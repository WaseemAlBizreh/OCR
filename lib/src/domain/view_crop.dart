/// A crop given as fractions (0..1) of an image's width and height.
typedef CropFractions = ({
  double left,
  double top,
  double right,
  double bottom,
});

/// Moves a crop drawn on the camera preview onto the photo.
///
/// The preview and the photo usually have the same shape. On some phones they
/// don't: a 16:9 preview with a 4:3 photo, for example. Both are then centred
/// crops of the camera sensor, so the preview shows the middle of the photo,
/// and the same fractions would land in the wrong place on the photo.
class ViewCrop {
  ViewCrop._();

  /// [crop] in fractions of a preview whose width / height is [viewAspect],
  /// as fractions of a photo whose width / height is [photoAspect]. Both
  /// aspects are in the same orientation. The result stays inside the photo.
  static CropFractions toPhoto(
    CropFractions crop, {
    required double viewAspect,
    required double photoAspect,
  }) {
    var sx = 1.0;
    var sy = 1.0;
    if (photoAspect > viewAspect) {
      // The photo is wider: the preview shows its middle band of columns.
      sx = viewAspect / photoAspect;
    } else if (photoAspect < viewAspect) {
      // The photo is taller: the preview shows its middle band of rows.
      sy = photoAspect / viewAspect;
    }
    double unit(double v) => v.clamp(0.0, 1.0).toDouble();
    return (
      left: unit(0.5 + (crop.left - 0.5) * sx),
      top: unit(0.5 + (crop.top - 0.5) * sy),
      right: unit(0.5 + (crop.right - 0.5) * sx),
      bottom: unit(0.5 + (crop.bottom - 0.5) * sy),
    );
  }
}
