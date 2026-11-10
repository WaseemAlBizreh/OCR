import 'package:idlens/src/domain/scan_issue.dart';
import 'package:idlens/src/domain/validation_limits.dart';

/// Measurements of the MRZ band of a photo, and what they say about it.
class ImageQuality {
  const ImageQuality({
    required this.sharpness,
    required this.brightness,
    required this.glareShare,
    this.documentCoverage = 1,
  });

  /// Variance of the Laplacian on a band normalised to [bandWidth] pixels
  /// wide. Low means blurry.
  final double sharpness;

  /// Mean grey level, 0..255.
  final double brightness;

  /// Share (0..1) of nearly white pixels.
  final double glareShare;

  /// Share (0..1) of the frame taken by the document's bounding box. Low when
  /// the document is far from the camera or only partly in the frame.
  final double documentCoverage;

  // Tuned from one bad on-device photo (sharpness 45.9, brightness 96.1), so
  // provisional: check them against good photos (the measured values are in
  // toJson) before trusting them.
  static const bandWidth = 1000;
  static const minSharpness = 60.0;
  static const minBrightness = 110.0;
  static const maxGlareShare = 0.20;

  /// Below this share of the photo the document is too far away. The camera
  /// crops 6% wider than the box on every side, so a document as wide as a
  /// share `w` of the box covers about `(w / 1.12)²` of the photo:
  ///
  /// | Width in the box | Coverage | Result |
  /// |---|---|---|
  /// | 100% | 0.80 | accepted |
  /// | 90% | 0.65 | accepted |
  /// | 87% | 0.60 | the limit |
  /// | 80% | 0.51 | too far |
  /// | 60% | 0.29 | too far |
  ///
  /// Calibrated 2026-11-10 from the labelled scans in test/fixtures/scans
  /// (test/regression/calibrate_test.dart): far 0.255, 0.463, 0.514, 0.555;
  /// good 0.653 to 0.932 (16 scans). Every value from 0.56 to 0.64 separates
  /// them; 0.60 is the middle. It was 0.42, which accepted three of the four
  /// far scans. Provisional: 4 far samples, two photographed from a screen.
  static const minDocumentCoverage = 0.60;

  /// The most likely reason the document could not be read well (an issue
  /// code), or null when nothing stands out. A document far from the frame
  /// comes first, as its dark surroundings would otherwise read as a dark
  /// photo.
  ScanIssue? get problem => problemWith(ValidationLimits.standard);

  /// [problem] judged with other [limits] (regression calibration only).
  ScanIssue? problemWith(ValidationLimits limits) {
    if (documentCoverage < limits.minDocumentCoverage) {
      return ScanIssue.documentNotInFrame;
    }
    final notClear =
        brightness < limits.minBrightness ||
        glareShare > limits.maxGlareShare ||
        sharpness < limits.minSharpness;
    return notClear ? ScanIssue.imageNotClear : null;
  }

  Map<String, dynamic> toJson() => {
    'sharpness': sharpness,
    'brightness': brightness,
    'glareShare': glareShare,
    'documentCoverage': documentCoverage,
    'issue': problem?.name,
  };
}
