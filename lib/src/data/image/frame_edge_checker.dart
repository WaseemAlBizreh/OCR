import 'package:idlens/src/data/ocr/paddle/passport/mlkit_latin_reader.dart';
import 'package:idlens/src/data/ocr/paddle/passport/passport_frame_check.dart';
import 'package:opencv_dart/opencv.dart' as cv;

/// Tells whether a photo's printed text is cut off by the edges of the photo,
/// for documents whose own scan does not expose line positions (the Sudan ID
/// front and the certificate). ML Kit is used only for where text is, not for
/// what it says, so even a garbled Arabic reading counts.
class FrameEdgeChecker {
  FrameEdgeChecker(this._mlkit);

  final MlKitLatinReader _mlkit;

  /// Edges (0 to 4) that text runs up to; 0 when nothing could be measured.
  Future<int> touchedSides(String imagePath) async {
    final page = await _mlkit.read(imagePath);
    if (page == null) return 0;
    final image = cv.imread(imagePath);
    try {
      if (image.isEmpty) return 0;
      return PassportFrameCheck.touchedSides(
        page.lines,
        width: image.cols.toDouble(),
        height: image.rows.toDouble(),
      );
    } finally {
      image.dispose();
    }
  }
}
