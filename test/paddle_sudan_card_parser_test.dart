import 'package:flutter_test/flutter_test.dart';
import 'package:mrz/features/identity_scan/data/ocr/paddle/paddle_sudan_card_parser.dart';

void main() {
  const parser = PaddleSudanCardParser();

  String? name(String text) => parser.parseFront(text).fields['arabicName'];

  test('the name label is dropped whatever letters of it OCR lost', () {
    for (final label in ['الاسم', 'لاسم', 'الإسم', 'الاسم:']) {
      expect(name('بطاقة اثبات الشخصية\n$label ميرغنى مكي ميرغنى عثمان\nتاريخ الميلاد'),
          'ميرغنى مكي ميرغنى عثمان',
          reason: label);
    }
  });

  test('real capture: لاسم glued before the name', () {
    expect(
      name('11974221992\nبطاقة اثبات الشخصية\nلاسم ميرغنى مكي ميرغنى عثمان\nتاريخ الميلاد\n'
          'مكان الميلادالخرطوم امدرمان'),
      'ميرغنى مكي ميرغنى عثمان',
    );
  });
}
