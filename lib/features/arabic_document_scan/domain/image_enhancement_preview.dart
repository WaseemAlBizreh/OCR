import 'package:mrz/features/arabic_document_scan/domain/custom_enhancement_settings.dart';
import 'package:mrz/features/arabic_document_scan/domain/image_enhancement_preset.dart';

class ImageEnhancementPreview {
  const ImageEnhancementPreview({
    required this.originalPath,
    required this.presetPaths,
    this.selectedPreset = EnhancementPreset.standard,
    this.enhancementFailed = false,
    this.warning,
  });

  final String originalPath;
  final Map<EnhancementPreset, String> presetPaths;
  final EnhancementPreset selectedPreset;
  final bool enhancementFailed;
  final String? warning;

  String pathFor(EnhancementPreset preset) {
    if (preset == EnhancementPreset.original) {
      return originalPath;
    }
    return presetPaths[preset] ?? originalPath;
  }

  bool get isEnhanced => presetPaths.isNotEmpty;

  Iterable<String> get generatedTempPaths => presetPaths.values;
}

class ImagePreviewSelection {
  const ImagePreviewSelection({
    required this.action,
    required this.preset,
    required this.ocrImagePath,
    required this.generatedPaths,
    this.customSettings,
    this.customGeneratedPaths = const {},
  });

  final ImagePreviewAction action;
  final EnhancementPreset preset;
  final String ocrImagePath;
  final Map<EnhancementPreset, String> generatedPaths;
  final CustomEnhancementSettings? customSettings;
  final Map<String, String> customGeneratedPaths;

  Iterable<String> get allGeneratedPaths => [
        ...generatedPaths.values,
        ...customGeneratedPaths.values,
      ];
}

enum ImagePreviewAction { retake, accept }
