import 'package:idlens/src/data/image/image_ops.dart';
import 'package:idlens/src/presentation/widgets/card_frame_overlay.dart';
import 'package:idlens/src/services.dart';

/// Crops [photoPath] around [frame], [CardFrame.captureMargin] wider than the
/// frame on every side, and returns the path of the new PNG.
///
/// [frame] is in fractions of the camera area on screen, whose width / height
/// is [viewAspect]; the photo may have another shape (see `ViewCrop`).
///
/// The one place that makes the photo idlens' reader expects, used by both
/// idlens' own camera and `process...` with a camera photo, so they cannot
/// drift apart. [imageOps] defaults to the shared one.
Future<String> cropAroundFrame(
  String photoPath,
  CardFrame frame, {
  required double viewAspect,
  required String label,
  ImageOps? imageOps,
}) {
  final crop = frame.expanded(CardFrame.captureMargin);
  return (imageOps ?? IdLensServices.instance.imageOps).crop(
    photoPath,
    left: crop.left,
    top: crop.top,
    right: crop.right,
    bottom: crop.bottom,
    portrait: true,
    viewAspect: viewAspect,
    label: label,
  );
}
