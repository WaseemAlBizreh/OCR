enum EnhancementPreset {
  original('Original'),
  minimal('Mild contrast'),
  standard('Standard'),
  enhanced('Enhanced'),
  custom('Custom');

  const EnhancementPreset(this.label);

  final String label;

  static const List<EnhancementPreset> processed = [
    EnhancementPreset.minimal,
    EnhancementPreset.standard,
    EnhancementPreset.enhanced,
    EnhancementPreset.custom,
  ];
}
