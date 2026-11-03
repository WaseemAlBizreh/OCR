import 'package:flutter_test/flutter_test.dart';
import 'package:idlens/src/data/mrz/mrz_parser.dart';
import 'package:idlens/src/domain/document_kind.dart';
import 'package:idlens/src/domain/mrz_validator.dart';

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

  test('a missing MRZ is not a wrong document', () {
    expect(validator.isWrongDocument(null, DocumentKind.passport), isFalse);
  });

  test('an expired document is still accepted', () {
    // The ICAO specimen expired in 2012.
    final mrz = parser.parseText(passportText);
    expect(validator.isWrongDocument(mrz, DocumentKind.passport), isFalse);
  });

  group('wrong document', () {
    final passport = parser.parseText(passportText);
    final idCard = parser.parseText(idText);

    test('a passport MRZ on an ID scan', () {
      expect(validator.isWrongDocument(passport, DocumentKind.sudanId), isTrue);
    });

    test('an ID MRZ on a passport scan', () {
      expect(validator.isWrongDocument(idCard, DocumentKind.passport), isTrue);
    });

    test('the matching document passes', () {
      expect(validator.isWrongDocument(idCard, DocumentKind.sudanId), isFalse);
    });
  });
}
