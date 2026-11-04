import 'dart:ui' show Rect, Size;

import 'package:idlens/src/domain/document_kind.dart';
import 'package:idlens/src/presentation/widgets/card_frame_overlay.dart';

/// Where an app should draw the document box on its own camera screen, so the
/// photo it takes can be cropped the way idlens' reader expects.
///
/// Draw [box] (and [mrzGuide], when it is not null) over the camera image,
/// ask the user to fit the document inside, take the photo, then pass the
/// same [box] and the size of the camera area to `IdLens.cropDocument`.
///
/// The numbers are idlens' own: the box and the MRZ guide are the ones its
/// built-in camera draws. The box is deliberately smaller than the screen
/// (86% of the width, at most 86% of the height), so that the 6% margin
/// `cropDocument` keeps around it fits inside the photo.
class DocumentGuide {
  const DocumentGuide._({required this.box, required this.mrzGuide});

  /// The guide for a [kind] document in a camera area of [previewSize].
  ///
  /// [previewSize] is the area the camera image fills on screen, in logical
  /// pixels: the whole screen when the image is shown full screen and
  /// cropped to fit, or the image's own size when it is shown whole. The box
  /// is centred in it.
  ///
  /// [maxHeight] limits the box's height, for screens where text or buttons
  /// need room above and below it. The box then shrinks and keeps the
  /// document's shape; null means no limit beyond 86% of the height.
  ///
  /// The MRZ guide is only given for a page that has an MRZ: the back of an
  /// ID card and a passport's data page.
  factory DocumentGuide.forPreview({
    required DocumentKind kind,
    required DocumentSide side,
    required Size previewSize,
    double? maxHeight,
  }) {
    if (previewSize.isEmpty) {
      throw ArgumentError.value(
        previewSize,
        'previewSize',
        'must not be empty',
      );
    }
    if (!kind.sides.contains(side)) {
      throw ArgumentError.value(side, 'side', 'is not a page of ${kind.name}');
    }
    var heightFactor = 0.86;
    if (maxHeight != null) {
      if (maxHeight <= 0) {
        throw ArgumentError.value(maxHeight, 'maxHeight', 'must be positive');
      }
      heightFactor = (maxHeight / previewSize.height).clamp(0.0, heightFactor);
    }
    final box = CardFrame.centered(
      previewSize: previewSize,
      aspectRatio: kind.aspectRatio,
      heightFactor: heightFactor,
    ).toRect(previewSize);
    final showsMrz = kind.hasMrz && side != DocumentSide.front;
    return DocumentGuide._(
      box: box,
      mrzGuide: showsMrz
          ? CardFrame.mrzGuideRect(box, kind.mrzGuideFraction)
          : null,
    );
  }

  /// The document box, in the same logical pixels as the `previewSize`.
  /// Draw it as a window in a dark layer, or as a border.
  final Rect box;

  /// The strip along the bottom of [box] where the MRZ lines should sit, or
  /// null when this page has no MRZ. Label it "MRZ": that is the standard's
  /// name and is not translated.
  final Rect? mrzGuide;
}
