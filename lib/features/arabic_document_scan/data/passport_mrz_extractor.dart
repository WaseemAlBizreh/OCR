import 'dart:convert';

import 'package:injectable/injectable.dart';
import 'package:mrz/features/arabic_document_scan/data/arabic_ocr_engine.dart';
import 'package:mrz/features/arabic_document_scan/data/ocr_debug_log.dart';
import 'package:mrz/features/arabic_document_scan/data/parsers/sudan_passport_parser.dart';
import 'package:mrz/features/arabic_document_scan/domain/document_scan_result.dart';
import 'package:mrz/features/arabic_document_scan/domain/document_type.dart';
import 'package:mrz_scanner_plus/mrz_scanner_plus.dart';

@lazySingleton
class PassportMrzExtractor {
  PassportMrzExtractor(this._ocrEngine);

  final ArabicOcrEngine _ocrEngine;

  Future<DocumentScanResult> extract({
    required String imagePath,
    String? countryCode,
  }) async {
    if (countryCode == 'sd') {
      final comparison = await _ocrEngine.compareEngines(imagePath);
      final ocrText = _ocrEngine.mergeForArabicParsing(comparison) ?? '';

      logRawOcrBeforeParsing(
        context: 'passport/sd',
        mergedText: ocrText,
        tesseractText: comparison.tesseractText,
        mlKitText: comparison.mlKitText,
      );

      return SudanPassportParser().parse(
        ocrText: ocrText,
        imagePath: imagePath,
        ocrComparison: comparison,
      );
    }

    return _extractGenericPassport(imagePath);
  }

  Future<DocumentScanResult> _extractGenericPassport(String imagePath) async {
    final warnings = <String>[];
    final jsonPayload =
        await MrzScanResultBuilder.buildPassportPayloadFromImage(
      imagePath: imagePath,
    );

    if (jsonPayload == null) {
      return DocumentScanResult(
        documentType: DocumentType.passport,
        fields: const {},
        imagePath: imagePath,
        warnings: const [
          'Passport MRZ not found. Align the MRZ band and retake.',
        ],
      );
    }

    final payload = jsonDecode(jsonPayload) as Map<String, dynamic>;
    final mrzResult = payload['mrzResult'] as Map<String, dynamic>?;
    final frontText = payload['frontText'] as String?;

    logRawOcrBeforeParsing(
      context: 'passport/mrz',
      mergedText: frontText,
    );

    if (mrzResult == null) {
      warnings.add('MRZ parsing returned empty result.');
    }

    return DocumentScanResult(
      documentType: DocumentType.passport,
      fields: {
        'documentNumber': payload['documentNumber'] ?? mrzResult?['documentNumber'],
        'issueDate': payload['issueDate'],
        'expiryDate': payload['expiryDate'] ?? mrzResult?['expiryDate'],
        'surname': mrzResult?['surnames'],
        'givenNames': mrzResult?['givenNames'],
        'nationality': mrzResult?['nationalityCountryCode'],
        'dateOfBirth': mrzResult?['birthDate'],
        'sex': mrzResult?['sex'],
        'documentType': mrzResult?['documentType'],
      },
      rawOcrText: frontText,
      imagePath: imagePath,
      mrzResult: mrzResult,
      warnings: warnings,
    );
  }
}
