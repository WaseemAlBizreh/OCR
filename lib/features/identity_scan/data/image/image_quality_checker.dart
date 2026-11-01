import 'package:injectable/injectable.dart';
import 'package:mrz/features/identity_scan/data/image/image_ops.dart';
import 'package:mrz/features/identity_scan/domain/document_kind.dart';
import 'package:mrz/features/identity_scan/domain/image_quality.dart';
import 'package:opencv_dart/opencv.dart' as cv;

/// Measures blur, darkness and glare on the MRZ band of a photo. Used to
/// explain why an MRZ could not be read, never to reject an image by itself.
@lazySingleton
class ImageQualityChecker {
  ImageQualityChecker(this._imageOps);

  final ImageOps _imageOps;

  /// Returns null when the image cannot be read.
  Future<ImageQuality?> check(String imagePath, DocumentKind kind) async {
    String? bandPath;
    try {
      bandPath = await _imageOps.crop(
        imagePath,
        top: 1 - kind.mrzBandFraction,
        label: 'quality_band',
      );
      final quality = _measure(bandPath);
      if (quality == null) return null;
      return ImageQuality(
        sharpness: quality.sharpness,
        brightness: quality.brightness,
        glareShare: quality.glareShare,
        documentCoverage: _coverage(imagePath),
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
  ImageQuality? checkWhole(String imagePath) {
    final image = cv.imread(imagePath, flags: cv.IMREAD_GRAYSCALE);
    if (image.isEmpty) {
      image.dispose();
      return null;
    }
    final mats = <cv.Mat>[image];
    try {
      final scale = ImageQuality.bandWidth / image.cols;
      final page = cv.resize(
        image,
        (ImageQuality.bandWidth, (image.rows * scale).round().clamp(1, 1 << 20)),
        interpolation: scale < 1 ? cv.INTER_AREA : cv.INTER_LINEAR,
      );
      final laplacian = cv.laplacian(page, cv.MatType.CV_64F);
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
      final sharpness = variances[(variances.length * 0.9).floor().clamp(0, variances.length - 1)];

      return ImageQuality(
        sharpness: sharpness,
        brightness: page.mean().val1,
        glareShare: 0,
        documentCoverage: _coverage(imagePath),
      );
    } finally {
      for (final m in mats) {
        m.dispose();
      }
    }
  }

  /// Share of the frame taken by the largest bright region (the document on
  /// a darker background). 1 when no clear region is found, so an unusual
  /// background never makes a good photo look like a far one.
  double _coverage(String imagePath) {
    final image = cv.imread(imagePath, flags: cv.IMREAD_GRAYSCALE);
    if (image.isEmpty) {
      image.dispose();
      return 1;
    }
    final mats = <cv.Mat>[image];
    try {
      final scale = 400 / image.cols;
      final small = cv.resize(
        image,
        (400, (image.rows * scale).round().clamp(1, 1 << 20)),
        interpolation: cv.INTER_AREA,
      );
      final blurred = cv.gaussianBlur(small, (7, 7), 0);
      final (_, binary) = cv.threshold(blurred, 0, 255, cv.THRESH_BINARY | cv.THRESH_OTSU);
      final kernel = cv.getStructuringElement(cv.MORPH_RECT, (15, 15));
      final closed = cv.morphologyEx(binary, cv.MORPH_CLOSE, kernel);
      mats.addAll([small, blurred, binary, kernel, closed]);

      final (contours, hierarchy) =
          cv.findContours(closed, cv.RETR_EXTERNAL, cv.CHAIN_APPROX_SIMPLE);
      var best = 0.0;
      cv.Rect? box;
      for (var i = 0; i < contours.length; i++) {
        final area = cv.contourArea(contours[i]);
        if (area > best) {
          best = area;
          box = cv.boundingRect(contours[i]);
        }
      }
      hierarchy.dispose();
      if (box == null) return 1;
      return (box.width * box.height) / (small.cols * small.rows);
    } finally {
      for (final m in mats) {
        m.dispose();
      }
    }
  }

  ImageQuality? _measure(String bandPath) {
    final image = cv.imread(bandPath, flags: cv.IMREAD_GRAYSCALE);
    if (image.isEmpty) {
      image.dispose();
      return null;
    }
    final mats = <cv.Mat>[image];
    try {
      // Same width for every photo so the sharpness numbers are comparable.
      final scale = ImageQuality.bandWidth / image.cols;
      final band = cv.resize(
        image,
        (ImageQuality.bandWidth, (image.rows * scale).round().clamp(1, 1 << 20)),
        interpolation: scale < 1 ? cv.INTER_AREA : cv.INTER_LINEAR,
      );
      mats.add(band);

      final laplacian = cv.laplacian(band, cv.MatType.CV_64F);
      mats.add(laplacian);
      final (_, laplacianStd) = cv.meanStdDev(laplacian);
      final sharpness = laplacianStd.val1 * laplacianStd.val1;

      final brightness = band.mean().val1;

      final (_, bright) = cv.threshold(band, 250, 255, cv.THRESH_BINARY);
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
