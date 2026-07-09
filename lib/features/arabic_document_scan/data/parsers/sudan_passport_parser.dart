import 'dart:convert';

import 'package:mrz/features/arabic_document_scan/data/parsers/parser_utils.dart';
import 'package:mrz/features/arabic_document_scan/domain/document_scan_result.dart';
import 'package:mrz/features/arabic_document_scan/domain/document_type.dart';
import 'package:mrz_scanner_plus/mrz_scanner_plus.dart';

class SudanPassportParser {
  static final _passportNumber = RegExp(r'\bP\d{8}\b');
  static final _nationalNumber = RegExp(r'\b\d{3}-\d{4}-\d{4}\b');
  static final _dateDmy = RegExp(r'\b(\d{2}-\d{2}-\d{4})\b');

  Future<DocumentScanResult> parse({
    required String ocrText,
    required String imagePath,
    OcrEngineComparison? ocrComparison,
  }) async {
    final normalized = ParserUtils.normalizeDigits(ocrText);
    final warnings = <String>[];

    Map<String, dynamic>? mrzResult;
    final mrzPayload = await MrzScanResultBuilder.buildPassportPayloadFromImage(
      imagePath: imagePath,
      frontText: ocrText,
    );

    if (mrzPayload != null) {
      final payload = jsonDecode(mrzPayload) as Map<String, dynamic>;
      mrzResult = payload['mrzResult'] as Map<String, dynamic>?;
    } else {
      warnings.add('Passport MRZ not found — align the MRZ band and retake.');
    }

    final passportType = ParserUtils.extractLabeledValue(
      ocrText,
      labels: const ['Passport Type', 'نوع الجواز'],
      valuePattern: RegExp(r'\b(PC|P)\b'),
    );

    final countryCode = ParserUtils.extractLabeledValue(
      ocrText,
      labels: const ['Country Code', 'رمز الدولة'],
      valuePattern: RegExp(r'\b(SDN|UAE|ARE)\b'),
    );

    final passportNumber = ParserUtils.extractLabeledValue(
      ocrText,
      labels: const ['Passport No', 'رقم الجواز', 'Passport No.'],
      valuePattern: _passportNumber,
    ) ??
        mrzResult?['documentNumber']?.toString() ??
        _passportNumber.firstMatch(normalized)?.group(0);

    final fullNameEnglish = ParserUtils.extractLabeledValue(
      ocrText,
      labels: const ['Full Name', 'الاسم الكامل'],
      valuePattern: RegExp(r'([A-Z][A-Z\s]{4,})'),
    );

    final fullNameArabic = ParserUtils.extractLabeledValue(
      ocrText,
      labels: const ['الاسم الكامل', 'Full Name'],
      arabicValue: true,
    );

    final nationalityEnglish = ParserUtils.extractLabeledValue(
      ocrText,
      labels: const ['Nationality', 'الجنسية'],
      valuePattern: RegExp(r'\b(SDN|Sudan)\b', caseSensitive: false),
    );

    final nationalityArabic = ParserUtils.extractLabeledValue(
      ocrText,
      labels: const ['الجنسية', 'Nationality'],
      arabicValue: true,
    );

    final nationalNumber = ParserUtils.extractLabeledValue(
      ocrText,
      labels: const ['National No', 'الرقم الوطني'],
      valuePattern: _nationalNumber,
    );

    final placeOfBirthEnglish = ParserUtils.extractLabeledValue(
      ocrText,
      labels: const ['Place of Birth', 'مكان الميلاد'],
      valuePattern: RegExp(r'([A-Z][A-Z\s]{2,})'),
    );

    final placeOfBirthArabic = ParserUtils.extractLabeledValue(
      ocrText,
      labels: const ['مكان الميلاد'],
      arabicValue: true,
    );

    final dateOfBirth = ParserUtils.extractLabeledValue(
      ocrText,
      labels: const ['Date of Birth', 'تاريخ الميلاد'],
      valuePattern: _dateDmy,
    ) ??
        mrzResult?['birthDate'];

    final sex = ParserUtils.extractGender(ocrText) ?? mrzResult?['sex'];

    final issueDate = ParserUtils.extractLabeledValue(
      ocrText,
      labels: const ['Date of Issue', 'تاريخ الإصدار'],
      valuePattern: _dateDmy,
    );

    final placeOfIssueEnglish = ParserUtils.extractLabeledValue(
      ocrText,
      labels: const ['Place of Issue', 'مكان الإصدار'],
      valuePattern: RegExp(r'([A-Z][A-Z\s]{2,})'),
    );

    final placeOfIssueArabic = ParserUtils.extractLabeledValue(
      ocrText,
      labels: const ['مكان الإصدار'],
      arabicValue: true,
    );

    final expiryDate = ParserUtils.extractLabeledValue(
      ocrText,
      labels: const ['Date of Expiry', 'تاريخ الصلاحية'],
      valuePattern: _dateDmy,
    ) ??
        mrzResult?['expiryDate'];

    final fields = {
      'passportType': passportType ?? mrzResult?['documentType'],
      'countryCode': countryCode ?? mrzResult?['nationalityCountryCode'],
      'passportNumber': passportNumber,
      'fullNameEnglish': fullNameEnglish ??
          _nameFromMrz(mrzResult?['givenNames'], mrzResult?['surnames']),
      'fullNameArabic': fullNameArabic,
      'nationalityEnglish': nationalityEnglish ?? mrzResult?['nationalityCountryCode'],
      'nationalityArabic': nationalityArabic,
      'nationalNumber': nationalNumber,
      'placeOfBirthEnglish': placeOfBirthEnglish,
      'placeOfBirthArabic': placeOfBirthArabic,
      'dateOfBirth': dateOfBirth,
      'sex': sex,
      'issueDate': issueDate,
      'placeOfIssueEnglish': placeOfIssueEnglish,
      'placeOfIssueArabic': placeOfIssueArabic,
      'expiryDate': expiryDate,
      'surname': mrzResult?['surnames'],
      'givenNames': mrzResult?['givenNames'],
    };

    warnings.addAll(
      ParserUtils.collectWarnings(
        fields,
        const ['passportNumber', 'fullNameEnglish', 'dateOfBirth', 'expiryDate'],
      ),
    );

    return DocumentScanResult(
      documentType: DocumentType.passport,
      countryCode: 'sd',
      fields: fields,
      rawOcrText: ocrText,
      imagePath: imagePath,
      mrzResult: mrzResult,
      warnings: warnings.toSet().toList(),
      ocrComparison: ocrComparison,
    );
  }

  String? _nameFromMrz(dynamic givenNames, dynamic surnames) {
    final given = givenNames?.toString().trim();
    final surname = surnames?.toString().trim();
    if (given == null && surname == null) return null;
    if (surname == null) return given;
    if (given == null) return surname;
    return '$given $surname'.trim();
  }
}
