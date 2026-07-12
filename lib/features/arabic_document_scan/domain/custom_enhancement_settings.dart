/// Manual filter controls (CamScanner-style 0–100 sliders).
class CustomEnhancementSettings {
  const CustomEnhancementSettings({
    this.contrast = 50,
    this.brightness = 50,
    this.details = 50,
    this.shadowRemoval = 70,
    this.textDarkening = true,
    this.grayscale = false,
  });

  final int contrast;
  final int brightness;
  final int details;
  final int shadowRemoval;
  final bool textDarkening;
  final bool grayscale;

  static const defaults = CustomEnhancementSettings();

  String get cacheKey =>
      '$contrast-$brightness-$details-$shadowRemoval-$textDarkening-$grayscale';

  CustomEnhancementSettings copyWith({
    int? contrast,
    int? brightness,
    int? details,
    int? shadowRemoval,
    bool? textDarkening,
    bool? grayscale,
  }) {
    return CustomEnhancementSettings(
      contrast: contrast ?? this.contrast,
      brightness: brightness ?? this.brightness,
      details: details ?? this.details,
      shadowRemoval: shadowRemoval ?? this.shadowRemoval,
      textDarkening: textDarkening ?? this.textDarkening,
      grayscale: grayscale ?? this.grayscale,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CustomEnhancementSettings && cacheKey == other.cacheKey;

  @override
  int get hashCode => cacheKey.hashCode;
}
