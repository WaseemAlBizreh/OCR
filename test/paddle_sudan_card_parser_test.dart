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
}
