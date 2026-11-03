import 'package:flutter_test/flutter_test.dart';
import 'package:idlens/src/domain/image_quality.dart';
import 'package:idlens/src/domain/scan_issue.dart';

void main() {
  ImageQuality quality({
    double sharpness = 300,
    double brightness = 160,
    double glare = 0.02,
    double coverage = 0.9,
  }) => ImageQuality(
    sharpness: sharpness,
    brightness: brightness,
    glareShare: glare,
    documentCoverage: coverage,
  );

  test('a sharp, evenly lit band has no problem', () {
    expect(quality().problem, isNull);
  });

  test('low sharpness is not clear', () {
    expect(quality(sharpness: 10).problem, ScanIssue.imageNotClear);
  });

  test('low brightness is not clear', () {
    expect(quality(brightness: 30).problem, ScanIssue.imageNotClear);
  });

  test('a large white share is not clear', () {
    expect(quality(glare: 0.4).problem, ScanIssue.imageNotClear);
  });

  test('a small document in a dark frame is not-in-frame, not too dark', () {
    // Measured on a device: passport far from the camera, MRZ still read.
    expect(
      quality(brightness: 105.3, sharpness: 616.6, coverage: 0.4).problem,
      ScanIssue.documentNotInFrame,
    );
  });

  test('the dim, unclear passport photo measured on a device is flagged', () {
    // sharpness 45.9, brightness 96.1, glare 0.00015
    expect(
      quality(sharpness: 45.9, brightness: 96.1, glare: 0.00015).problem,
      ScanIssue.imageNotClear,
    );
  });

  group('ScanIssueResolver', () {
    test('an empty frame is documentNotInFrame, not "too dark"', () {
      expect(
        ScanIssueResolver.resolve(
          mrzMissing: true,
          recognizedFields: 0,
          imageIssue: ScanIssue.imageNotClear,
        ),
        ScanIssue.documentNotInFrame,
      );
    });

    test(
      'text cut off at two edges is documentNotInFrame even with an MRZ',
      () {
        expect(
          ScanIssueResolver.resolve(recognizedFields: 8, frameTouchedSides: 2),
          ScanIssue.documentNotInFrame,
        );
      },
    );

    test('text at only one edge is accepted', () {
      expect(
        ScanIssueResolver.resolve(recognizedFields: 8, frameTouchedSides: 1),
        isNull,
      );
    });

    test('a far document wins even when the MRZ was read', () {
      expect(
        ScanIssueResolver.resolve(
          recognizedFields: 8,
          imageIssue: ScanIssue.documentNotInFrame,
        ),
        ScanIssue.documentNotInFrame,
      );
    });

    test('a readable page without an MRZ keeps the photo problem', () {
      expect(
        ScanIssueResolver.resolve(
          mrzMissing: true,
          recognizedFields: 6,
          imageIssue: ScanIssue.imageNotClear,
        ),
        ScanIssue.imageNotClear,
      );
    });

    test('a found MRZ with a dark photo reports the photo', () {
      expect(
        ScanIssueResolver.resolve(
          recognizedFields: 0,
          imageIssue: ScanIssue.imageNotClear,
        ),
        ScanIssue.imageNotClear,
      );
    });

    test('a wrong document is never replaced', () {
      expect(
        ScanIssueResolver.resolve(wrongDocument: true, recognizedFields: 0),
        ScanIssue.wrongDocument,
      );
    });

    test('an unread MRZ on a clear, framed photo is imageNotClear', () {
      expect(
        ScanIssueResolver.resolve(mrzMissing: true, recognizedFields: 6),
        ScanIssue.imageNotClear,
      );
    });

    test('nothing wrong gives null', () {
      expect(ScanIssueResolver.resolve(recognizedFields: 9), isNull);
    });
  });
}
