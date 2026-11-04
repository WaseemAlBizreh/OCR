import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:idlens/src/api/document_guide.dart';
import 'package:idlens/src/domain/document_kind.dart';
import 'package:idlens/src/presentation/widgets/card_frame_overlay.dart';

void main() {
  const preview = Size(400, 800);

  DocumentGuide guide(
    DocumentKind kind,
    DocumentSide side, {
    double? maxHeight,
  }) => DocumentGuide.forPreview(
    kind: kind,
    side: side,
    previewSize: preview,
    maxHeight: maxHeight,
  );

  test('the box is 86% of the width, centred, in the document shape', () {
    final g = guide(DocumentKind.sudanId, DocumentSide.front);
    expect(g.box.width, closeTo(344, 1e-6));
    expect(g.box.width / g.box.height, closeTo(85.6 / 54, 1e-6));
    expect(g.box.center.dx, closeTo(200, 1e-6));
    expect(g.box.center.dy, closeTo(400, 1e-6));
  });

  test('the box is the one idlens\' own camera draws', () {
    for (final kind in DocumentKind.values) {
      final g = guide(kind, kind.sides.first);
      final own = CardFrame.centered(
        previewSize: preview,
        aspectRatio: kind.aspectRatio,
      ).toRect(preview);
      expect(g.box.left, closeTo(own.left, 1e-9));
      expect(g.box.top, closeTo(own.top, 1e-9));
      expect(g.box.right, closeTo(own.right, 1e-9));
      expect(g.box.bottom, closeTo(own.bottom, 1e-9));
    }
  });

  test('the 6% margin around the box always fits inside the preview', () {
    for (final kind in DocumentKind.values) {
      final g = guide(kind, kind.sides.first);
      final dx = g.box.width * CardFrame.captureMargin;
      final dy = g.box.height * CardFrame.captureMargin;
      expect(g.box.left - dx, greaterThan(0));
      expect(g.box.top - dy, greaterThan(0));
      expect(g.box.right + dx, lessThan(preview.width));
      expect(g.box.bottom + dy, lessThan(preview.height));
    }
  });

  test('only a page with an MRZ gets an MRZ guide', () {
    expect(guide(DocumentKind.sudanId, DocumentSide.front).mrzGuide, isNull);
    expect(guide(DocumentKind.sudanId, DocumentSide.back).mrzGuide, isNotNull);
    expect(
      guide(DocumentKind.passport, DocumentSide.dataPage).mrzGuide,
      isNotNull,
    );
    expect(
      guide(DocumentKind.civilRegistryCertificate, DocumentSide.page).mrzGuide,
      isNull,
    );
  });

  test('the MRZ guide sits along the bottom of the box', () {
    final g = guide(DocumentKind.sudanId, DocumentSide.back);
    final mrz = g.mrzGuide!;
    expect(mrz.left, closeTo(g.box.left + 8, 1e-9));
    expect(mrz.right, closeTo(g.box.right - 8, 1e-9));
    expect(mrz.bottom, closeTo(g.box.bottom - 8, 1e-9));
    expect(mrz.height, closeTo(g.box.height * 0.34 - 8, 1e-9));
  });

  test('maxHeight shrinks the box and keeps its shape', () {
    final free = guide(
      DocumentKind.civilRegistryCertificate,
      DocumentSide.page,
    );
    final g = guide(
      DocumentKind.civilRegistryCertificate,
      DocumentSide.page,
      maxHeight: 400,
    );
    expect(g.box.height, closeTo(400, 1e-6));
    expect(g.box.height, lessThan(free.box.height));
    expect(g.box.width / g.box.height, closeTo(210 / 297, 1e-6));
    expect(g.box.center.dy, closeTo(400, 1e-6));
  });

  test('a maxHeight above the usual box changes nothing', () {
    final free = guide(DocumentKind.sudanId, DocumentSide.front);
    final g = guide(DocumentKind.sudanId, DocumentSide.front, maxHeight: 700);
    expect(g.box, free.box);
  });

  test('a side that is not a page of the document is refused', () {
    expect(
      () => guide(DocumentKind.passport, DocumentSide.front),
      throwsArgumentError,
    );
  });

  test('an empty preview or a non-positive maxHeight is refused', () {
    expect(
      () => DocumentGuide.forPreview(
        kind: DocumentKind.sudanId,
        side: DocumentSide.front,
        previewSize: Size.zero,
      ),
      throwsArgumentError,
    );
    expect(
      () => guide(DocumentKind.sudanId, DocumentSide.front, maxHeight: 0),
      throwsArgumentError,
    );
  });
}
