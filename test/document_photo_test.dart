import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:idlens/src/api/document_photo.dart';

void main() {
  const preview = Size(400, 800);
  final file = File('photo.jpg');

  group('DocumentPhoto.camera', () {
    test('takes a box inside the preview', () {
      final photo = DocumentPhoto.camera(
        file,
        box: const Rect.fromLTRB(40, 100, 360, 700),
        previewSize: preview,
      );
      expect(photo.isCamera, isTrue);
      expect(photo.file, file);
    });

    test('allows a pixel of rounding past the preview', () {
      final photo = DocumentPhoto.camera(
        file,
        box: const Rect.fromLTRB(-0.5, 0, 400.5, 800),
        previewSize: preview,
      );
      expect(photo.isCamera, isTrue);
    });

    test('refuses an empty box', () {
      expect(
        () => DocumentPhoto.camera(file, box: Rect.zero, previewSize: preview),
        throwsArgumentError,
      );
    });

    test('refuses a box outside the preview', () {
      expect(
        () => DocumentPhoto.camera(
          file,
          box: const Rect.fromLTRB(0, 0, 500, 100),
          previewSize: preview,
        ),
        throwsArgumentError,
      );
      expect(
        () => DocumentPhoto.camera(
          file,
          box: const Rect.fromLTRB(-20, 0, 100, 100),
          previewSize: preview,
        ),
        throwsArgumentError,
      );
    });

    test('refuses an empty preview', () {
      expect(
        () => DocumentPhoto.camera(
          file,
          box: const Rect.fromLTWH(10, 10, 100, 100),
          previewSize: Size.zero,
        ),
        throwsArgumentError,
      );
    });

    test('gives the box as fractions of the preview', () {
      final photo = DocumentPhoto.camera(
        file,
        box: const Rect.fromLTRB(40, 100, 360, 700),
        previewSize: preview,
      );
      expect(photo.frame.left, closeTo(0.1, 1e-9));
      expect(photo.frame.top, closeTo(0.125, 1e-9));
      expect(photo.frame.right, closeTo(0.9, 1e-9));
      expect(photo.frame.bottom, closeTo(0.875, 1e-9));
      expect(photo.viewAspect, closeTo(0.5, 1e-9));
    });
  });

  group('DocumentPhoto.file', () {
    test('is read as it is, with no box', () {
      final photo = DocumentPhoto.file(File('done.png'));
      expect(photo.isCamera, isFalse);
      expect(photo.file.path, 'done.png');
    });
  });
}
