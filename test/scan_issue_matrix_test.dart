import 'package:flutter_test/flutter_test.dart';
import 'package:idlens/src/api/scan_review.dart';
import 'package:idlens/src/api/scan_status.dart';
import 'package:idlens/src/domain/document_kind.dart';
import 'package:idlens/src/domain/image_quality.dart';
import 'package:idlens/src/domain/mrz_data.dart';
import 'package:idlens/src/domain/scan_issue.dart';

/// Every situation a scan can end in, from the photos to the final
/// `issue` / `issueSides` / `status`. It repeats the steps of the scan runner
/// (photo check -> resolve -> review) with the same functions, so a change in
/// any rule shows up here as a changed row.
void main() {
  // Photo measurements: [good] is clear and well framed.
  ImageQuality photo({
    double sharpness = 300,
    double brightness = 160,
    double glare = 0.02,
    double coverage = 0.8,
  }) => ImageQuality(
    sharpness: sharpness,
    brightness: brightness,
    glareShare: glare,
    documentCoverage: coverage,
  );

  final good = photo();
  final dark = photo(brightness: 40);
  final blurry = photo(sharpness: 10);
  final glary = photo(glare: 0.5);
  final far = photo(coverage: 0.2);

  MrzData mrz() => MrzData(
    format: MrzFormat.td1,
    lines: const [],
    documentCode: 'ID',
    issuingCountry: 'SDN',
    documentNumber: '008593666',
    dateOfBirth: '1992-09-23',
    sex: 'M',
    expiryDate: '2027-05-16',
    nationality: 'SDN',
    surname: 'A',
    givenNames: 'B',
    optionalData: '',
    checks: const {
      'documentNumber': true,
      'dateOfBirth': true,
      'expiryDate': true,
      'composite': true,
    },
  );

  const idRead = {'arabicName': 'محمد', 'nationalNumber': '11974221992'};
  const nothingRead = <String, dynamic>{};

  /// What the scan runner would report for one document.
  ({ScanIssue? issue, List<DocumentSide> sides, ScanStatus status}) scan({
    DocumentKind kind = DocumentKind.sudanId,
    ImageQuality? front,
    required ImageQuality page, // the page the MRZ is read from
    bool mrzFound = false,
    bool wrongDocument = false,
    bool cutOff = false,
    Map<String, dynamic> fields = idRead,
    bool frontHasContent = true,
  }) {
    final frontPhoto = kind == DocumentKind.sudanId ? front?.problem : null;
    final contentFields = frontHasContent ? fields : nothingRead;
    final frontIssue =
        frontPhoto ??
        (kind == DocumentKind.sudanId &&
                !ScanReview.hasRequiredContent(kind, contentFields)
            ? ScanIssue.contentNotFound
            : null);
    final resolved = ScanIssueResolver.resolve(
      wrongDocument: wrongDocument,
      contentMissing: kind.hasMrz
          ? !mrzFound
          : !ScanReview.hasRequiredContent(kind, fields),
      imageIssue: wrongDocument ? null : page.problem,
      cutOff: cutOff,
    );
    final mrzData = mrzFound ? mrz() : null;
    final readable = ScanReview.isReadable(
      kind: kind,
      fields: contentFields,
      mrz: mrzData,
    );
    final issue = ScanReview.worse(frontIssue, resolved);
    final status = ScanReview.statusFor(
      issue: issue,
      readable: readable,
      fieldsToCheck: const [],
    );
    // A failed scan always says why.
    if (status == ScanStatus.failed) expect(issue, isNotNull);
    return (
      issue: issue,
      sides: ScanReview.issueSides(
        issue,
        kind: kind,
        photos: {
          if (kind == DocumentKind.sudanId) DocumentSide.front: frontIssue,
          kind.sides.last: resolved,
        },
      ),
      status: ScanReview.statusFor(
        issue: issue,
        readable: readable,
        fieldsToCheck: const [],
      ),
    );
  }

  const front = DocumentSide.front;
  const back = DocumentSide.back;

  group('Sudan ID card', () {
    test('both sides good, MRZ read: verified, no issue', () {
      final r = scan(front: good, page: good, mrzFound: true);
      expect(r.issue, isNull);
      expect(r.sides, isEmpty);
      expect(r.status, ScanStatus.verified);
    });

    test(
      'front scanned twice (back clear, in frame, no MRZ): contentNotFound',
      () {
        // The reported case.
        final r = scan(front: good, page: good);
        expect(r.issue, ScanIssue.contentNotFound);
        expect(r.sides, [back]);
        expect(r.status, ScanStatus.failed);
      },
    );

    test('back has no MRZ and is dark: imageNotClear', () {
      final r = scan(front: good, page: dark);
      expect(r.issue, ScanIssue.imageNotClear);
      expect(r.sides, [back]);
      expect(r.status, ScanStatus.failed);
    });

    test('back has no MRZ and is blurry: imageNotClear', () {
      expect(scan(front: good, page: blurry).issue, ScanIssue.imageNotClear);
    });

    test('back has no MRZ and has glare: imageNotClear', () {
      expect(scan(front: good, page: glary).issue, ScanIssue.imageNotClear);
    });

    test('back has no MRZ and the card is far away: documentNotInFrame', () {
      final r = scan(front: good, page: far);
      expect(r.issue, ScanIssue.documentNotInFrame);
      expect(r.sides, [back]);
      expect(r.status, ScanStatus.failed);
    });

    test('back has no MRZ and the card is cut at an edge', () {
      final r = scan(front: good, page: good, cutOff: true);
      expect(r.issue, ScanIssue.documentNotInFrame);
      expect(r.status, ScanStatus.failed);
    });

    test('a passport shown for the ID card: wrongDocument, both sides', () {
      final r = scan(
        front: good,
        page: good,
        mrzFound: true,
        wrongDocument: true,
      );
      expect(r.issue, ScanIssue.wrongDocument);
      expect(r.sides, [front, back]);
      expect(r.status, ScanStatus.failed);
    });

    test('MRZ read but the front is dark: imageNotClear on the front, '
        'needsReview', () {
      final r = scan(front: dark, page: good, mrzFound: true);
      expect(r.issue, ScanIssue.imageNotClear);
      expect(r.sides, [front]);
      expect(r.status, ScanStatus.needsReview);
    });

    test('MRZ read but the front is far away: documentNotInFrame on the '
        'front, needsReview', () {
      final r = scan(front: far, page: good, mrzFound: true);
      expect(r.issue, ScanIssue.documentNotInFrame);
      expect(r.sides, [front]);
      expect(r.status, ScanStatus.needsReview);
    });

    test('back scanned twice (front holds no name or number, MRZ read): '
        'contentNotFound on the front', () {
      // The mirror of the front-twice case.
      final r = scan(
        front: good,
        page: good,
        mrzFound: true,
        frontHasContent: false,
      );
      expect(r.issue, ScanIssue.contentNotFound);
      expect(r.sides, [front]);
      expect(r.status, ScanStatus.failed);
    });

    test('back scanned twice but the front is dark: imageNotClear first', () {
      final r = scan(
        front: dark,
        page: good,
        mrzFound: true,
        frontHasContent: false,
      );
      expect(r.issue, ScanIssue.imageNotClear);
      expect(r.sides, [front]);
    });

    test('MRZ read, card slightly cut off: needsReview, not failed', () {
      final r = scan(front: good, page: good, mrzFound: true, cutOff: true);
      expect(r.issue, ScanIssue.documentNotInFrame);
      expect(r.status, ScanStatus.needsReview);
    });

    test('front dark and back has no MRZ: contentNotFound, retake both', () {
      final r = scan(front: dark, page: good);
      expect(r.issue, ScanIssue.contentNotFound);
      expect(r.sides, [front, back]);
    });

    test('front far and back has no MRZ: documentNotInFrame wins', () {
      final r = scan(front: far, page: good);
      expect(r.issue, ScanIssue.documentNotInFrame);
      expect(r.sides, [front, back]);
    });

    test('nothing at all read from the back: still the back to retake', () {
      final r = scan(front: good, page: good, fields: nothingRead);
      expect(r.issue, ScanIssue.contentNotFound);
      expect(r.sides, [front, back]);
      expect(r.status, ScanStatus.failed);
    });
  });

  group('Passport', () {
    const page = DocumentSide.dataPage;

    test('good page, MRZ read: verified', () {
      final r = scan(
        kind: DocumentKind.passport,
        page: good,
        mrzFound: true,
        fields: nothingRead,
      );
      expect(r.issue, isNull);
      expect(r.status, ScanStatus.verified);
    });

    test('clear, in frame, no MRZ: contentNotFound', () {
      final r = scan(kind: DocumentKind.passport, page: good);
      expect(r.issue, ScanIssue.contentNotFound);
      expect(r.sides, [page]);
      expect(r.status, ScanStatus.failed);
    });

    test('no MRZ and dark: imageNotClear', () {
      final r = scan(kind: DocumentKind.passport, page: dark);
      expect(r.issue, ScanIssue.imageNotClear);
      expect(r.sides, [page]);
    });

    test('no MRZ and far away: documentNotInFrame, failed', () {
      final r = scan(kind: DocumentKind.passport, page: far);
      expect(r.issue, ScanIssue.documentNotInFrame);
      expect(r.status, ScanStatus.failed);
    });

    test('an ID card MRZ shown for a passport: wrongDocument', () {
      final r = scan(
        kind: DocumentKind.passport,
        page: good,
        mrzFound: true,
        wrongDocument: true,
      );
      expect(r.issue, ScanIssue.wrongDocument);
      expect(r.sides, [page]);
    });
  });

  group('Civil registry certificate (has no MRZ)', () {
    const page = DocumentSide.page;
    const kind = DocumentKind.civilRegistryCertificate;
    const read = {
      'nationalNumber': '11974221992',
      'name': 'محمد',
      'dateOfBirth': '1992-09-23',
    };

    test('good page, fields read: verified, never contentNotFound', () {
      final r = scan(kind: kind, page: good, fields: read);
      expect(r.issue, isNull);
      expect(r.status, ScanStatus.verified);
    });

    test('good page but no required field read: contentNotFound, failed', () {
      final r = scan(kind: kind, page: good, fields: nothingRead);
      expect(r.issue, ScanIssue.contentNotFound);
      expect(r.sides, [page]);
      expect(r.status, ScanStatus.failed);
    });

    test('far away but fields read: documentNotInFrame, needsReview', () {
      final r = scan(kind: kind, page: far, fields: read);
      expect(r.issue, ScanIssue.documentNotInFrame);
      expect(r.status, ScanStatus.needsReview);
    });

    test('dark but fields read: imageNotClear, needsReview', () {
      final r = scan(kind: kind, page: dark, fields: read);
      expect(r.issue, ScanIssue.imageNotClear);
      expect(r.status, ScanStatus.needsReview);
    });
  });

  group('Failures that are not about the photo', () {
    for (final issue in [
      ScanIssue.processingFailed,
      ScanIssue.readerUnavailable,
      ScanIssue.timedOut,
    ]) {
      test('$issue: failed, no page to retake', () {
        expect(
          ScanReview.statusFor(
            issue: issue,
            readable: true,
            fieldsToCheck: const [],
          ),
          ScanStatus.failed,
        );
        expect(
          ScanReview.issueSides(issue, kind: DocumentKind.sudanId),
          isEmpty,
        );
      });
    }
  });

  group('Which issue wins when the two ID card sides disagree', () {
    // Most serious first.
    const order = [
      ScanIssue.wrongDocument,
      ScanIssue.readerUnavailable,
      ScanIssue.timedOut,
      ScanIssue.processingFailed,
      ScanIssue.documentNotInFrame,
      ScanIssue.contentNotFound,
      ScanIssue.imageNotClear,
    ];

    test(
      'every issue is ranked, and the earlier one wins either way round',
      () {
        expect(order.toSet(), ScanIssue.values.toSet());
        for (var i = 0; i < order.length; i++) {
          for (var j = i + 1; j < order.length; j++) {
            expect(ScanReview.worse(order[i], order[j]), order[i]);
            expect(ScanReview.worse(order[j], order[i]), order[i]);
          }
        }
      },
    );
  });

  group('The reported payload', () {
    // Back photo: sharpness 221, brightness 102.6, glare 0.0004, coverage 0.69,
    // no MRZ. The brightness is under the 110 limit, so the photo itself is
    // flagged and imageNotClear is correct for it.
    test('brightness 102.6 is flagged as not clear', () {
      final back = photo(sharpness: 221, brightness: 102.6, coverage: 0.69);
      expect(back.problem, ScanIssue.imageNotClear);
      expect(scan(front: good, page: back).issue, ScanIssue.imageNotClear);
    });

    test('the same photo at brightness 120 would be contentNotFound', () {
      final back = photo(sharpness: 221, brightness: 120, coverage: 0.69);
      expect(back.problem, isNull);
      expect(scan(front: good, page: back).issue, ScanIssue.contentNotFound);
    });
  });
}
