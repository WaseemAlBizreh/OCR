import 'dart:io';
import 'dart:ui' show Rect, Size;

import 'package:idlens/src/presentation/widgets/card_frame_overlay.dart'
    show CardFrame;

/// One photo handed to a `process...` method, and how idlens should treat it.
///
/// There are two forms:
///
/// * [DocumentPhoto.camera]: a raw photo from your own camera. idlens crops
///   it, then reads it.
/// * [DocumentPhoto.file]: a finished photo, read as it is.
class DocumentPhoto {
  DocumentPhoto._(this.file, this._box, this._previewSize);

  /// A raw photo from your own camera. idlens crops it around [box], a little
  /// wider on every side so the background shows around the document, then
  /// reads it. That strip is how idlens tells a cut-off or distant document
  /// from a good one, so you don't cut the photo yourself.
  ///
  /// * [box] is the rectangle the user fitted the document into, in the same
  ///   logical pixels as [previewSize]. Take it from
  ///   `DocumentGuide.forPreview`, so it leaves room for the strip.
  /// * [previewSize] is the area the camera image fills on screen. A camera
  ///   image shown full screen and cropped to fit is fine: the photo is mapped
  ///   onto it, whatever its own shape. An image shown whole, with bars around
  ///   it, needs the image's own size instead of the screen's.
  /// * The camera should be in portrait. A photo with landscape pixels is
  ///   turned upright first.
  /// * [file] is never changed or deleted. The result's `images` hold the
  ///   cropped photos: temporary files that its `dispose()` deletes.
  ///
  /// Throws [ArgumentError] when [previewSize] or [box] is empty, or [box]
  /// reaches outside [previewSize].
  factory DocumentPhoto.camera(
    File file, {
    required Rect box,
    required Size previewSize,
  }) {
    const slack = 1.0; // a pixel of rounding is fine
    if (previewSize.isEmpty) {
      throw ArgumentError.value(
        previewSize,
        'previewSize',
        'must not be empty',
      );
    }
    if (box.isEmpty ||
        box.left < -slack ||
        box.top < -slack ||
        box.right > previewSize.width + slack ||
        box.bottom > previewSize.height + slack) {
      throw ArgumentError.value(box, 'box', 'must lie inside previewSize');
    }
    return DocumentPhoto._(file, box, previewSize);
  }

  /// A finished photo, read as it is: one from a server or the gallery, or a
  /// `scan...` result read again. Use [DocumentPhoto.camera] instead whenever
  /// your own camera took the photo.
  ///
  /// Keep a thin strip of background around the document (about 6% of its
  /// size): that is how idlens tells a cut-off or distant document from a
  /// good one. A photo cropped exactly to the document can only be checked
  /// from its text, which is less reliable.
  ///
  /// [file] is never changed or deleted, and is the result's image.
  DocumentPhoto.file(this.file) : _box = null, _previewSize = null;

  /// The photo file.
  final File file;

  final Rect? _box;
  final Size? _previewSize;

  /// Whether idlens crops this photo ([DocumentPhoto.camera]).
  bool get isCamera => _box != null;

  /// The camera area's width / height. Only for a camera photo.
  double get viewAspect {
    final size = _previewSize!;
    return size.width / size.height;
  }

  /// The box as fractions of the camera area. Only for a camera photo.
  CardFrame get frame {
    final box = _box!;
    final size = _previewSize!;
    return CardFrame(
      left: box.left / size.width,
      top: box.top / size.height,
      right: box.right / size.width,
      bottom: box.bottom / size.height,
    );
  }
}
