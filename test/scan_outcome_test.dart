import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:idlens/src/api/civil_registry_result.dart';
import 'package:idlens/src/api/id_card_result.dart';
import 'package:idlens/src/api/passport_result.dart';
import 'package:idlens/src/api/scan_exception.dart';
import 'package:idlens/src/api/scan_outcome.dart';
import 'package:idlens/src/api/scan_status.dart';
import 'package:idlens/src/api/scanned_image.dart';
import 'package:idlens/src/domain/document_kind.dart';
import 'package:idlens/src/domain/scan_issue.dart';

void main() {
  group('statusFor', () {
    test('nothing wrong is verified', () {
      expect(
        ScanOutcome.statusFor(issues: [], warnings: []),
        ScanStatus.verified,
      );
    });

    test('a warning alone needs review', () {
      expect(
        ScanOutcome.statusFor(issues: [], warnings: ['date differs']),
        ScanStatus.needsReview,
      );
    });

    test('a soft issue needs review', () {
      for (final issue in [
        ScanIssue.imageNotClear,
        ScanIssue.mrzCheckDigitsFailed,
      ]) {
        expect(
          ScanOutcome.statusFor(issues: [issue], warnings: []),
          ScanStatus.needsReview,
          reason: issue.name,
        );
      }
    });

    test('an unreadable document fails', () {
      for (final issue in [
        ScanIssue.mrzNotFound,
        ScanIssue.wrongDocument,
        ScanIssue.documentNotInFrame,
        ScanIssue.processingFailed,
      ]) {
        expect(
          ScanOutcome.statusFor(issues: [issue], warnings: []),
          ScanStatus.failed,
          reason: issue.name,
        );
      }
    });

    test('a fatal issue wins over a soft one', () {
      expect(
        ScanOutcome.statusFor(
          issues: [ScanIssue.imageNotClear, ScanIssue.mrzNotFound],
          warnings: [],
        ),
        ScanStatus.failed,
      );
    });

    test('incomplete wins over everything', () {
      expect(
        ScanOutcome.statusFor(
          issues: [ScanIssue.mrzNotFound],
          warnings: ['x'],
          incomplete: true,
        ),
        ScanStatus.incomplete,
      );
    });
  });

  group('parseScanDate', () {
    test('reads dashes and slashes', () {
      expect(parseScanDate('1992-09-23'), DateTime(1992, 9, 23));
      expect(parseScanDate('1992/09/23'), DateTime(1992, 9, 23));
    });

    test('rejects missing, malformed and impossible dates', () {
      expect(parseScanDate(null), isNull);
      expect(parseScanDate(''), isNull);
      expect(parseScanDate('920923'), isNull);
      expect(parseScanDate('1992-02-31'), isNull);
      expect(parseScanDate('1992-13-01'), isNull);
      expect(parseScanDate(19920923), isNull);
    });
  });

  group('results', () {
    final scannedAt = DateTime(2026, 11, 1);

    test('ID card exposes typed fields and keeps unread ones null', () {
      final result = IdCardResult(
        status: ScanStatus.verified,
        scannedAt: scannedAt,
        fields: const {
          'nationalNumber': '12345678901',
          'dateOfBirth': '1992-09-23',
          'expiryDate': '2999-01-01',
          'profession': 'Engineer',
        },
      );
      expect(result.documentKind, DocumentKind.sudanId);
      expect(result.nationalNumber, '12345678901');
      expect(result.dateOfBirth, DateTime(1992, 9, 23));
      expect(result.profession, 'Engineer');
      expect(result.phone, isNull);
      expect(result.isExpired, isFalse);
      expect(result.isVerified, isTrue);
    });

    test(
      'isExpired is unknown without an expiry date and true in the past',
      () {
        expect(
          PassportResult(
            status: ScanStatus.failed,
            scannedAt: scannedAt,
          ).isExpired,
          isNull,
        );
        expect(
          PassportResult(
            status: ScanStatus.needsReview,
            scannedAt: scannedAt,
            fields: const {'expiryDate': '2001/01/01'},
          ).isExpired,
          isTrue,
        );
      },
    );

    test('civil registry reads its own fields and confidence', () {
      final result = CivilRegistryResult(
        status: ScanStatus.needsReview,
        scannedAt: scannedAt,
        fields: const {'name': 'x', 'dateOfBirth': '1990-01-02'},
        confidence: const {'name': 0.9},
      );
      expect(result.documentKind, DocumentKind.civilRegistryCertificate);
      expect(result.name, 'x');
      expect(result.dateOfBirth, DateTime(1990, 1, 2));
      expect(result.toJson()['confidence'], {'name': 0.9});
      expect(result.mrz, isNull);
    });

    test('a failed result still carries its images and serialises', () {
      final result = PassportResult(
        status: ScanStatus.failed,
        issues: const [ScanIssue.mrzNotFound],
        images: [
          ScannedImage(
            side: DocumentSide.dataPage,
            file: File('/tmp/page.jpg'),
          ),
        ],
        scannedAt: scannedAt,
      );
      final json = result.toJson();
      expect(json['status'], 'failed');
      expect(json['issues'], ['mrzNotFound']);
      expect(json['documentKind'], 'passport');
      expect(json['images'], [
        {'side': 'dataPage', 'path': '/tmp/page.jpg'},
      ]);
      expect(result.imageFor(DocumentSide.dataPage), isNotNull);
      expect(result.imageFor(DocumentSide.front), isNull);
    });
  });

  group('dispose', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('idlens_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    test(
      'deletes temporary images only, never the host app\'s files',
      () async {
        final temp = File('${dir.path}/temp.jpg')..writeAsStringSync('a');
        final owned = File('${dir.path}/owned.jpg')..writeAsStringSync('b');
        final result = IdCardResult(
          status: ScanStatus.incomplete,
          scannedAt: DateTime(2026, 11, 1),
          images: [
            ScannedImage(
              side: DocumentSide.front,
              file: temp,
              isTemporary: true,
            ),
            ScannedImage(side: DocumentSide.back, file: owned),
          ],
        );
        await result.dispose();
        expect(temp.existsSync(), isFalse);
        expect(owned.existsSync(), isTrue);
      },
    );

    test('bytes reads the file', () async {
      final file = File('${dir.path}/a.jpg')..writeAsBytesSync([1, 2, 3]);
      final image = ScannedImage(side: DocumentSide.front, file: file);
      expect(await image.bytes(), [1, 2, 3]);
    });
  });

  test('ScanException prints its reason', () {
    expect(
      const ScanException(ScanFailureReason.permissionDenied).toString(),
      'ScanException(permissionDenied)',
    );
    expect(
      const ScanException(ScanFailureReason.imageUnreadable, 'x').toString(),
      'ScanException(imageUnreadable: x)',
    );
  });
}
