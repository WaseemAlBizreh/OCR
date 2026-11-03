import 'package:flutter_test/flutter_test.dart';
import 'package:idlens/src/data/mrz/mrz_parser.dart';
import 'package:idlens/src/domain/mrz_data.dart';

void main() {
  final parser = MrzParser(clock: () => DateTime(2026, 10, 28));

  const sudanTd1 = [
    'IDSDN0085936669<<<<<<<<<<<<<<<',
    '9209231M2705169SDN<<<<<<<<<<<4',
    'OSMAN<<MERGHANI<MEKKI<MERGHANI',
  ];

  test('parses the Sudan TD1 sample with all check digits passing', () {
    final mrz = parser.parseLines(sudanTd1, MrzFormat.td1)!;
    expect(mrz.checks, {
      'documentNumber': true,
      'dateOfBirth': true,
      'expiryDate': true,
      'composite': true,
    });
    expect(mrz.documentNumber, '008593666');
    expect(mrz.dateOfBirth, '1992-09-23');
    expect(mrz.expiryDate, '2027-05-16');
    expect(mrz.sex, 'M');
    expect(mrz.nationality, 'SDN');
    expect(mrz.issuingCountry, 'SDN');
    expect(mrz.surname, 'OSMAN');
    expect(mrz.givenNames, 'MERGHANI MEKKI MERGHANI');
  });

  test('repairs letter/digit confusions in OCR text', () {
    final mrz = parser.parseText(
      'some header\n'
      'IDSDNOO85936669<<<<<<<<<<<<<<<\n'
      '92O9231M27O5169SDN<<<<<<<<<<<4\n'
      'OSMAN<<MERGHANI<MEKKI<MERGHANI\n',
    )!;
    expect(mrz.isValid, isTrue);
    expect(mrz.documentNumber, '008593666');
    expect(mrz.dateOfBirth, '1992-09-23');
  });

  test('tolerates spaces and a short line', () {
    final mrz = parser.parseText(
      'IDSDN 008593666 9<<<<<<<<<<<<<<<\n'
      '9209231M2705169SDN<<<<<<<<<<4\n'
      'OSMAN<<MERGHANI<MEKKI<MERGHANI\n',
    );
    expect(mrz, isNotNull);
    expect(mrz!.documentNumber, '008593666');
    // A dropped filler is a misread, not a cut.
    expect(mrz.cutOff, isFalse);
  });

  group('MRZ cut off by the photo', () {
    test('a complete MRZ is not cut', () {
      expect(parser.parseLines(sudanTd1, MrzFormat.td1)!.cutOff, isFalse);
    });

    test('a card past the right edge: name and check digit lost', () {
      // Read on a device: the last character of every line is outside the
      // photo, so MERGHANI became MERGHAN with no check digit to catch it.
      final mrz = parser.parseText(
        'IDSDN0085936669<<<<<<<<<<<<<<\n'
        '9209231M2705169SDN<<<<<<<<<<<\n'
        'OSMAN<<MERGHANI<MEKKI<MERGHAN\n',
      )!;
      expect(mrz.cutOff, isTrue);
    });

    test('only the name line cut is enough', () {
      expect(
        MrzParser.isCut([
          sudanTd1[0],
          sudanTd1[1],
          'OSMAN<<MERGHANI<MEKKI<MERGHA',
        ], MrzFormat.td1),
        isTrue,
      );
    });

    test('a lost composite digit is a cut', () {
      expect(
        MrzParser.isCut([
          sudanTd1[0],
          '9209231M2705169SDN<<<<<<<<<<<',
          sudanTd1[2],
        ], MrzFormat.td1),
        isTrue,
      );
    });

    test('a card past the left edge loses the document code', () {
      expect(
        MrzParser.isCut([
          'SDN0085936669<<<<<<<<<<<<<<<',
          '09231M2705169SDN<<<<<<<<<<<4',
          'MAN<<MERGHANI<MEKKI<MERGHANI',
        ], MrzFormat.td1),
        isTrue,
      );
    });

    test('a short name line ending in filler is a dropped filler', () {
      expect(
        MrzParser.isCut([
          sudanTd1[0],
          sudanTd1[1],
          'OSMAN<<MERGHANI<MEKKI<<<<<<<',
        ], MrzFormat.td1),
        isFalse,
      );
    });

    test('a passport whose composite digit is lost is cut', () {
      expect(
        MrzParser.isCut([
          'P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<',
          'L898902C36UTO7408122F1204159ZE184226B<<<<<<',
        ], MrzFormat.td3),
        isTrue,
      );
    });

    test('a complete passport is not cut', () {
      expect(
        MrzParser.isCut([
          'P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<',
          'L898902C36UTO7408122F1204159ZE184226B<<<<<10',
        ], MrzFormat.td3),
        isFalse,
      );
    });
  });

  test('parses the ICAO TD3 specimen', () {
    final mrz = parser.parseText(
      'P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<\n'
      'L898902C36UTO7408122F1204159ZE184226B<<<<<10\n',
    )!;
    expect(mrz.format, MrzFormat.td3);
    expect(mrz.isValid, isTrue);
    expect(mrz.documentNumber, 'L898902C3');
    expect(mrz.dateOfBirth, '1974-08-12');
    expect(mrz.surname, 'ERIKSSON');
    expect(mrz.givenNames, 'ANNA MARIA');
  });

  test('returns null for text without an MRZ', () {
    expect(parser.parseText('الاسم: عثمان\nتاريخ الميلاد 1992/09/23'), isNull);
  });

  group('K misread as filler', () {
    const header =
        'IDSDN0085936669<<<<<<<<<<<<<<<\n9209231M2705169SDN<<<<<<<<<<<4\n';

    test('is removed from a trailing filler run, not left in the name', () {
      final mrz = parser.parseText('${header}SMITH<<MARK<<<K<K<<<<<<<<<<<<<')!;
      expect(mrz.givenNames, 'MARK');
      final khalid = parser.parseText(
        '${header}KARIM<<KHALID<K<<K<K<<<<<<<<<<',
      )!;
      expect(khalid.givenNames, 'KHALID');
    });

    test('is kept when it belongs to a name', () {
      final mrz = parser.parseText('${header}SMITH<<JOHN<K<DOE<<<<<<<<<<<<<')!;
      expect(mrz.givenNames, 'JOHN K DOE');
    });
  });
}
