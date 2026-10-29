import 'package:injectable/injectable.dart';
import 'package:mrz/features/identity_scan/data/front/card_dates.dart';
import 'package:mrz/features/identity_scan/data/image/image_ops.dart';
import 'package:mrz/features/identity_scan/data/ocr/paddle/civil_registry/certificate_labels.dart';
import 'package:mrz/features/identity_scan/data/ocr/paddle/civil_registry/civil_registry_parser.dart';
import 'package:mrz/features/identity_scan/data/ocr/paddle/civil_registry/civil_registry_result.dart';
import 'package:mrz/features/identity_scan/data/ocr/paddle/civil_registry/civil_registry_text_reader.dart';

/// Reads a civil registry certificate (A4) with ML Kit + Paddle only.
///
/// The page is read as photographed; when a key field is missing the contrast-
/// enhanced copy is read too and the better of the two is kept.
@lazySingleton
class CivilRegistryScanService {
  CivilRegistryScanService(this._reader, this._imageOps);

  static const _parser = CivilRegistryParser();

  /// Fields without which a read is considered incomplete.
  static final _key = [
    CertificateField.nationalNumber.name,
    CertificateField.name.name,
    CertificateField.dateOfBirth.name,
  ];

  final CivilRegistryTextReader _reader;
  final ImageOps _imageOps;

  Future<CivilRegistryResult> scan(String pagePath) async {
    final text = await _reader.read(pagePath);
    var chosen = text;
    var page = _parser.parse(text.lines);
    var raw = text.flat;
    var rawMlKit = text.mlkitText;

    if (_missingKey(page)) {
      String? enhancedPath;
      try {
        enhancedPath = await _imageOps.enhance(pagePath, label: 'certificate_enhanced');
        final retryText = await _reader.read(enhancedPath);
        final retry = _parser.parse(retryText.lines);
        if (_found(retry) > _found(page)) {
          page = retry;
          chosen = retryText;
          raw = retryText.flat;
          rawMlKit = retryText.mlkitText;
        }
      } finally {
        if (enhancedPath != null) await _imageOps.deleteTemp(enhancedPath);
      }
    }

    // Digits are sometimes printed small or on a textured background, and
    // neither engine reads them from the full page. Such a row is cropped and
    // read on its own.
    var fields = page.fields;
    var warnings = page.warnings;
    for (final reread in _rereads) {
      if (fields[reread.key] != null) continue;
      final result = await _rereadRow(pagePath, chosen, reread, fields);
      rawMlKit = '$rawMlKit\n--- ${reread.key} row ---\n${result.text}';
      if (result.value != null) {
        fields = {...fields, reread.key: result.value};
        warnings = [
          for (final w in warnings)
            if (w != 'Missing field: ${reread.key}') w,
        ];
      }
    }

    return CivilRegistryResult(
      fields: fields,
      confidence: page.confidence,
      warnings: warnings,
      imagePath: pagePath,
      rawText: raw,
      rawMlKit: rawMlKit,
    );
  }

  /// Fields whose row is read again when the full-page pass found no value.
  static final _rereads = [
    _Reread(CertificateField.nationalNumber, CivilRegistryParser.nationalNumber),
    _Reread(CertificateField.issueDate, _dateOf, accept: _afterBirth),
  ];

  static String? _dateOf(String line) {
    final dates = CardDates.datesIn(line);
    return dates.isEmpty ? null : CardDates.iso(dates.first);
  }

  /// An issue date cannot be on or before the birth date; this also rejects
  /// the birth date itself when a crop reaches into the next row.
  static bool _afterBirth(String value, Map<String, String?> fields) {
    final birth = fields[CertificateField.dateOfBirth.name];
    return birth == null || value.compareTo(birth) > 0;
  }

  /// Reads [reread]'s row again from crops of the photo: the whole row and the
  /// value half of the label's box, each as is and contrast-boosted, upscaled
  /// so the digits are tall enough for ML Kit.
  Future<({String? value, String text})> _rereadRow(
    String pagePath,
    CertificateText text,
    _Reread reread,
    Map<String, String?> fields,
  ) async {
    final label = _parser.labelLine(reread.field, text.lines);
    if (label == null) return (value: null, text: 'label not found');

    final pad = label.height * 0.4;
    final top = label.top - pad;
    final bottom = label.bottom + pad;
    final strips = [
      (left: 0.0, right: 100000.0), // the whole row
      (left: label.left, right: label.left + label.width * 0.65), // value side
      (left: 0.0, right: label.left + label.width * 0.65),
    ];
    final seen = StringBuffer();
    for (final strip in strips) {
      for (final enhance in [false, true]) {
        String? crop;
        try {
          crop = await _imageOps.cropPixels(
            pagePath,
            left: strip.left,
            top: top,
            right: strip.right,
            bottom: bottom,
            minWidth: 1400,
            enhance: enhance,
            label: 'certificate_row',
          );
          final read = await _reader.readMlKitText(crop);
          seen.writeln(read.replaceAll('\n', ' | '));
          for (final line in read.split('\n')) {
            final value = reread.extract(line);
            if (value != null && (reread.accept?.call(value, fields) ?? true)) {
              return (value: value, text: seen.toString());
            }
          }
        } finally {
          if (crop != null) await _imageOps.deleteTemp(crop);
        }
      }
    }
    return (value: null, text: seen.toString());
  }

  static bool _missingKey(CertificatePage page) =>
      _key.any((k) => page.fields[k] == null);

  static int _found(CertificatePage page) =>
      page.fields.values.where((v) => v != null).length;
}

class _Reread {
  const _Reread(this.field, this.extract, {this.accept});

  final CertificateField field;
  final String? Function(String line) extract;

  /// Extra check on a found value, given the fields read so far.
  final bool Function(String value, Map<String, String?> fields)? accept;

  String get key => field.name;
}
