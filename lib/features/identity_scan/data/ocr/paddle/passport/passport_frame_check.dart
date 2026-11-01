import 'package:mrz/features/identity_scan/data/ocr/paddle/passport/passport_line.dart';

/// Tells whether the photographed document is cut off by the frame.
///
/// The camera crops the guide frame plus a margin, so a well-placed document
/// leaves paper around its text. Text that runs to the edge of the photo on
/// two or more sides means the document is too close or off to one side. Pure
/// Dart so it can be unit tested without OCR or OpenCV.
class PassportFrameCheck {
  PassportFrameCheck._();

  /// A line this close to an edge (as a fraction of the photo) touches it.
  static const margin = 0.03;

  /// Lines smaller than this fraction of the photo are noise, not printing.
  static const _minHeight = 0.01;

  /// The edges (0 to 4) that printed text runs up to.
  static int touchedSides(
    List<PassportLine> lines, {
    required double width,
    required double height,
  }) {
    if (width <= 0 || height <= 0) return 0;
    var left = false, right = false, top = false, bottom = false;
    for (final line in lines) {
      if (line.text.trim().length < 3 || line.height < height * _minHeight) continue;
      left |= line.left <= width * margin;
      right |= line.right >= width * (1 - margin);
      top |= line.top <= height * margin;
      bottom |= line.bottom >= height * (1 - margin);
    }
    return [left, right, top, bottom].where((touched) => touched).length;
  }
}
