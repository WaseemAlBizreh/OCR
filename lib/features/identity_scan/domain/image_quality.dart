import 'package:mrz/features/identity_scan/domain/scan_issue.dart';

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
  static const minDocumentCoverage = 0.6;

  /// The most likely reason the document could not be read well (an issue
  /// code), or null when nothing stands out. A document far from the frame
  /// comes first, as its dark surroundings would otherwise read as a dark
  /// photo.
  ScanIssue? get problem {
    if (documentCoverage < minDocumentCoverage) return ScanIssue.documentNotInFrame;
    final notClear = brightness < minBrightness ||
        glareShare > maxGlareShare ||
        sharpness < minSharpness;
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
