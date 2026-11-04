import 'dart:io';
import 'dart:math' as math;

import 'package:idlens/src/domain/document_framing.dart';
import 'package:idlens/src/domain/view_crop.dart';
import 'package:opencv_dart/opencv.dart' as cv;
import 'package:path_provider/path_provider.dart';

/// Crops used by the capture screen and by the MRZ reader.
class ImageOps {
  /// Crops [inputPath] to the given fractions (0..1) of its width and height.
  ///
  /// [portrait] rotates the image first when its pixels are landscape, which
  /// some Android devices return even for a portrait capture. When
  /// [minWidth] is set, a narrower result is upscaled to that width, which
  /// helps OCR on thin MRZ characters.
  ///
  /// When [viewAspect] is set, the fractions are of a camera preview with
  /// that width / height, and are moved onto the photo with [ViewCrop] in
  /// case the photo has a different shape.
  Future<String> crop(
    String inputPath, {
    double left = 0,
    double top = 0,
    double right = 1,
    double bottom = 1,
    bool portrait = false,
    int minWidth = 0,
    double? viewAspect,
    String label = 'crop',
  }) async {
    var mat = await cv.imreadAsync(inputPath);
    if (mat.isEmpty) {
      mat.dispose();
      throw StateError('Failed to read image: $inputPath');
    }

    final toDispose = <cv.Mat>[mat];
    try {
      if (portrait && mat.cols > mat.rows) {
        mat = await cv.rotateAsync(mat, cv.ROTATE_90_CLOCKWISE);
        toDispose.add(mat);
      }

      if (viewAspect != null) {
        final onPhoto = ViewCrop.toPhoto(
          (left: left, top: top, right: right, bottom: bottom),
          viewAspect: viewAspect,
          photoAspect: mat.cols / mat.rows,
        );
        left = onPhoto.left;
        top = onPhoto.top;
        right = onPhoto.right;
        bottom = onPhoto.bottom;
      }

      final x = (mat.cols * left).round().clamp(0, mat.cols - 1);
      final y = (mat.rows * top).round().clamp(0, mat.rows - 1);
      final w = ((mat.cols * right).round() - x).clamp(1, mat.cols - x);
      final h = ((mat.rows * bottom).round() - y).clamp(1, mat.rows - y);

      var result = mat.region(cv.Rect(x, y, w, h));
      toDispose.add(result);

      if (minWidth > 0 && result.cols < minWidth) {
        final scale = minWidth / result.cols;
        result = await cv.resizeAsync(result, (
          minWidth,
          (result.rows * scale).round(),
        ), interpolation: cv.INTER_CUBIC);
        toDispose.add(result);
      }

      final dir = await getTemporaryDirectory();
      final outputPath =
          '${dir.path}/${label}_${DateTime.now().microsecondsSinceEpoch}.png';
      if (!await cv.imwriteAsync(outputPath, result)) {
        throw StateError('Failed to write cropped image');
      }
      return outputPath;
    } finally {
      for (final m in toDispose) {
        m.dispose();
      }
    }
  }

  /// Straightens a photographed page: finds the largest four-corner outline
  /// and warps it to a flat A4 sheet [outWidth] pixels wide. Returns null when
  /// no page outline is found, so the caller keeps the original photo.
  Future<String?> cropPage(
    String inputPath, {
    int outWidth = 1654,
    String label = 'page',
  }) async {
    var mat = await cv.imreadAsync(inputPath);
    if (mat.isEmpty) {
      mat.dispose();
      throw StateError('Failed to read image: $inputPath');
    }
    final toDispose = <cv.Mat>[mat];
    try {
      if (mat.cols > mat.rows) {
        mat = await cv.rotateAsync(mat, cv.ROTATE_90_CLOCKWISE);
        toDispose.add(mat);
      }

      // Find the outline on a small copy; it is faster and ignores print.
      final scale = math.min(1.0, 800 / math.max(mat.cols, mat.rows));
      final small = await cv.resizeAsync(mat, (
        (mat.cols * scale).round(),
        (mat.rows * scale).round(),
      ), interpolation: cv.INTER_AREA);
      final gray = await cv.cvtColorAsync(small, cv.COLOR_BGR2GRAY);
      final blurred = await cv.gaussianBlurAsync(gray, (5, 5), 0);
      final edges = await cv.cannyAsync(blurred, 50, 150);
      final kernel = cv.getStructuringElement(cv.MORPH_RECT, (5, 5));
      final closed = await cv.dilateAsync(edges, kernel);
      toDispose.addAll([small, gray, blurred, edges, kernel, closed]);

      final (contours, hierarchy) = await cv.findContoursAsync(
        closed,
        cv.RETR_EXTERNAL,
        cv.CHAIN_APPROX_SIMPLE,
      );
      final minArea = 0.35 * small.cols * small.rows;
      List<cv.Point>? corners;
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
          corners = [for (var k = 0; k < 4; k++) approx[k]];
        }
      }
      hierarchy.dispose();
      if (corners == null) return null;
      // A page reaching the photo's edge is cut off. Flattening it would hide
      // that from the framing check, so the plain photo is kept.
      final dx = small.cols * DocumentFraming.edgeMargin;
      final dy = small.rows * DocumentFraming.edgeMargin;
      if (corners.any(
        (p) =>
            p.x <= dx ||
            p.y <= dy ||
            p.x >= small.cols - dx ||
            p.y >= small.rows - dy,
      )) {
        return null;
      }

      // Order: top-left, top-right, bottom-right, bottom-left.
      int sum(cv.Point p) => p.x + p.y;
      int diff(cv.Point p) => p.y - p.x;
      final tl = corners.reduce((a, b) => sum(a) <= sum(b) ? a : b);
      final br = corners.reduce((a, b) => sum(a) >= sum(b) ? a : b);
      final tr = corners.reduce((a, b) => diff(a) <= diff(b) ? a : b);
      final bl = corners.reduce((a, b) => diff(a) >= diff(b) ? a : b);
      cv.Point up(cv.Point p) =>
          cv.Point((p.x / scale).round(), (p.y / scale).round());

      final outHeight = (outWidth * 297 / 210).round();
      final from = cv.VecPoint.fromList([up(tl), up(tr), up(br), up(bl)]);
      final to = cv.VecPoint.fromList([
        cv.Point(0, 0),
        cv.Point(outWidth - 1, 0),
        cv.Point(outWidth - 1, outHeight - 1),
        cv.Point(0, outHeight - 1),
      ]);
      final transform = cv.getPerspectiveTransform(from, to);
      final page = await cv.warpPerspectiveAsync(mat, transform, (
        outWidth,
        outHeight,
      ));
      toDispose.addAll([transform, page]);

      return await _write(page, label);
    } finally {
      for (final m in toDispose) {
        m.dispose();
      }
    }
  }

  /// A contrast-normalised copy (CLAHE on the lightness channel) for a second
  /// OCR attempt on a dim or uneven photo.
  Future<String> enhance(String inputPath, {String label = 'enhanced'}) async {
    final mat = await cv.imreadAsync(inputPath);
    if (mat.isEmpty) {
      mat.dispose();
      throw StateError('Failed to read image: $inputPath');
    }
    final toDispose = <cv.Mat>[mat];
    try {
      final lab = await cv.cvtColorAsync(mat, cv.COLOR_BGR2Lab);
      final channels = await cv.splitAsync(lab);
      final clahe = cv.CLAHE(2.0, (8, 8));
      final lightness = await clahe.applyAsync(channels[0]);
      final merged = await cv.mergeAsync(
        cv.VecMat.fromList([lightness, channels[1], channels[2]]),
      );
      final result = await cv.cvtColorAsync(merged, cv.COLOR_Lab2BGR);
      toDispose.addAll([lab, lightness, merged, result]);
      clahe.dispose();
      channels.dispose();
      return await _write(result, label);
    } finally {
      for (final m in toDispose) {
        m.dispose();
      }
    }
  }

  /// A strip of the photo in pixel coordinates (clamped to the image),
  /// upscaled to at least [minWidth] and optionally contrast-normalised. Used
  /// to re-read one row whose digits the full-page pass missed.
  Future<String> cropPixels(
    String inputPath, {
    required double left,
    required double top,
    required double right,
    required double bottom,
    int minWidth = 0,
    bool enhance = false,
    String label = 'region',
  }) async {
    final mat = await cv.imreadAsync(inputPath);
    if (mat.isEmpty) {
      mat.dispose();
      throw StateError('Failed to read image: $inputPath');
    }
    final toDispose = <cv.Mat>[mat];
    try {
      final x = left.floor().clamp(0, mat.cols - 1);
      final y = top.floor().clamp(0, mat.rows - 1);
      final w = (right.ceil() - x).clamp(1, mat.cols - x);
      final h = (bottom.ceil() - y).clamp(1, mat.rows - y);
      var result = mat.region(cv.Rect(x, y, w, h));
      toDispose.add(result);

      if (minWidth > 0 && result.cols < minWidth) {
        final scale = minWidth / result.cols;
        result = await cv.resizeAsync(result, (
          minWidth,
          (result.rows * scale).round(),
        ), interpolation: cv.INTER_CUBIC);
        toDispose.add(result);
      }
      if (enhance) {
        final lab = await cv.cvtColorAsync(result, cv.COLOR_BGR2Lab);
        final channels = await cv.splitAsync(lab);
        final clahe = cv.CLAHE(3.0, (4, 4));
        final lightness = await clahe.applyAsync(channels[0]);
        final merged = await cv.mergeAsync(
          cv.VecMat.fromList([lightness, channels[1], channels[2]]),
        );
        result = await cv.cvtColorAsync(merged, cv.COLOR_Lab2BGR);
        toDispose.addAll([lab, lightness, merged, result]);
        clahe.dispose();
        channels.dispose();
      }
      return await _write(result, label);
    } finally {
      for (final m in toDispose) {
        m.dispose();
      }
    }
  }

  Future<String> _write(cv.Mat image, String label) async {
    final dir = await getTemporaryDirectory();
    final outputPath =
        '${dir.path}/${label}_${DateTime.now().microsecondsSinceEpoch}.png';
    if (!await cv.imwriteAsync(outputPath, image)) {
      throw StateError('Failed to write image');
    }
    return outputPath;
  }

  Future<void> deleteTemp(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}
