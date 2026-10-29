import 'package:injectable/injectable.dart';
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

    // The number is printed small or on a textured background; neither engine
    // reads it from the full page, so its row is cropped and read on its own.
    var fields = page.fields;
    var warnings = page.warnings;
    if (fields[_numberKey] == null) {
      final reread = await _rereadNumber(pagePath, chosen);
      rawMlKit = '$rawMlKit\n--- national number row ---\n${reread.text}';
      if (reread.number != null) {
        fields = {...fields, _numberKey: reread.number};
        warnings = [
          for (final w in warnings)
            if (w != 'Missing field: $_numberKey') w,
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

  static final _numberKey = CertificateField.nationalNumber.name;

  /// Reads the national-number row again from crops of the photo: the whole
  /// row and the value half of the label's box, each as is and contrast-
  /// boosted, upscaled so the digits are tall enough for ML Kit.
  Future<({String? number, String text})> _rereadNumber(
    String pagePath,
    CertificateText text,
  ) async {
    final label = _parser.labelLine(CertificateField.nationalNumber, text.lines);
    if (label == null) return (number: null, text: 'label not found');

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
            label: 'certificate_number',
          );
          final read = await _reader.readMlKitText(crop);
          seen.writeln(read.replaceAll('\n', ' | '));
          for (final line in read.split('\n')) {
            final number = CivilRegistryParser.nationalNumber(line);
            if (number != null) return (number: number, text: seen.toString());
          }
        } finally {
          if (crop != null) await _imageOps.deleteTemp(crop);
        }
      }
    }
    return (number: null, text: seen.toString());
  }

  static bool _missingKey(CertificatePage page) =>
      _key.any((k) => page.fields[k] == null);

  static int _found(CertificatePage page) =>
      page.fields.values.where((v) => v != null).length;
}
