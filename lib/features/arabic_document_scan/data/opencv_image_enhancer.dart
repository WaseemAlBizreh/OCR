import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:injectable/injectable.dart';
import 'package:mrz/features/arabic_document_scan/domain/custom_enhancement_settings.dart';
import 'package:mrz/features/arabic_document_scan/domain/image_enhancement_preset.dart';
import 'package:opencv_dart/opencv.dart' as cv;
import 'package:path_provider/path_provider.dart';

/// Document preprocessing for OCR using OpenCV.
@lazySingleton
class OpenCvImageEnhancer {
  static const int _minWidth = 1500;

  static const int _enhancedContrast = 70;
  static const int _enhancedBrightness = 20;
  static const int _enhancedDetails = 100;
  static const int _enhancedShadowRemoval = 70;

  Future<void>? _enhanceChain;

  Future<T> _runSerialized<T>(Future<T> Function() action) async {
    final previous = _enhanceChain ?? Future.value();
    final completer = Completer<void>();
    _enhanceChain = completer.future;
    await previous.catchError((_) {});
    try {
      return await action();
    } finally {
      completer.complete();
    }
  }

  Future<String> enhance(
    String inputPath, {
    EnhancementPreset preset = EnhancementPreset.standard,
    CustomEnhancementSettings? customSettings,
  }) {
    return _runSerialized(() async {
      if (preset == EnhancementPreset.original) {
        return inputPath;
      }

      if (preset == EnhancementPreset.custom) {
        return _enhanceCustomInternal(
          inputPath,
          customSettings ?? CustomEnhancementSettings.defaults,
        );
      }

      return _enhanceMatFile(inputPath, preset.name, (mat) async {
        return switch (preset) {
          EnhancementPreset.minimal => _enhanceMinimal(mat),
          EnhancementPreset.standard => _enhanceStandard(mat),
          EnhancementPreset.enhanced => _enhanceEnhanced(mat),
          EnhancementPreset.custom => mat.clone(),
          EnhancementPreset.original => mat.clone(),
        };
      });
    });
  }

  Future<String> enhanceCustom(
    String inputPath,
    CustomEnhancementSettings settings,
  ) {
    return _runSerialized(
      () => _enhanceCustomInternal(inputPath, settings),
    );
  }

  Future<String> _enhanceCustomInternal(
    String inputPath,
    CustomEnhancementSettings settings,
  ) {
    return _enhanceMatFile(
      inputPath,
      'custom_${settings.cacheKey}',
      (mat) => settings.grayscale
          ? _enhanceGrayscale(mat, settings)
          : _enhanceColorDocument(mat, settings),
    );
  }

  Future<String> _enhanceMatFile(
    String inputPath,
    String label,
    Future<cv.Mat> Function(cv.Mat mat) process,
  ) async {
    if (!await File(inputPath).exists()) {
      throw StateError('Image file not found: $inputPath');
    }

    final mat = cv.imread(inputPath);
    if (mat.isEmpty) {
      mat.dispose();
      throw StateError('Failed to read image: $inputPath');
    }

    cv.Mat? result;
    try {
      result = await process(mat);
      return await _writeResult(result, label);
    } finally {
      mat.dispose();
      result?.dispose();
    }
  }

  Future<String> _writeResult(cv.Mat result, String label) async {
    final tempDir = await getTemporaryDirectory();
    final outputPath =
        '${tempDir.path}/enhanced_${label}_${DateTime.now().microsecondsSinceEpoch}.png';

    final written = await cv.imwriteAsync(outputPath, result);
    if (!written) {
      throw StateError('Failed to write enhanced image');
    }

    return outputPath;
  }

  Future<cv.Mat> _enhanceMinimal(cv.Mat mat) async {
    final gray = await cv.cvtColorAsync(mat, cv.COLOR_BGR2GRAY);
    final clahe = cv.createCLAHE(clipLimit: 2.5, tileGridSize: (8, 8));
    try {
      final enhanced = await clahe.applyAsync(gray);
      return _ensureMinWidth(enhanced);
    } finally {
      gray.dispose();
      clahe.dispose();
    }
  }

  Future<cv.Mat> _enhanceStandard(cv.Mat mat) {
    return _enhanceGrayscale(
      mat,
      const CustomEnhancementSettings(
        contrast: 55,
        brightness: 45,
        details: 90,
        shadowRemoval: 80,
        textDarkening: false,
        grayscale: true,
      ),
    );
  }

  Future<cv.Mat> _enhanceEnhanced(cv.Mat mat) {
    return _enhanceColorDocument(
      mat,
      const CustomEnhancementSettings(
        contrast: _enhancedContrast,
        brightness: _enhancedBrightness,
        details: _enhancedDetails,
        shadowRemoval: _enhancedShadowRemoval,
        textDarkening: true,
        grayscale: false,
      ),
    );
  }

  Future<cv.Mat> _enhanceGrayscale(
    cv.Mat mat,
    CustomEnhancementSettings settings,
  ) async {
    var gray = await cv.cvtColorAsync(mat, cv.COLOR_BGR2GRAY);
    try {
      if (settings.shadowRemoval > 0) {
        final normalized = await _normalizeIllumination(
          gray,
          strength: settings.shadowRemoval,
        );
        gray.dispose();
        gray = normalized;
      }

      final clahe = cv.createCLAHE(
        clipLimit: _claheClipLimit(settings.contrast),
        tileGridSize: (8, 8),
      );
      final claheOut = await clahe.applyAsync(gray);
      clahe.dispose();
      gray.dispose();
      gray = claheOut;

      final stretched = await _stretchContrast(gray);
      gray.dispose();
      gray = stretched;

      final adjusted = await cv.convertScaleAbsAsync(
        gray,
        alpha: _contrastAlpha(settings.contrast),
        beta: _brightnessBeta(settings.brightness),
      );
      gray.dispose();
      gray = adjusted;

      var sharpened = await _sharpenForOcr(gray, details: settings.details);
      gray.dispose();
      gray = sharpened;

      if (settings.textDarkening) {
        final darkened = await _darkenTextForOcr(gray);
        gray.dispose();
        gray = darkened;
      }

      final binary = await cv.adaptiveThresholdAsync(
        gray,
        255,
        cv.ADAPTIVE_THRESH_GAUSSIAN_C,
        cv.THRESH_BINARY,
        _oddBlockSize(25, gray),
        3,
      );
      gray.dispose();
      gray = binary;

      final kernel = await cv.getStructuringElementAsync(cv.MORPH_RECT, (2, 2));
      final closed = await cv.morphologyExAsync(gray, cv.MORPH_CLOSE, kernel);
      kernel.dispose();
      gray.dispose();
      gray = closed;

      return _ensureMinWidth(gray);
    } catch (_) {
      gray.dispose();
      rethrow;
    }
  }

  Future<cv.Mat> _enhanceColorDocument(
    cv.Mat mat,
    CustomEnhancementSettings settings,
  ) async {
    final lab = await cv.cvtColorAsync(mat, cv.COLOR_BGR2Lab);
    final channels = await cv.splitAsync(lab);
    lab.dispose();

    cv.Mat? lChannel = channels[0].clone();
    cv.Mat? aChannel = channels[1].clone();
    cv.Mat? bChannel = channels[2].clone();
    channels.dispose();

    try {
      if (settings.shadowRemoval > 0) {
        final normalized = await _normalizeIllumination(
          lChannel!,
          strength: settings.shadowRemoval,
        );
        lChannel!.dispose();
        lChannel = normalized;
      }

      final clahe = cv.createCLAHE(
        clipLimit: _claheClipLimit(settings.contrast),
        tileGridSize: (8, 8),
      );
      final claheL = await clahe.applyAsync(lChannel!);
      clahe.dispose();
      lChannel!.dispose();
      lChannel = claheL;

      final stretched = await _stretchContrast(lChannel!);
      lChannel!.dispose();
      lChannel = stretched;

      final adjusted = await cv.convertScaleAbsAsync(
        lChannel!,
        alpha: _contrastAlpha(settings.contrast),
        beta: _brightnessBeta(settings.brightness),
      );
      lChannel!.dispose();
      lChannel = adjusted;

      final sharpened = await _sharpenForOcr(lChannel!, details: settings.details);
      lChannel!.dispose();
      lChannel = sharpened;

      if (settings.textDarkening) {
        final darkened = await _darkenTextForOcr(lChannel!);
        lChannel!.dispose();
        lChannel = darkened;
      }

      final lForMerge = lChannel!;
      final aForMerge = aChannel!;
      final bForMerge = bChannel!;
      lChannel = null;
      aChannel = null;
      bChannel = null;

      final merged = await cv.mergeAsync(
        cv.VecMat.fromList([lForMerge, aForMerge, bForMerge]),
      );
      lForMerge.dispose();
      aForMerge.dispose();
      bForMerge.dispose();

      final bgr = await cv.cvtColorAsync(merged, cv.COLOR_Lab2BGR);
      merged.dispose();

      return _ensureMinWidth(bgr);
    } catch (_) {
      lChannel?.dispose();
      aChannel?.dispose();
      bChannel?.dispose();
      rethrow;
    }
  }

  Future<cv.Mat> _normalizeIllumination(
    cv.Mat gray, {
    required int strength,
  }) async {
    final requested = 15 + ((strength.clamp(0, 100) / 100) * 36).round();
    final kernel = _oddBlurKernel(requested, gray);

    final denoised = await cv.medianBlurAsync(gray, 3);
    final background = await cv.gaussianBlurAsync(denoised, (kernel, kernel), 0);
    final backgroundFloor = cv.Mat.ones(gray.rows, gray.cols, cv.MatType.CV_8UC1)
        .setTo(cv.Scalar.all(5));
    final safeBackground = await cv.maxAsync(background, backgroundFloor);
    backgroundFloor.dispose();

    final normalized = await cv.divideAsync(
      denoised,
      safeBackground,
      scale: 255,
    );

    denoised.dispose();
    background.dispose();
    safeBackground.dispose();

    return normalized;
  }

  Future<cv.Mat> _stretchContrast(cv.Mat src) async {
    final dst = cv.Mat.empty();
    return cv.normalizeAsync(
      src,
      dst,
      alpha: 0,
      beta: 255,
      normType: cv.NORM_MINMAX,
    );
  }

  Future<cv.Mat> _darkenTextForOcr(cv.Mat luminance) async {
    final binary = await cv.adaptiveThresholdAsync(
      luminance,
      255,
      cv.ADAPTIVE_THRESH_GAUSSIAN_C,
      cv.THRESH_BINARY,
      _oddBlockSize(21, luminance),
      4,
    );
    final darkened = await cv.minAsync(luminance, binary);
    binary.dispose();
    return darkened;
  }

  int _oddBlurKernel(int requested, cv.Mat mat) {
    final maxKernel = math.min(mat.rows, mat.cols);
    if (maxKernel < 3) return 3;
    final capped = math.min(requested, maxKernel);
    final odd = capped.isOdd ? capped : capped - 1;
    return math.max(odd, 3);
  }

  int _oddBlockSize(int requested, cv.Mat mat) {
    final maxBlock = math.min(mat.rows, mat.cols);
    if (maxBlock < 3) return 3;
    final capped = math.min(requested, maxBlock);
    final odd = capped.isOdd ? capped : capped - 1;
    return math.max(odd, 3);
  }

  double _contrastAlpha(int slider) {
    final value = slider.clamp(0, 100) / 100.0;
    return 0.6 + value * 1.2;
  }

  double _brightnessBeta(int slider) {
    return ((slider.clamp(0, 100) - 50) / 50.0) * 60.0;
  }

  double _claheClipLimit(int slider) {
    final value = slider.clamp(0, 100) / 100.0;
    return 1.0 + value * 3.0;
  }

  (double srcWeight, double blurWeight) _detailWeights(int slider) {
    final amount = slider.clamp(0, 100) / 100.0;
    return (1.0 + amount * 1.5, -amount * 1.5);
  }

  Future<cv.Mat> _sharpenForOcr(cv.Mat src, {required int details}) async {
    final (srcWeight, blurWeight) = _detailWeights(details);
    final blurred = await cv.gaussianBlurAsync(src, (0, 0), 1.0);
    final sharpened = await cv.addWeightedAsync(
      src,
      srcWeight,
      blurred,
      blurWeight,
      0,
    );
    blurred.dispose();
    return sharpened;
  }

  Future<cv.Mat> _ensureMinWidth(cv.Mat src) async {
    if (src.cols >= _minWidth) {
      return src;
    }

    final scale = _minWidth / src.cols;
    final newHeight = (src.rows * scale).round();
    final resized = await cv.resizeAsync(
      src,
      (_minWidth, newHeight),
      interpolation: cv.INTER_CUBIC,
    );
    src.dispose();
    return resized;
  }

  Future<void> deleteTemp(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
