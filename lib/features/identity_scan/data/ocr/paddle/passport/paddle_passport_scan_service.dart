import 'package:injectable/injectable.dart';
import 'package:mrz/features/identity_scan/data/front/parser_utils.dart';
import 'package:mrz/features/identity_scan/data/ocr/paddle/passport/country_names.dart';
import 'package:mrz/features/identity_scan/data/ocr/paddle/passport/mlkit_latin_reader.dart';
import 'package:mrz/features/identity_scan/data/ocr/paddle/passport/paddle_passport_mrz_reader.dart';
import 'package:mrz/features/identity_scan/data/ocr/paddle/passport/paddle_passport_parser.dart';
import 'package:mrz/features/identity_scan/data/ocr/paddle/passport/paddle_passport_text_reader.dart';
import 'package:mrz/features/identity_scan/domain/document_kind.dart';
import 'package:mrz/features/identity_scan/domain/identity_scan_result.dart';
import 'package:mrz/features/identity_scan/domain/mrz_data.dart';

/// Reads any passport's data page with ML Kit + Paddle, without Tesseract.
///
/// 1. MRZ: validated machine-readable zone (the trusted source).
/// 2. Printed page: whatever labelled fields can be located, any country.
/// 3. Merge: one identity payload, cross-checked against the MRZ.
///
/// Self-contained on purpose: it shares nothing with the classic scan service,
/// so the Paddle and Tesseract code can be shipped separately.
@lazySingleton
class PaddlePassportScanService {
  PaddlePassportScanService(this._mlkit, this._mrzReader, this._textReader);

  static const _parser = PaddlePassportParser();

  final MlKitLatinReader _mlkit;
  final PaddlePassportMrzReader _mrzReader;
  final PaddlePassportTextReader _textReader;

  Future<IdentityScanResult> scan(String dataPagePath) async {
    final page = await _mlkit.read(dataPagePath); // read once, used twice
    final mrzRead = await _mrzReader.read(dataPagePath, page: page);
    final mrz = mrzRead.data;
    final text = await _textReader.read(dataPagePath, mlkit: page);
    final printed = _parser.parse(text.lines, mrz: mrz);

    final warnings = <String>[..._mrzWarnings(mrz), ...printed.warnings];
    final identity = _merge(mrz, printed.fields, warnings);

    return IdentityScanResult(
      documentKind: DocumentKind.passport,
      identity: identity,
      dataPageFields: printed.fields,
      mrz: mrz,
      mrzAttempts: mrzRead.attempts,
      imagePaths: {DocumentSide.dataPage: dataPagePath},
      rawText: {DocumentSide.dataPage: text.flat},
      warnings: warnings.toSet().toList(),
    );
  }

  static List<String> _mrzWarnings(MrzData? mrz) {
    if (mrz == null) {
      return ['MRZ not found. Align the MRZ band inside the frame and retake.'];
    }
    if (mrz.isValid) return const [];
    final failed = [
      for (final entry in mrz.checks.entries)
        if (!entry.value) entry.key,
    ];
    return ['MRZ check digits failed: ${failed.join(', ')}. Retake or retry.'];
  }

  /// MRZ fields win when their own check digit passed; the printed fields fill
  /// the rest, and disagreements are reported as warnings.
  Map<String, dynamic> _merge(
    MrzData? mrz,
    Map<String, String?> page,
    List<String> warnings,
  ) {
    bool trusted(String check) => mrz?.checks[check] ?? false;

    final expiryDate = _crossChecked(
      warnings,
      'Expiry date',
      mrz?.expiryDate,
      trusted('expiryDate'),
      page['expiryDate'],
    );
    var issueDate = _toIsoDate(page['issueDate']) ?? page['issueDate'];
    // An issue date on or after the expiry date cannot be right (ISO dates
    // compare as text), so report nothing rather than a wrong date.
    if (issueDate != null && expiryDate != null && issueDate.compareTo(expiryDate) >= 0) {
      issueDate = null;
    }

    final personalNumber = trusted('personalNumber') && (mrz?.optionalData ?? '').isNotEmpty
        ? mrz!.optionalData
        : null;
    // Some issuers (Sudan, for one) put the national number in the MRZ
    // personal-number field; accept it only when it looks like a number.
    final mrzNational =
        personalNumber != null && RegExp(r'^\d{8,16}$').hasMatch(personalNumber)
            ? personalNumber
            : null;
    final printedNational = page['nationalNumber'];
    if (mrzNational != null && printedNational != null && mrzNational != printedNational) {
      warnings.add('National number on the page ($printedNational) differs from the MRZ ($mrzNational).');
    }

    return {
      'documentType': mrz?.documentCode,
      'documentNumber': mrz?.documentNumber ?? page['passportNumber'],
      'nationalNumber': mrzNational ?? printedNational,
      'personalNumber': personalNumber,
      'arabicName': page['arabicName'],
      'englishName': mrz?.fullName ?? page['englishName'],
      'surname': mrz?.surname,
      'givenNames': mrz?.givenNames,
      'dateOfBirth': _crossChecked(
        warnings,
        'Date of birth',
        mrz?.dateOfBirth,
        trusted('dateOfBirth'),
        page['dateOfBirth'],
      ),
      'sex': mrz?.sex,
      'nationality': mrz?.nationality,
      'nationalityText': page['nationalityText'] ?? countryName(mrz?.nationality),
      'nationalityTextArabic': page['nationalityTextArabic'],
      'issuingCountry': mrz?.issuingCountry,
      'issuingCountryName': countryName(mrz?.issuingCountry),
      'issueDate': issueDate,
      'expiryDate': expiryDate,
      'placeOfBirth': page['placeOfBirth'],
      'placeOfBirthArabic': page['placeOfBirthArabic'],
      'placeOfIssue': page['placeOfIssue'],
      'placeOfIssueArabic': page['placeOfIssueArabic'],
    };
  }

  /// The MRZ value when its own check digit passed (a differing printed value
  /// becomes a warning); otherwise the printed value, then the MRZ value.
  static String? _crossChecked(
    List<String> warnings,
    String label,
    String? mrzValue,
    bool mrzTrusted,
    String? printed,
  ) {
    final printedIso = _toIsoDate(printed);
    if (mrzTrusted && mrzValue != null) {
      if (printedIso != null && printedIso != mrzValue) {
        warnings.add('$label on the page ($printedIso) differs from the MRZ ($mrzValue).');
      }
      return mrzValue;
    }
    return printedIso ?? printed ?? mrzValue;
  }

  static final _ymd = RegExp(r'^(\d{4})[/.-](\d{1,2})[/.-](\d{1,2})$');
  static final _dmy = RegExp(r'^(\d{1,2})[/.-](\d{1,2})[/.-](\d{4})$');

  static String? _toIsoDate(String? raw) {
    if (raw == null) return null;
    final value = ParserUtils.normalizeDigits(raw.trim());
    String two(String s) => s.padLeft(2, '0');
    final ymd = _ymd.firstMatch(value);
    if (ymd != null) return '${ymd[1]}-${two(ymd[2]!)}-${two(ymd[3]!)}';
    final dmy = _dmy.firstMatch(value);
    if (dmy != null) return '${dmy[3]}-${two(dmy[2]!)}-${two(dmy[1]!)}';
    return null;
  }
}
