import 'dart:convert';

import 'package:mrz/features/arabic_document_scan/data/parsers/parser_utils.dart';
import 'package:mrz/features/arabic_document_scan/domain/document_scan_result.dart';
import 'package:mrz/features/arabic_document_scan/domain/document_type.dart';
import 'package:mrz_scanner_plus/mrz_scanner_plus.dart';

class SudanIdBackParser {
  String get countryCode => 'sd';

  static final _serialNumber = RegExp(r'\b\d{9}\b');

  Future<DocumentScanResult> parseAsync(
    String ocrText, {
    required String imagePath,
    OcrEngineComparison? ocrComparison,
  }) async {
    final placeOfIssue = ParserUtils.extractLabeledValue(
      ocrText,
      labels: const ['مكان الإصدار', 'مكان الاصدار'],
      arabicValue: true,
    );

    final issueDate = ParserUtils.extractDate(
      ocrText,
      const ['تاريخ الإصدار', 'تاريخ الاصدار'],
    );

    final expiryDate = ParserUtils.extractDate(
      ocrText,
      const ['تاريخ الإنتهاء', 'تاريخ الانتهاء', 'تاريخ الانتها'],
    );

    final englishName = ParserUtils.extractEnglishNameLine(ocrText);

    final serialNumber = ParserUtils.extractLabeledValue(
      ocrText,
      labels: const [],
      valuePattern: _serialNumber,
    );

    Map<String, dynamic>? mrzResult;
    final warnings = <String>[];

    final mrzPayload = await MrzScanResultBuilder.buildBackMrzPayloadFromImage(
      imagePath: imagePath,
    );

    if (mrzPayload != null) {
      final payload = jsonDecode(mrzPayload) as Map<String, dynamic>;
      mrzResult = payload['mrzResult'] as Map<String, dynamic>?;
    } else {
      warnings.add('MRZ not found on ID back — align the MRZ band and retake.');
    }

    final fields = {
      'cardSide': 'back',
      'serialNumber': serialNumber ?? mrzResult?['documentNumber'],
      'englishName': englishName ??
          _nameFromMrz(mrzResult?['surnames'], mrzResult?['givenNames']),
      'placeOfIssue': placeOfIssue,
      'issueDate': issueDate ?? mrzResult?['issueDate'],
      'expiryDate': expiryDate ?? mrzResult?['expiryDate'],
      'dateOfBirth': mrzResult?['birthDate'],
      'sex': mrzResult?['sex'],
      'nationality': mrzResult?['nationalityCountryCode'],
    };

    warnings.addAll(
      ParserUtils.collectWarnings(
        fields,
        const ['englishName', 'issueDate', 'expiryDate'],
      ),
    );

    return DocumentScanResult(
      documentType: DocumentType.arabicId,
      countryCode: countryCode,
      fields: fields,
      rawOcrText: ocrText,
      imagePath: imagePath,
      mrzResult: mrzResult,
      warnings: warnings.toSet().toList(),
      ocrComparison: ocrComparison,
    );
  }

  String? _nameFromMrz(dynamic surnames, dynamic givenNames) {
    final surname = surnames?.toString().trim();
    final given = givenNames?.toString().trim();
    if (surname == null && given == null) return null;
    if (surname == null) return given;
    if (given == null) return surname;
    return '$given $surname'.trim();
  }
}
