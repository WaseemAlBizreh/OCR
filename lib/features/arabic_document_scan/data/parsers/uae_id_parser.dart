import 'package:mrz/features/arabic_document_scan/data/parsers/country_parser.dart';
import 'package:mrz/features/arabic_document_scan/data/parsers/parser_utils.dart';
import 'package:mrz/features/arabic_document_scan/domain/document_scan_result.dart';
import 'package:mrz/features/arabic_document_scan/domain/document_type.dart';

class UaeIdParser implements CountryParser {
  @override
  String get countryCode => 'ae';

  static final _emiratesId = RegExp(r'\b784-\d{4}-\d{7}-\d\b');
  static final _dateDmy = RegExp(r'\b(\d{2}/\d{2}/\d{4})\b');

  @override
  DocumentScanResult parse(
    String ocrText, {
    required String imagePath,
    OcrEngineComparison? ocrComparison,
  }) {
    final normalized = ParserUtils.normalizeDigits(ocrText);

    final idNumber = _emiratesId.firstMatch(normalized)?.group(0) ??
        ParserUtils.extractLabeledValue(
          ocrText,
          labels: const ['ID Number', 'رقم الهوية'],
          valuePattern: _emiratesId,
        );

    final arabicName = ParserUtils.extractLabeledValue(
      ocrText,
      labels: const [':الاسم', 'الاسم', ':الإسم', 'الإسم'],
      arabicValue: true,
    );

    final englishName = ParserUtils.extractLabeledValue(
      ocrText,
      labels: const ['Name:', 'Name :', 'Name'],
      valuePattern: RegExp(r'([A-Za-z][A-Za-z\s]{4,})'),
    );

    final dateOfBirth = ParserUtils.extractDate(
      ocrText,
      const ['Date of Birth', 'تاريخ الميلاد', ':تاريخ الميلاد'],
    ) ??
        _dateDmy
            .allMatches(normalized)
            .map((m) => m.group(0))
            .firstOrNull;

    final nationalityArabic = ParserUtils.extractLabeledValue(
      ocrText,
      labels: const [':الجنسية', 'الجنسية'],
      arabicValue: true,
    );

    final nationalityEnglish = ParserUtils.extractLabeledValue(
      ocrText,
      labels: const ['Nationality:', 'Nationality'],
      valuePattern: RegExp(r'([A-Za-z][A-Za-z\s]{2,})'),
    );

    final issuingDate = ParserUtils.extractDate(
      ocrText,
      const ['Issuing Date', 'تاريخ الاصدار', 'تاريخ الإصدار'],
    );

    final expiryDate = ParserUtils.extractDate(
      ocrText,
      const ['Expiry Date', 'تاريخ الانتهاء', 'تاريخ الإنتهاء'],
    );

    final sex = ParserUtils.extractGender(ocrText);

    final fields = {
      'idNumber': idNumber,
      'arabicName': arabicName,
      'englishName': englishName,
      'dateOfBirth': dateOfBirth,
      'nationalityArabic': nationalityArabic,
      'nationalityEnglish': nationalityEnglish,
      'issuingDate': issuingDate,
      'expiryDate': expiryDate,
      'sex': sex,
    };

    final warnings = ParserUtils.collectWarnings(
      fields,
      const ['idNumber', 'arabicName', 'englishName', 'dateOfBirth'],
    );

    return DocumentScanResult(
      documentType: DocumentType.arabicId,
      countryCode: countryCode,
      fields: fields,
      rawOcrText: ocrText,
      imagePath: imagePath,
      warnings: warnings,
      ocrComparison: ocrComparison,
    );
  }
}
