import 'package:flutter_ocr_identity_extractor/flutter_ocr_identity_extractor.dart';
import 'package:injectable/injectable.dart';
import 'package:mrz/features/arabic_document_scan/domain/document_scan_result.dart';
import 'package:mrz/features/arabic_document_scan/domain/document_type.dart';

@lazySingleton
class SaudiIdExtractor {
  Future<DocumentScanResult> extract({
    required String imagePath,
    OcrEngineComparison? ocrComparison,
    String? ocrTextOverride,
  }) async {
    final warnings = <String>[];
    final ocrText = ocrTextOverride?.trim();

    if (ocrText == null || ocrText.isEmpty) {
      return DocumentScanResult(
        documentType: DocumentType.saudiId,
        countryCode: 'sa',
        fields: const {},
        rawOcrText: ocrText,
        imagePath: imagePath,
        warnings: [...warnings, 'No text recognized in image.'],
        ocrComparison: ocrComparison,
      );
    }

    final idData = await AiIdExtractor.instance.extractWithAi(ocrText);
    final parsed = SaudiIdParser.instance.parseOcrText(ocrText);
    final merged = _mergeIdData(parsed, idData);

    if (merged.identityNumber == null) {
      warnings.add('Saudi identity number not found.');
    }
    if (merged.arabicName == null) {
      warnings.add('Arabic name not found.');
    }

    return DocumentScanResult(
      documentType: DocumentType.saudiId,
      countryCode: 'sa',
      fields: {
        'arabicName': merged.arabicName,
        'englishName': merged.englishName,
        'identityNumber': merged.identityNumber,
        'dateOfBirth': merged.dateOfBirth,
        'dateOfExpiry': merged.dateOfExpiry,
        'placeOfBirth': merged.placeOfBirth,
        'gender': merged.gender,
        'cardType': merged.cardType.name,
      },
      rawOcrText: ocrText,
      imagePath: imagePath,
      warnings: warnings,
      ocrComparison: ocrComparison,
    );
  }

  SaudiIdData _mergeIdData(SaudiIdData primary, SaudiIdData fallback) {
    return SaudiIdData(
      arabicName: primary.arabicName ?? fallback.arabicName,
      englishName: primary.englishName ?? fallback.englishName,
      identityNumber: primary.identityNumber ?? fallback.identityNumber,
      dateOfBirth: primary.dateOfBirth ?? fallback.dateOfBirth,
      dateOfExpiry: primary.dateOfExpiry ?? fallback.dateOfExpiry,
      placeOfBirth: primary.placeOfBirth ?? fallback.placeOfBirth,
      gender: primary.gender ?? fallback.gender,
      cardType: primary.cardType != IdCardType.unknown
          ? primary.cardType
          : fallback.cardType,
    );
  }
}
