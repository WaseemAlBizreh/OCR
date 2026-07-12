import 'package:mrz/features/arabic_document_scan/data/parsers/country_parser.dart';
import 'package:mrz/features/arabic_document_scan/data/parsers/parser_utils.dart';
import 'package:mrz/features/arabic_document_scan/data/parsers/sudan_id_template.dart';
import 'package:mrz/features/arabic_document_scan/domain/document_scan_result.dart';
import 'package:mrz/features/arabic_document_scan/domain/document_type.dart';

class SudanIdTemplateParser implements CountryParser {
  SudanIdTemplateParser({SudanIdTemplate? template})
      : _template = template ?? const SudanIdTemplate();

  final SudanIdTemplate _template;

  static final _nationalNumber = RegExp(r'\b\d{10}\b');
  static final _phone = RegExp(r'(?:ت\s*/\s*)?0?\d{9,10}');
  static final _bloodType = RegExp(r'\b[ABO][+-]\b', caseSensitive: false);

  @override
  String get countryCode => _template.countryCode;

  @override
  DocumentScanResult parse(
    String ocrText, {
    required String imagePath,
    OcrEngineComparison? ocrComparison,
  }) {
    final normalized = ParserUtils.normalizeDigits(ocrText);

    final arabicName = _extractArabicField(
      ocrText,
      labels: _template.fieldLabels['arabicName']!,
      minWords: 3,
    );

    final nationalNumber = ParserUtils.extractLabeledValue(
          ocrText,
          labels: _template.fieldLabels['nationalNumber']!,
          valuePattern: _nationalNumber,
        ) ??
        _nationalNumber.allMatches(normalized).map((match) => match.group(0)).firstOrNull;

    final dateOfBirth = ParserUtils.extractDate(
      ocrText,
      _template.fieldLabels['dateOfBirth']!,
    );

    final placeOfBirth = _extractArabicField(
      ocrText,
      labels: _template.fieldLabels['placeOfBirth']!,
    );

    final bloodType = ParserUtils.extractLabeledValue(
      ocrText,
      labels: _template.fieldLabels['bloodType']!,
      valuePattern: _bloodType,
    );

    final profession = _extractArabicField(
      ocrText,
      labels: _template.fieldLabels['profession']!,
    );

    final address = _extractArabicField(
      ocrText,
      labels: _template.fieldLabels['address']!,
      minWords: 2,
    );

    final phone = ParserUtils.extractLabeledValue(
      ocrText,
      labels: _template.fieldLabels['phone']!,
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

    final warnings = ParserUtils.collectWarnings(fields, SudanIdTemplate.requiredFields);

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

  String? _extractArabicField(
    String ocrText, {
    required List<String> labels,
    int minWords = 1,
  }) {
    return ParserUtils.extractLabeledValue(
          ocrText,
          labels: labels,
          arabicValue: true,
        ) ??
        ParserUtils.extractArabicColonValue(
          ocrText,
          minWords: minWords,
        );
  }
}