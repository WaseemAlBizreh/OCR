import 'package:injectable/injectable.dart';
import 'package:mrz/features/identity_scan/data/front/parser_utils.dart';
import 'package:mrz/features/identity_scan/data/front/passport_viz_parser.dart';
import 'package:mrz/features/identity_scan/data/front/sudan_card_parser.dart';
import 'package:mrz/features/identity_scan/data/image/image_ops.dart';
import 'package:mrz/features/identity_scan/data/mrz/mrz_reader.dart';
import 'package:mrz/features/identity_scan/data/ocr/card_text_recognizer.dart';
import 'package:mrz/features/identity_scan/data/ocr/ocr_engine.dart';
import 'package:mrz/features/identity_scan/domain/document_kind.dart';
import 'package:mrz/features/identity_scan/domain/identity_scan_result.dart';
import 'package:mrz/features/identity_scan/domain/mrz_data.dart';

/// Runs the three layers over the captured pages:
///
/// 1. MRZ: validated machine-readable zone (the trusted source).
/// 2. Card text: Arabic fields from the printed side.
/// 3. Merge: one identity payload, cross-checked against the MRZ.
@lazySingleton
class IdentityScanService {
  IdentityScanService(
    this._imageOps,
    this._ocr,
    this._mrzReader,
  );

  static const _cardParser = SudanCardParser();
  static const _passportParser = PassportVizParser();

  final ImageOps _imageOps;
  final OcrEngine _ocr;
  final MrzReader _mrzReader;

  Future<void> discard(Iterable<String> paths) async {
    for (final path in paths) {
      await _imageOps.deleteTemp(path);
    }
  }

  /// [cardText] reads the printed Arabic/Latin fields; it defaults to the
  /// classic Tesseract engine. The MRZ is always read by [MrzReader].
  Future<IdentityScanResult> scan({
    required DocumentKind kind,
    required Map<DocumentSide, String> imagePaths,
    CardTextRecognizer? cardText,
    CardFields Function(String text)? parseFront,
    CardFields Function(String text)? parseBack,
    bool includeRawText = false,
  }) async {
    final recognizer = cardText ?? _ocr;
    final frontParser = parseFront ?? _cardParser.parseFront;
    final backParser = parseBack ?? _cardParser.parseBack;
    final warnings = <String>[];
    final rawText = <DocumentSide, String>{};

    final mrzSide =
        kind == DocumentKind.passport ? DocumentSide.dataPage : DocumentSide.back;
    final mrzRead = await _mrzReader.read(imagePaths[mrzSide]!, kind);
    final mrz = mrzRead.data;

    if (mrz == null) {
      warnings.add('MRZ not found. Align the MRZ band inside the frame and retake.');
    } else if (!mrz.isValid) {
      final failed = [
        for (final entry in mrz.checks.entries)
          if (!entry.value) entry.key,
      ];
      warnings.add('MRZ check digits failed: ${failed.join(', ')}. Retake or retry.');
    }

    CardFields? front;
    CardFields? back;
    if (kind == DocumentKind.sudanId) {
      final frontText =
          await recognizer.recognizeCardText(imagePaths[DocumentSide.front]!);
      final backText =
          await recognizer.recognizeCardText(imagePaths[DocumentSide.back]!);
      if (includeRawText) {
        rawText[DocumentSide.front] = frontText;
        rawText[DocumentSide.back] = backText;
      }
      front = frontParser(frontText);
      back = backParser(backText);
      warnings.addAll(front.warnings);
    }

    CardFields? dataPage;
    if (kind == DocumentKind.passport) {
      final text =
          await recognizer.recognizeCardText(imagePaths[DocumentSide.dataPage]!);
      rawText[DocumentSide.dataPage] = text;
      dataPage = _passportParser.parse(text, mrz: mrz);
      warnings.addAll(dataPage.warnings);
    }

    final identity = kind == DocumentKind.passport
        ? _mergePassport(mrz, dataPage?.fields, warnings)
        : _merge(mrz, front?.fields, back?.fields, warnings);

    return IdentityScanResult(
      documentKind: kind,
      identity: identity,
      frontFields: front?.fields,
      backFields: back?.fields,
      dataPageFields: dataPage?.fields,
      mrz: mrz,
      mrzAttempts: mrzRead.attempts,
      imagePaths: imagePaths,
      rawText: rawText,
      warnings: warnings.toSet().toList(),
    );
  }

  /// MRZ fields win when their own check digit passed; the printed fields fill
  /// the rest, and disagreements are reported as warnings.
  Map<String, dynamic> _merge(
    MrzData? mrz,
    Map<String, String?>? front,
    Map<String, String?>? back,
    List<String> warnings,
  ) {
    bool trusted(String check) => mrz?.checks[check] ?? false;

    String? crossChecked(
      String label,
      String? mrzValue,
      bool mrzTrusted,
      String? printed,
    ) =>
        _crossChecked(warnings, label, mrzValue, mrzTrusted, printed);

    final expiryDate = crossChecked(
      'Expiry date',
      mrz?.expiryDate,
      trusted('expiryDate'),
      back?['expiryDate'],
    );
    var issueDate = _toIsoDate(back?['issueDate']) ?? back?['issueDate'];
    // An issue date on or after the expiry date cannot be right (ISO dates
    // compare as text), so report nothing rather than a wrong date.
    if (issueDate != null && expiryDate != null && issueDate.compareTo(expiryDate) >= 0) {
      issueDate = null;
    }

    return {
      'documentType': mrz?.documentCode,
      'documentNumber': mrz?.documentNumber,
      'nationalNumber': front?['nationalNumber'],
      'arabicName': front?['arabicName'],
      'englishName': mrz?.fullName,
      'surname': mrz?.surname,
      'givenNames': mrz?.givenNames,
      'dateOfBirth': crossChecked(
        'Date of birth',
        mrz?.dateOfBirth,
        trusted('dateOfBirth'),
        front?['dateOfBirth'],
      ),
      'sex': mrz?.sex,
      'nationality': mrz?.nationality,
      'issuingCountry': mrz?.issuingCountry,
      'issueDate': issueDate,
      'expiryDate': expiryDate,
      'placeOfBirth': front?['placeOfBirth'],
      'placeOfIssue': back?['placeOfIssue'],
      'profession': front?['profession'],
      'address': front?['address'],
      'bloodType': front?['bloodType'],
      'phone': front?['phone'],
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
        warnings.add('$label on card ($printedIso) differs from MRZ ($mrzValue).');
      }
      return mrzValue;
    }
    return printedIso ?? printed ?? mrzValue;
  }

  /// Passport payload: the MRZ for everything it holds, the printed data page
  /// for what the MRZ lacks (place of birth, issue date and place, national
  /// number, Arabic name).
  Map<String, dynamic> _mergePassport(
    MrzData? mrz,
    Map<String, String?>? page,
    List<String> warnings,
  ) {
    bool trusted(String check) => mrz?.checks[check] ?? false;

    final expiryDate = _crossChecked(
      warnings,
      'Expiry date',
      mrz?.expiryDate,
      trusted('expiryDate'),
      page?['expiryDate'],
    );
    var issueDate = _toIsoDate(page?['issueDate']) ?? page?['issueDate'];
    if (issueDate != null && expiryDate != null && issueDate.compareTo(expiryDate) >= 0) {
      issueDate = null;
    }

    // Sudanese passports carry the national number in the MRZ personal-number
    // field as well as on the printed page.
    final mrzNational =
        trusted('personalNumber') && RegExp(r'^\d{11}$').hasMatch(mrz?.optionalData ?? '')
            ? mrz!.optionalData
            : null;
    final printedNational = page?['nationalNumber'];
    if (mrzNational != null && printedNational != null && mrzNational != printedNational) {
      warnings.add('National number on the page ($printedNational) differs from the MRZ ($mrzNational).');
    }

    return {
      'documentType': mrz?.documentCode,
      'documentNumber': mrz?.documentNumber ?? page?['passportNumber'],
      'nationalNumber': mrzNational ?? printedNational,
      'arabicName': page?['arabicName'],
      'englishName': mrz?.fullName,
      'surname': mrz?.surname,
      'givenNames': mrz?.givenNames,
      'dateOfBirth': _crossChecked(
        warnings,
        'Date of birth',
        mrz?.dateOfBirth,
        trusted('dateOfBirth'),
        page?['dateOfBirth'],
      ),
      'sex': mrz?.sex,
      'nationality': mrz?.nationality,
      'nationalityText': page?['nationalityText'],
      'issuingCountry': mrz?.issuingCountry,
      'issueDate': issueDate,
      'expiryDate': expiryDate,
      'placeOfBirth': page?['placeOfBirth'],
      'placeOfBirthArabic': page?['placeOfBirthArabic'],
      'placeOfIssue': page?['placeOfIssue'],
      'placeOfIssueArabic': page?['placeOfIssueArabic'],
    };
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
