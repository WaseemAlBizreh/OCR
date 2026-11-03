import 'package:idlens/src/domain/document_framing.dart';
import 'package:opencv_dart/opencv.dart' as cv;

/// Finds where the document sits in a photo: its 4-corner outline and its
/// bright area against the background. [DocumentFraming] judges the result.
class DocumentFrameChecker {
  /// The photo is measured at this width: fast, and print is too small to
  /// matter.
  static const _width = 400;

  /// Returns null when the image cannot be read.
  Future<FrameMeasure?> measure(String imagePath) async {
    final image = await cv.imreadAsync(imagePath, flags: cv.IMREAD_GRAYSCALE);
    if (image.isEmpty) {
      image.dispose();
      return null;
    }
    final mats = <cv.Mat>[image];
    try {
      final scale = _width / image.cols;
      final small = await cv.resizeAsync(image, (
        _width,
        (image.rows * scale).round().clamp(1, 1 << 20),
      ), interpolation: cv.INTER_AREA);
      mats.add(small);
      return FrameMeasure(
        width: small.cols.toDouble(),
        height: small.rows.toDouble(),
        outline: await _outline(small, mats),
        region: await _region(small, mats),
      );
    } finally {
      for (final m in mats) {
        m.dispose();
      }
    }
  }

  /// The largest convex 4-corner shape drawn by edges, as `cropPage` finds a
  /// page. The edge limits are lower than `cropPage`'s so that a light card
  /// on a light table still shows its outline. Shapes down to
  /// [DocumentFraming.minFarOutlineShare] are kept, so a far document's
  /// outline is found too.
  static Future<List<FramePoint>?> _outline(
    cv.Mat small,
    List<cv.Mat> mats,
  ) async {
    final blurred = await cv.gaussianBlurAsync(small, (5, 5), 0);
    final edges = await cv.cannyAsync(blurred, 25, 75);
    final kernel = cv.getStructuringElement(cv.MORPH_RECT, (5, 5));
    final closed = await cv.dilateAsync(edges, kernel);
    mats.addAll([blurred, edges, kernel, closed]);

    final (contours, hierarchy) = await cv.findContoursAsync(
      closed,
      cv.RETR_EXTERNAL,
      cv.CHAIN_APPROX_SIMPLE,
    );
    hierarchy.dispose();
    final minArea =
        DocumentFraming.minFarOutlineShare * small.cols * small.rows;
    List<FramePoint>? best;
    var bestArea = minArea;
    for (var i = 0; i < contours.length; i++) {
      final contour = contours[i];
      final area = cv.contourArea(contour);
      if (area < bestArea) continue;
      final approx = cv.approxPolyDP(
        contour,
        0.02 * cv.arcLength(contour, true),
        true,
      );
      if (approx.length == 4 && cv.isContourConvex(approx)) {
        bestArea = area;
        best = [
          for (var k = 0; k < 4; k++)
            (x: approx[k].x.toDouble(), y: approx[k].y.toDouble()),
        ];
      }
      approx.dispose();
    }
    contours.dispose();
    return best;
  }

  /// The largest bright area (Otsu threshold), with how much of each photo
  /// edge it lies on.
  static Future<FrameRegion?> _region(cv.Mat small, List<cv.Mat> mats) async {
    final blurred = await cv.gaussianBlurAsync(small, (7, 7), 0);
    final (_, binary) = await cv.thresholdAsync(
      blurred,
      0,
      255,
      cv.THRESH_BINARY | cv.THRESH_OTSU,
    );
    final kernel = cv.getStructuringElement(cv.MORPH_RECT, (15, 15));
    final closed = await cv.morphologyExAsync(binary, cv.MORPH_CLOSE, kernel);
    mats.addAll([blurred, binary, kernel, closed]);

    final (contours, hierarchy) = await cv.findContoursAsync(
      closed,
      cv.RETR_EXTERNAL,
      cv.CHAIN_APPROX_SIMPLE,
    );
    hierarchy.dispose();
    try {
      var bestIndex = -1;
      var bestArea = 0.0;
      for (var i = 0; i < contours.length; i++) {
        final area = cv.contourArea(contours[i]);
        if (area > bestArea) {
          bestArea = area;
          bestIndex = i;
        }
      }
      if (bestIndex < 0) return null;

      final box = cv.boundingRect(contours[bestIndex]);
      final mask = cv.Mat.zeros(small.rows, small.cols, cv.MatType.CV_8UC1);
      mats.add(mask);
      cv.drawContours(
        mask,
        contours,
        bestIndex,
        cv.Scalar.all(255),
        thickness: cv.FILLED,
      );
      double along(cv.Rect strip) {
        final part = mask.region(strip);
        final count = cv.countNonZero(part);
        part.dispose();
        return count.toDouble();
      }

      final cols = small.cols, rows = small.rows;
      final share = cv.countNonZero(mask) / (cols * rows);
      return FrameRegion(
        share: share,
        left: box.x.toDouble(),
        top: box.y.toDouble(),
        right: (box.x + box.width).toDouble(),
        bottom: (box.y + box.height).toDouble(),
        // In FrameSide order: left, top, right, bottom.
        contact: [
          along(cv.Rect(0, 0, 1, rows)),
          along(cv.Rect(0, 0, cols, 1)),
          along(cv.Rect(cols - 1, 0, 1, rows)),
          along(cv.Rect(0, rows - 1, cols, 1)),
        ],
      );
    } finally {
      contours.dispose();
    }
  }
}
