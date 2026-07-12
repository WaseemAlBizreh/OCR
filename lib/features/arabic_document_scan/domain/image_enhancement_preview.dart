class ImageEnhancementPreview {
  const ImageEnhancementPreview({
    required this.originalPath,
    required this.previewPath,
    this.enhancementFailed = false,
    this.warning,
  });

  final String originalPath;
  final String previewPath;
  final bool enhancementFailed;
  final String? warning;

  bool get isEnhanced => originalPath != previewPath;
}
