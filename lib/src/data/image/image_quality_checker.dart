import 'package:idlens/src/data/image/image_ops.dart';
import 'package:idlens/src/domain/document_kind.dart';
import 'package:idlens/src/domain/image_quality.dart';
import 'package:opencv_dart/opencv.dart' as cv;

/// Measures blur, darkness and glare on the MRZ band of a photo. Used to
/// explain why an MRZ could not be read, never to reject an image by itself.
class ImageQualityChecker {
  ImageQualityChecker(this._imageOps);

  final ImageOps _imageOps;

  /// Returns null when the image cannot be read. [documentCoverage] comes
  /// from `DocumentFrameChecker`, which measures the whole photo.
  Future<ImageQuality?> check(
    String imagePath,
    DocumentKind kind, {
    double documentCoverage = 1,
  }) async {
    String? bandPath;
    try {
      bandPath = await _imageOps.crop(
        imagePath,
        top: 1 - kind.mrzBandFraction,
        label: 'quality_band',
      );
      final quality = await _measure(bandPath);
      if (quality == null) return null;
      return ImageQuality(
        sharpness: quality.sharpness,
        brightness: quality.brightness,
        glareShare: quality.glareShare,
        documentCoverage: documentCoverage,
      );
    } catch (_) {
      return null;
    } finally {
      if (bandPath != null) await _imageOps.deleteTemp(bandPath);
    }
  }

  /// Clarity of a whole photo with no MRZ band (the Sudan ID front and the
  /// civil registry certificate): brightness, sharpness taken from the
  /// text-dense tiles only (blank paper has no edges even in a sharp photo),
  /// and how much of the frame the document covers. Glare is not judged: a
  /// white page would always look like glare.
  Future<ImageQuality?> checkWhole(
    String imagePath, {
    double documentCoverage = 1,
  }) async {
    final image = await cv.imreadAsync(imagePath, flags: cv.IMREAD_GRAYSCALE);
    if (image.isEmpty) {
      image.dispose();
      return null;
    }
    final mats = <cv.Mat>[image];
    try {
      final scale = ImageQuality.bandWidth / image.cols;
      final page = await cv.resizeAsync(image, (
        ImageQuality.bandWidth,
        (image.rows * scale).round().clamp(1, 1 << 20),
      ), interpolation: scale < 1 ? cv.INTER_AREA : cv.INTER_LINEAR);
      final laplacian = await cv.laplacianAsync(page, cv.MatType.CV_64F);
      mats.addAll([page, laplacian]);

      const grid = 8;
      final tileWidth = page.cols ~/ grid;
      final tileHeight = page.rows ~/ grid;
      final variances = <double>[];
      for (var row = 0; row < grid; row++) {
        for (var col = 0; col < grid; col++) {
          final tile = laplacian.region(
            cv.Rect(col * tileWidth, row * tileHeight, tileWidth, tileHeight),
          );
          final (_, std) = cv.meanStdDev(tile);
          variances.add(std.val1 * std.val1);
          tile.dispose();
        }
      }
      variances.sort();
      // The 90th percentile: sharp text makes some tiles very sharp, a blurry
      // photo has none.
      final sharpness =
          variances[(variances.length * 0.9).floor().clamp(
            0,
            variances.length - 1,
          )];

      return ImageQuality(
        sharpness: sharpness,
        brightness: page.mean().val1,
        glareShare: 0,
        documentCoverage: documentCoverage,
      );
    } finally {
      for (final m in mats) {
        m.dispose();
      }
    }
  }

  Future<ImageQuality?> _measure(String bandPath) async {
    final image = await cv.imreadAsync(bandPath, flags: cv.IMREAD_GRAYSCALE);
    if (image.isEmpty) {
      image.dispose();
      return null;
    }
    final mats = <cv.Mat>[image];
    try {
      // Same width for every photo so the sharpness numbers are comparable.
      final scale = ImageQuality.bandWidth / image.cols;
      final band = await cv.resizeAsync(image, (
        ImageQuality.bandWidth,
        (image.rows * scale).round().clamp(1, 1 << 20),
      ), interpolation: scale < 1 ? cv.INTER_AREA : cv.INTER_LINEAR);
      mats.add(band);

      final laplacian = await cv.laplacianAsync(band, cv.MatType.CV_64F);
      mats.add(laplacian);
      final (_, laplacianStd) = cv.meanStdDev(laplacian);
      final sharpness = laplacianStd.val1 * laplacianStd.val1;

      final brightness = band.mean().val1;

      final (_, bright) = await cv.thresholdAsync(
        band,
        250,
        255,
        cv.THRESH_BINARY,
      );
      mats.add(bright);
      final glareShare = cv.countNonZero(bright) / (band.rows * band.cols);

      return ImageQuality(
        sharpness: sharpness,
        brightness: brightness,
        glareShare: glareShare,
      );
    } finally {
      for (final m in mats) {
        m.dispose();
      }
    }
  }
}
