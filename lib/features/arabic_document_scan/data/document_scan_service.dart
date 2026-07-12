import 'package:injectable/injectable.dart';
import 'package:mrz/features/arabic_document_scan/data/arabic_ocr_engine.dart';
import 'package:mrz/features/arabic_document_scan/data/generic_arabic_extractor.dart';
import 'package:mrz/features/arabic_document_scan/data/opencv_image_enhancer.dart';
import 'package:mrz/features/arabic_document_scan/data/passport_mrz_extractor.dart';
import 'package:mrz/features/arabic_document_scan/domain/document_scan_result.dart';
import 'package:mrz/features/arabic_document_scan/domain/document_type.dart';
import 'package:mrz/features/arabic_document_scan/domain/id_card_side.dart';
import 'package:mrz/features/arabic_document_scan/domain/custom_enhancement_settings.dart';
import 'package:mrz/features/arabic_document_scan/domain/image_enhancement_preset.dart';
import 'package:mrz/features/arabic_document_scan/domain/image_enhancement_preview.dart';

@lazySingleton
class DocumentScanService {
  DocumentScanService(
    this._passportMrzExtractor,
    this._genericArabicExtractor,
    this._imageEnhancer,
    this._ocrEngine,
  );

  final PassportMrzExtractor _passportMrzExtractor;
  final GenericArabicExtractor _genericArabicExtractor;
  final OpenCvImageEnhancer _imageEnhancer;
  final ArabicOcrEngine _ocrEngine;

  Future<ImageEnhancementPreview> prepareImage(String imagePath) async {
    try {
      final standardPath = await _imageEnhancer.enhance(
        imagePath,
        preset: EnhancementPreset.standard,
      );
      return ImageEnhancementPreview(
        originalPath: imagePath,
        presetPaths: {EnhancementPreset.standard: standardPath},
        selectedPreset: EnhancementPreset.standard,
      );
    } catch (e) {
      return ImageEnhancementPreview(
        originalPath: imagePath,
        presetPaths: const {},
        selectedPreset: EnhancementPreset.original,
        enhancementFailed: true,
        warning: 'Image enhancement skipped: $e',
      );
    }
  }

  Future<String> ensurePresetPath({
    required String originalPath,
    required EnhancementPreset preset,
    required Map<EnhancementPreset, String> cache,
    CustomEnhancementSettings? customSettings,
  }) async {
    if (preset == EnhancementPreset.original) {
      return originalPath;
    }

    if (preset == EnhancementPreset.custom) {
      throw ArgumentError(
        'Use ensureCustomPath for EnhancementPreset.custom',
      );
    }

    final cached = cache[preset];
    if (cached != null) {
      return cached;
    }

    final path = await _imageEnhancer.enhance(originalPath, preset: preset);
    cache[preset] = path;
    return path;
  }

  Future<String> ensureCustomPath({
    required String originalPath,
    required CustomEnhancementSettings settings,
    required Map<String, String> cache,
  }) async {
    final cached = cache[settings.cacheKey];
    if (cached != null) {
      return cached;
    }

    final path = await _imageEnhancer.enhanceCustom(originalPath, settings);
    cache[settings.cacheKey] = path;
    return path;
  }

  Future<void> discardPreparedImages(Iterable<String> paths) async {
    for (final path in paths) {
      await _imageEnhancer.deleteTemp(path);
    }
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
    final resolvedOcrPath = await _resolveBestOcrImagePath(
      originalPath: imagePath,
      preferredPath: ocrImagePath,
      extraWarnings: extraWarnings,
    );
    final shouldCleanupOcrImage = resolvedOcrPath != imagePath;

    try {
      final result = await switch (documentType) {
        DocumentType.passport => _passportMrzExtractor.extract(
            imagePath: resolvedOcrPath,
            countryCode: countryCode,
          ),
        DocumentType.arabicId => _genericArabicExtractor.extract(
            imagePath: resolvedOcrPath,
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
        await _imageEnhancer.deleteTemp(resolvedOcrPath);
      }
    }
  }

  Future<String> _resolveBestOcrImagePath({
    required String originalPath,
    required String preferredPath,
    required List<String> extraWarnings,
  }) async {
    if (originalPath == preferredPath) {
      return preferredPath;
    }

    final originalQuality = await _ocrEngine.estimateOcrQuality(originalPath);
    final preferredQuality = await _ocrEngine.estimateOcrQuality(preferredPath);

    if (originalQuality > preferredQuality) {
      extraWarnings.add(
        'Original image produced better OCR preview; using original.',
      );
      return originalPath;
    }

    return preferredPath;
  }
}
