import 'package:mrz/features/arabic_document_scan/data/parsers/country_parser.dart';
import 'package:mrz/features/arabic_document_scan/data/parsers/parser_utils.dart';
import 'package:mrz/features/arabic_document_scan/domain/document_scan_result.dart';
import 'package:mrz/features/arabic_document_scan/domain/document_type.dart';

class SudanIdFrontParser implements CountryParser {
  @override
  String get countryCode => 'sd';

  static final _nationalNumber = RegExp(r'\b\d{10}\b');
  static final _phone = RegExp(r'(?:ت\s*/\s*)?0?\d{9,10}');
  static final _bloodType = RegExp(r'\b[ABO][+-]\b', caseSensitive: false);

  @override
  DocumentScanResult parse(
    String ocrText, {
    required String imagePath,
    OcrEngineComparison? ocrComparison,
  }) {
    final normalized = ParserUtils.normalizeDigits(ocrText);

    final arabicName = ParserUtils.extractLabeledValue(
      ocrText,
      labels: const ['الإسم', 'الاسم', ':الإسم', ':الاسم'],
      arabicValue: true,
    ) ??
        ParserUtils.extractArabicColonValue(ocrText, minWords: 3);

    final nationalNumber = ParserUtils.extractLabeledValue(
      ocrText,
      labels: const ['الرقم الوطني', 'الرقم القومي'],
      valuePattern: _nationalNumber,
    ) ??
        _nationalNumber.allMatches(normalized).map((m) => m.group(0)).firstOrNull;

    final dateOfBirth = ParserUtils.extractDate(
      ocrText,
      const ['تاريخ الميلاد'],
    );

    final placeOfBirth = ParserUtils.extractLabeledValue(
      ocrText,
      labels: const ['مكان الميلاد'],
      arabicValue: true,
    );

    final bloodType = ParserUtils.extractLabeledValue(
      ocrText,
      labels: const ['فصيلة الدم'],
      valuePattern: _bloodType,
    );

    final profession = ParserUtils.extractLabeledValue(
      ocrText,
      labels: const ['المهنة'],
      arabicValue: true,
    );

    final address = ParserUtils.extractLabeledValue(
      ocrText,
      labels: const ['العنوان'],
      arabicValue: true,
    );

    final phone = ParserUtils.extractLabeledValue(
      ocrText,
      labels: const ['ت /', 'ت/', 'هاتف', 'Tel'],
      valuePattern: _phone,
    );

    final fields = {
      'cardSide': 'front',
      'arabicName': arabicName,
      'nationalNumber': nationalNumber,
      'dateOfBirth': dateOfBirth,
      'placeOfBirth': placeOfBirth,
      'bloodType': bloodType,
      'profession': profession,
      'address': address,
      'phone': phone,
    };

    final warnings = ParserUtils.collectWarnings(
      fields,
      const ['arabicName', 'nationalNumber', 'dateOfBirth'],
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
