import 'dart:io';

import 'package:injectable/injectable.dart';
import 'package:opencv_dart/opencv.dart' as cv;
import 'package:path_provider/path_provider.dart';

/// Crops used by the capture screen and by the MRZ reader.
@lazySingleton
class ImageOps {
  /// Crops [inputPath] to the given fractions (0..1) of its width and height.
  ///
  /// [portrait] rotates the image first when its pixels are landscape, which
  /// some Android devices return even for a portrait capture. When
  /// [minWidth] is set, a narrower result is upscaled to that width, which
  /// helps OCR on thin MRZ characters.
  Future<String> crop(
    String inputPath, {
    double left = 0,
    double top = 0,
    double right = 1,
    double bottom = 1,
    bool portrait = false,
    int minWidth = 0,
    String label = 'crop',
  }) async {
    var mat = cv.imread(inputPath);
    if (mat.isEmpty) {
      mat.dispose();
      throw StateError('Failed to read image: $inputPath');
    }

    final toDispose = <cv.Mat>[mat];
    try {
      if (portrait && mat.cols > mat.rows) {
        mat = cv.rotate(mat, cv.ROTATE_90_CLOCKWISE);
        toDispose.add(mat);
      }

      final x = (mat.cols * left).round().clamp(0, mat.cols - 1);
      final y = (mat.rows * top).round().clamp(0, mat.rows - 1);
      final w = ((mat.cols * right).round() - x).clamp(1, mat.cols - x);
      final h = ((mat.rows * bottom).round() - y).clamp(1, mat.rows - y);

      var result = mat.region(cv.Rect(x, y, w, h));
      toDispose.add(result);

      if (minWidth > 0 && result.cols < minWidth) {
        final scale = minWidth / result.cols;
        result = cv.resize(
          result,
          (minWidth, (result.rows * scale).round()),
          interpolation: cv.INTER_CUBIC,
        );
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

  Future<void> deleteTemp(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}
