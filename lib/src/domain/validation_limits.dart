import 'package:idlens/src/domain/document_framing.dart';
import 'package:idlens/src/domain/image_quality.dart';

/// The tunable limits of the photo checks, in one object so the regression
/// calibration (test/regression/calibrate_test.dart) can replay the labelled
/// scans with other values. The package itself always uses [standard], whose
/// values are the constants on [DocumentFraming] and [ImageQuality]; change a
/// limit there, never by passing another object. Not exported.
class ValidationLimits {
  const ValidationLimits({
    this.minDocumentCoverage = ImageQuality.minDocumentCoverage,
    this.minSharpness = ImageQuality.minSharpness,
    this.minBrightness = ImageQuality.minBrightness,
    this.maxGlareShare = ImageQuality.maxGlareShare,
    this.edgeMargin = DocumentFraming.edgeMargin,
    this.minContact = DocumentFraming.minContact,
    this.regionAspectTolerance = DocumentFraming.regionAspectTolerance,
    this.uprightRegionTolerance = DocumentFraming.uprightRegionTolerance,
    this.aspectTolerance = DocumentFraming.aspectTolerance,
  });

  static const standard = ValidationLimits();

  final double minDocumentCoverage;
  final double minSharpness;
  final double minBrightness;
  final double maxGlareShare;
  final double edgeMargin;
  final double minContact;
  final double regionAspectTolerance;
  final double uprightRegionTolerance;
  final double aspectTolerance;

  /// The limits by name, in the order above.
  Map<String, double> toMap() => {
    'minDocumentCoverage': minDocumentCoverage,
    'minSharpness': minSharpness,
    'minBrightness': minBrightness,
    'maxGlareShare': maxGlareShare,
    'edgeMargin': edgeMargin,
    'minContact': minContact,
    'regionAspectTolerance': regionAspectTolerance,
    'uprightRegionTolerance': uprightRegionTolerance,
    'aspectTolerance': aspectTolerance,
  };

  /// These limits with the one called [name] set to [value].
  ValidationLimits withLimit(String name, double value) {
    final m = toMap();
    if (!m.containsKey(name)) throw ArgumentError.value(name, 'name');
    m[name] = value;
    return ValidationLimits(
      minDocumentCoverage: m['minDocumentCoverage']!,
      minSharpness: m['minSharpness']!,
      minBrightness: m['minBrightness']!,
      maxGlareShare: m['maxGlareShare']!,
      edgeMargin: m['edgeMargin']!,
      minContact: m['minContact']!,
      regionAspectTolerance: m['regionAspectTolerance']!,
      uprightRegionTolerance: m['uprightRegionTolerance']!,
      aspectTolerance: m['aspectTolerance']!,
    );
  }
}
