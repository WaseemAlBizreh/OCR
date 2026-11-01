import 'package:flutter_test/flutter_test.dart';
import 'package:idlens/src/data/mrz/mrz_parser.dart';
import 'package:idlens/src/domain/document_kind.dart';
import 'package:idlens/src/domain/mrz_validator.dart';
import 'package:idlens/src/domain/scan_issue.dart';

void main() {
  final parser = MrzParser(clock: () => DateTime(2026, 10, 28));
  const validator = MrzValidator();

  const passportText =
      'P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<\n'
      'L898902C36UTO7408122F1204159ZE184226B<<<<<10\n';
  const idText =
      'IDSDN0085936669<<<<<<<<<<<<<<<\n'
      '9209231M2705169SDN<<<<<<<<<<<4\n'
      'OSMAN<<MERGHANI<MEKKI<MERGHANI\n';

  test('no MRZ gives the mrzNotFound code', () {
    expect(
      validator.validate(null, DocumentKind.passport),
      ScanIssue.mrzNotFound,
    );
  });

  test('an expired document is still accepted', () {
    // The ICAO specimen expired in 2012.
    final mrz = parser.parseText(passportText);
    expect(validator.validate(mrz, DocumentKind.passport), isNull);
  });

  group('wrong document', () {
    final passport = parser.parseText(passportText);
    final idCard = parser.parseText(idText);

    test('a passport MRZ on an ID scan', () {
      expect(
        validator.validate(passport, DocumentKind.sudanId),
        ScanIssue.wrongDocument,
      );
    });

    test('an ID MRZ on a passport scan', () {
      expect(
        validator.validate(idCard, DocumentKind.passport),
        ScanIssue.wrongDocument,
      );
    });

    test('the matching document passes', () {
      expect(validator.validate(idCard, DocumentKind.sudanId), isNull);
    });
  });
}
