import 'package:flutter_test/flutter_test.dart';
import 'package:mrz/features/identity_scan/data/front/sudan_card_parser.dart';

void main() {
  const parser = SudanCardParser();

  test('reads the 11-digit national number', () {
    final noisy = parser.parseFront('''
تاريخ الميلاد :1992/09/23 2 /
الرقم الوطني: 11974221992 \u200Eoy?\u200F 1
''');
    expect(noisy.fields['nationalNumber'], '11974221992');

    final unlabeled = parser.parseFront('جمهورية السودان\n11974221992\nID CARD');
    expect(unlabeled.fields['nationalNumber'], '11974221992');
  });

  group('back of the card dates', () {
    String? issue(String text) => parser.parseBack(text).fields['issueDate'];
    String? expiry(String text) => parser.parseBack(text).fields['expiryDate'];

    test('uses the two most recent dates whatever order OCR returns them in', () {
      const text = '008593666\n2022/05/17 x\n2027/05/16 y\n1992/09/23\n'
          'IDSDNO085936669<<<<<<<<<<<<<<<';
      expect(issue(text), '2022/05/17');
      expect(expiry(text), '2027/05/16');
    });

    test('fixes labels that contradict each other', () {
      const text = 'تاريخ الإصدار 2027/05/16\nتاريخ الإنتهاء 2022/05/17';
      expect(issue(text), '2022/05/17');
      expect(expiry(text), '2027/05/16');
    });

    test('trusts labels that agree, and ignores the date of birth', () {
      const text = 'تاريخ الإصدار: 2022/05/17\nتاريخ الإنتهاء: 2027/05/16\n23/09/1992';
      expect(issue(text), '2022/05/17');
      expect(expiry(text), '2027/05/16');
    });

    test('never reports the issue date as the expiry date', () {
      expect(expiry('تاريخ الإصدار: 2022/05/17'), isNull);
      expect(issue('مكان الإصدار: مجمع بحرى'), isNull);
    });

    test('reads dd/mm/yyyy', () {
      const text = 'issued 17/05/2022 expires 16/05/2027';
      expect(issue(text), '2022/05/17');
      expect(expiry(text), '2027/05/16');
    });
  });
}
