import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:idlens/src/data/ocr/paddle/paddle_sudan_card_parser.dart';

void main() {
  const parser = PaddleSudanCardParser();

  String? name(String text) => parser.parseFront(text).fields['arabicName'];

  test('the name label is dropped whatever letters of it OCR lost', () {
    for (final label in ['الاسم', 'لاسم', 'الإسم', 'الاسم:']) {
      expect(
        name(
          'بطاقة اثبات الشخصية\n$label ميرغنى مكي ميرغنى عثمان\nتاريخ الميلاد',
        ),
        'ميرغنى مكي ميرغنى عثمان',
        reason: label,
      );
    }
  });

  test('real capture: لاسم glued before the name', () {
    expect(
      name(
        '11974221992\nبطاقة اثبات الشخصية\nلاسم ميرغنى مكي ميرغنى عثمان\nتاريخ الميلاد\n'
        'مكان الميلادالخرطوم امدرمان',
      ),
      'ميرغنى مكي ميرغنى عثمان',
    );
  });

  group('warnings', () {
    const complete =
        '11974221992\nالاسم ميرغنى مكي ميرغنى عثمان\n'
        'العنوان الخرطوم ت/ ٠٩١٢٣٤٥٦٧٨';

    test('a complete front has no warnings', () {
      final front = parser.parseFront(complete);
      expect(front.fields['phone'], '0912345678');
      expect(front.warnings, isEmpty);
    });

    test('a missing required field is reported', () {
      final front = parser.parseFront('العنوان الخرطوم ت/ ٠٩١٢٣٤٥٦٧٨');
      expect(front.warnings, [
        'Missing field: arabicName',
        'Missing field: nationalNumber',
      ]);
    });

    test('an incomplete phone is dropped without a warning', () {
      final front = parser.parseFront(
        '11974221992\nالاسم ميرغنى مكي ميرغنى عثمان\n'
        'العنوان الخرطوم ت/ ٠٩١٢٣٤٥',
      );
      expect(front.fields['phone'], isNull);
      expect(front.warnings, isEmpty);
    });
  });

  group(
    'national number on a cut front (real device text)',
    skip: !Directory('test/fixtures/scans').existsSync()
        ? 'test/fixtures is local only (personal data)'
        : false,
    () {
      // The raw text is read from the fixture, which never ships to pub.dev.
      String rawFront(String name) {
        final json =
            jsonDecode(
                  File(
                    'test/fixtures/scans/idFront/cut/2026-11-10_$name.json',
                  ).readAsStringSync(),
                )
                as Map<String, dynamic>;
        return (json['diagnostics']['rawText'] as Map)['front'] as String;
      }

      for (final name in ['front-side-cut', 'front-top-cut']) {
        test('$name: the phone on the address row is not the number', () {
          final fields = parser.parseFront(rawFront(name)).fields;
          // Was the phone plus a stray digit.
          expect(fields['nationalNumber'], '11974221992');
          expect(fields['phone'], isNotNull);
        });
      }

      test('an 11-digit number shaped like a phone is never taken', () {
        final front = parser.parseFront(
          'الاسم ميرغنى مكي ميرغنى عثمان\nسوان ت٠٩١٢٣٤٥٦٧٨١',
        );
        expect(front.fields['nationalNumber'], isNull);
      });

      test('a number split by a space is joined', () {
        final front = parser.parseFront(
          'الاسم ميرغنى مكي ميرغنى عثمان\n1197422 1992 :yibl',
        );
        expect(front.fields['nationalNumber'], '11974221992');
      });

      test('the labelled line still wins', () {
        final front = parser.parseFront(
          '12345678901\nالرقم الوطني 11974221992\nالاسم ميرغنى مكي ميرغنى عثمان',
        );
        expect(front.fields['nationalNumber'], '11974221992');
      });
    },
  );
}
