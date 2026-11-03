import 'package:flutter_test/flutter_test.dart';
import 'package:idlens/src/api/scan_review.dart';
import 'package:idlens/src/api/scan_status.dart';
import 'package:idlens/src/domain/document_kind.dart';
import 'package:idlens/src/domain/mrz_data.dart';
import 'package:idlens/src/domain/scan_issue.dart';

void main() {
  MrzData mrz({Map<String, bool>? checks}) => MrzData(
    format: MrzFormat.td3,
    lines: const [],
    documentCode: 'P',
    issuingCountry: 'SDN',
    documentNumber: 'P01234567',
    dateOfBirth: '1990-01-02',
    sex: 'M',
    expiryDate: '2030-01-02',
    nationality: 'SDN',
    surname: 'A',
    givenNames: 'B',
    optionalData: '',
    checks:
        checks ??
        const {
          'documentNumber': true,
          'dateOfBirth': true,
          'expiryDate': true,
          'personalNumber': true,
          'composite': true,
        },
  );

  const idFields = {
    'documentNumber': 'P01234567',
    'nationalNumber': '12345678901',
    'arabicName': 'محمد',
    'dateOfBirth': '1990-01-02',
    'issueDate': '2020-01-02',
    'expiryDate': '2030-01-02',
    'phone': null,
  };

  group('fieldsToCheck', () {
    test('nothing to check on a clean ID card', () {
      expect(
        ScanReview.fieldsToCheck(
          kind: DocumentKind.sudanId,
          fields: idFields,
          mrz: mrz(),
        ),
        isEmpty,
      );
    });

    test(
      'a missing required field is listed, a missing optional one is not',
      () {
        expect(
          ScanReview.fieldsToCheck(
            kind: DocumentKind.sudanId,
            fields: {...idFields, 'arabicName': null, 'placeOfIssue': null},
            mrz: mrz(),
          ),
          ['arabicName'],
        );
      },
    );

    test('a passport has no required fields', () {
      expect(
        ScanReview.fieldsToCheck(
          kind: DocumentKind.passport,
          fields: const {'arabicName': null, 'placeOfBirth': null},
          mrz: mrz(),
        ),
        isEmpty,
      );
    });

    test('doubtful fields are listed in field order', () {
      expect(
        ScanReview.fieldsToCheck(
          kind: DocumentKind.sudanId,
          fields: idFields,
          doubtful: const ['expiryDate', 'dateOfBirth'],
          mrz: mrz(),
        ),
        ['dateOfBirth', 'expiryDate'],
      );
    });

    test('a failed check digit lists the fields it covers', () {
      final failed = mrz(
        checks: const {
          'documentNumber': true,
          'dateOfBirth': false,
          'expiryDate': true,
          'personalNumber': false,
          'composite': true,
        },
      );
      expect(
        ScanReview.fieldsToCheck(
          kind: DocumentKind.passport,
          fields: idFields,
          mrz: failed,
        ),
        ['nationalNumber', 'dateOfBirth'],
      );
    });

    test('a failed composite digit lists every field it covers', () {
      final failed = mrz(
        checks: const {
          'documentNumber': true,
          'dateOfBirth': true,
          'expiryDate': true,
          'composite': false,
        },
      );
      expect(
        ScanReview.fieldsToCheck(
          kind: DocumentKind.sudanId,
          fields: idFields,
          mrz: failed,
        ),
        ['documentNumber', 'dateOfBirth', 'expiryDate'],
      );
    });

    test('a date that is not a real date is listed', () {
      expect(
        ScanReview.fieldsToCheck(
          kind: DocumentKind.sudanId,
          fields: {...idFields, 'issueDate': '2020-02-31'},
          mrz: mrz(),
        ),
        ['issueDate'],
      );
    });

    test('a certificate lists its three required fields', () {
      expect(
        ScanReview.fieldsToCheck(
          kind: DocumentKind.civilRegistryCertificate,
          fields: const {
            'nationalNumber': null,
            'name': null,
            'dateOfBirth': null,
            'motherName': null,
          },
        ),
        ['nationalNumber', 'name', 'dateOfBirth'],
      );
    });
  });

  group('isReadable', () {
    test('an ID card or passport needs its MRZ', () {
      expect(
        ScanReview.isReadable(kind: DocumentKind.passport, fields: idFields),
        isFalse,
      );
      expect(
        ScanReview.isReadable(
          kind: DocumentKind.passport,
          fields: const {},
          mrz: mrz(),
        ),
        isTrue,
      );
    });

    test('a certificate needs one of its required fields', () {
      const kind = DocumentKind.civilRegistryCertificate;
      expect(
        ScanReview.isReadable(kind: kind, fields: const {'motherName': 'x'}),
        isFalse,
      );
      expect(
        ScanReview.isReadable(kind: kind, fields: const {'name': 'x'}),
        isTrue,
      );
    });
  });

  group('issueFor', () {
    test('an unreadable document always gets an issue', () {
      expect(
        ScanReview.issueFor(null, readable: false),
        ScanIssue.imageNotClear,
      );
      expect(
        ScanReview.issueFor(ScanIssue.documentNotInFrame, readable: false),
        ScanIssue.documentNotInFrame,
      );
      expect(ScanReview.issueFor(null, readable: true), isNull);
    });

    test('the more serious photo issue wins', () {
      expect(
        ScanReview.worse(ScanIssue.imageNotClear, ScanIssue.documentNotInFrame),
        ScanIssue.documentNotInFrame,
      );
      expect(
        ScanReview.worse(ScanIssue.documentNotInFrame, ScanIssue.wrongDocument),
        ScanIssue.wrongDocument,
      );
      expect(
        ScanReview.worse(ScanIssue.imageNotClear, null),
        ScanIssue.imageNotClear,
      );
    });
  });

  group('statusFor', () {
    ScanStatus status(
      ScanIssue? issue, {
      bool readable = true,
      List<String> fieldsToCheck = const [],
    }) => ScanReview.statusFor(
      issue: issue,
      readable: readable,
      fieldsToCheck: fieldsToCheck,
    );

    test('nothing wrong is verified', () {
      expect(status(null), ScanStatus.verified);
    });

    test('a field to check needs review', () {
      expect(status(null, fieldsToCheck: ['name']), ScanStatus.needsReview);
    });

    test('an unclear photo needs review', () {
      expect(status(ScanIssue.imageNotClear), ScanStatus.needsReview);
    });

    test('every other issue fails', () {
      for (final issue in [
        ScanIssue.wrongDocument,
        ScanIssue.documentNotInFrame,
        ScanIssue.processingFailed,
        ScanIssue.readerUnavailable,
      ]) {
        expect(status(issue), ScanStatus.failed, reason: issue.name);
      }
    });

    test('an unreadable document fails even with an unclear photo', () {
      expect(
        status(ScanIssue.imageNotClear, readable: false),
        ScanStatus.failed,
      );
    });
  });
}
