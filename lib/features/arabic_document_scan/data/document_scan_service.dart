import 'package:injectable/injectable.dart';
import 'package:mrz/features/arabic_document_scan/data/generic_arabic_extractor.dart';
import 'package:mrz/features/arabic_document_scan/data/opencv_image_enhancer.dart';
import 'package:mrz/features/arabic_document_scan/data/passport_mrz_extractor.dart';
import 'package:mrz/features/arabic_document_scan/domain/document_scan_result.dart';
import 'package:mrz/features/arabic_document_scan/domain/document_type.dart';
import 'package:mrz/features/arabic_document_scan/domain/id_card_side.dart';
import 'package:mrz/features/arabic_document_scan/domain/image_enhancement_preview.dart';

@lazySingleton
class DocumentScanService {
  DocumentScanService(
    this._passportMrzExtractor,
    this._genericArabicExtractor,
    this._imageEnhancer,
  );

  final PassportMrzExtractor _passportMrzExtractor;
  final GenericArabicExtractor _genericArabicExtractor;
  final OpenCvImageEnhancer _imageEnhancer;

  Future<ImageEnhancementPreview> prepareImage(String imagePath) async {
    try {
      final enhancedPath = await _imageEnhancer.enhance(imagePath);
      return ImageEnhancementPreview(
        originalPath: imagePath,
        previewPath: enhancedPath,
      );
    } catch (e) {
      return ImageEnhancementPreview(
        originalPath: imagePath,
        previewPath: imagePath,
        enhancementFailed: true,
        warning: 'Image enhancement skipped: $e',
      );
    }
  }

  Future<void> discardPreparedImage(String path) async {
    await _imageEnhancer.deleteTemp(path);
  }

  Future<DocumentScanResult> scan({
    required DocumentType documentType,
    required String imagePath,
    required String ocrImagePath,
    String? enhancementWarning,
    String? countryCode,
    IdCardSide idCardSide = IdCardSide.front,
  }) async {
    final extraWarnings = <String>[
      ?enhancementWarning,
    ];
    final shouldCleanupOcrImage = ocrImagePath != imagePath;

    try {
      final result = await switch (documentType) {
        DocumentType.passport => _passportMrzExtractor.extract(
            imagePath: ocrImagePath,
            countryCode: countryCode,
          ),
        DocumentType.arabicId => _genericArabicExtractor.extract(
            imagePath: ocrImagePath,
            countryCode: countryCode ?? 'sd',
            idCardSide: idCardSide,
          ),
      };

      return DocumentScanResult(
        documentType: result.documentType,
        countryCode: result.countryCode,
        fields: result.fields,
        rawOcrText: result.rawOcrText,
        imagePath: imagePath,
        mrzResult: result.mrzResult,
        warnings: [...result.warnings, ...extraWarnings],
        ocrComparison: result.ocrComparison,
        scannedAt: result.scannedAt,
      );
    } finally {
      if (shouldCleanupOcrImage) {
        await _imageEnhancer.deleteTemp(ocrImagePath);
      }
    }
  }
}
