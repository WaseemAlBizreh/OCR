import 'dart:io';

import 'package:injectable/injectable.dart';
import 'package:opencv_dart/opencv.dart' as cv;
import 'package:path_provider/path_provider.dart';

/// Grayscale + CLAHE preprocessing for document OCR.
@lazySingleton
class OpenCvImageEnhancer {
  Future<String> enhance(String inputPath) async {
    if (!await File(inputPath).exists()) {
      throw StateError('Image file not found: $inputPath');
    }

    final mat = cv.imread(inputPath);
    if (mat.isEmpty) {
      mat.dispose();
      throw StateError('Failed to read image: $inputPath');
    }

    cv.Mat? gray;
    cv.Mat? enhanced;
    cv.CLAHE? clahe;

    try {
      gray = await cv.cvtColorAsync(mat, cv.COLOR_BGR2GRAY);
      clahe = cv.createCLAHE(clipLimit: 2.0, tileGridSize: (8, 8));
      enhanced = await clahe.applyAsync(gray);

      final tempDir = await getTemporaryDirectory();
      final outputPath =
          '${tempDir.path}/enhanced_${DateTime.now().microsecondsSinceEpoch}.jpg';

      final written = await cv.imwriteAsync(outputPath, enhanced);
      if (!written) {
        throw StateError('Failed to write enhanced image');
      }

      return outputPath;
    } finally {
      mat.dispose();
      gray?.dispose();
      enhanced?.dispose();
      clahe?.dispose();
    }
  }

  Future<void> deleteTemp(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
