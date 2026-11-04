import 'package:flutter_test/flutter_test.dart';
import 'package:idlens/src/domain/view_crop.dart';

void main() {
  const box = (left: 0.1, top: 0.2, right: 0.9, bottom: 0.8);

  void expectCrop(CropFractions actual, CropFractions expected) {
    expect(actual.left, closeTo(expected.left, 1e-9));
    expect(actual.top, closeTo(expected.top, 1e-9));
    expect(actual.right, closeTo(expected.right, 1e-9));
    expect(actual.bottom, closeTo(expected.bottom, 1e-9));
  }

  test('the same shape keeps the crop as it is', () {
    expectCrop(
      ViewCrop.toPhoto(box, viewAspect: 9 / 16, photoAspect: 9 / 16),
      box,
    );
  });

  test(
    'a photo wider than the preview narrows the crop to the middle columns',
    () {
      // Portrait 9:16 preview, portrait 3:4 photo: the photo is wider, so the
      // preview shows its middle 75% of columns.
      final onPhoto = ViewCrop.toPhoto(
        box,
        viewAspect: 9 / 16,
        photoAspect: 3 / 4,
      );
      const s = (9 / 16) / (3 / 4); // 0.75
      expectCrop(onPhoto, (
        left: 0.5 - 0.4 * s,
        top: 0.2,
        right: 0.5 + 0.4 * s,
        bottom: 0.8,
      ));
    },
  );

  test(
    'a photo taller than the preview narrows the crop to the middle rows',
    () {
      // Portrait 3:4 preview, portrait 9:16 photo: the preview shows the middle
      // 75% of the photo's rows.
      final onPhoto = ViewCrop.toPhoto(
        box,
        viewAspect: 3 / 4,
        photoAspect: 9 / 16,
      );
      const s = (9 / 16) / (3 / 4);
      expectCrop(onPhoto, (
        left: 0.1,
        top: 0.5 - 0.3 * s,
        right: 0.9,
        bottom: 0.5 + 0.3 * s,
      ));
    },
  );

  test('the crop never leaves the photo', () {
    final onPhoto = ViewCrop.toPhoto(
      (left: -0.2, top: -0.1, right: 1.3, bottom: 1.2),
      viewAspect: 1,
      photoAspect: 1,
    );
    expectCrop(onPhoto, (left: 0, top: 0, right: 1, bottom: 1));
  });
}
