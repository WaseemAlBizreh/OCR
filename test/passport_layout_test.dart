import 'package:flutter_test/flutter_test.dart';
import 'package:mrz/features/identity_scan/data/ocr/paddle/passport/passport_labels.dart';
import 'package:mrz/features/identity_scan/data/ocr/paddle/passport/passport_layout.dart';
import 'package:mrz/features/identity_scan/data/ocr/paddle/passport/passport_line.dart';

PassportLine line(String text, double left, double top, {double width = 200, double height = 20}) =>
    PassportLine(text, left, top, left + width, top + height);

List<PassportLine> candidates(PassportLine label, List<PassportLine> all) {
  final labels = {
    for (final l in all)
      if (PassportLabels.hitsIn(l.text).isNotEmpty) l,
  };
  return PassportLayout.valueCandidates(label, all, labels);
}

void main() {
  group('PassportLabels', () {
    test('a longer label wins over a shorter one inside it', () {
      final hits = PassportLabels.hitsIn('Issuing Authority');
      expect(hits, hasLength(1));
      expect(hits.single.field, PassportField.issuePlace);
    });

    test('NAME does not match inside SURNAME or GIVEN NAMES', () {
      expect(PassportLabels.hitsIn('Surname').single.field, PassportField.other);
      expect(PassportLabels.hitsIn('Given names').single.field, PassportField.other);
      expect(PassportLabels.hitsIn('Full name').single.field, PassportField.arabicName);
    });

    test('tolerates OCR look-alikes and Arabic spelling variants', () {
      expect(PassportLabels.hitsIn('DATE 0F B1RTH').single.field, PassportField.birthDate);
      expect(PassportLabels.hitsIn('PLACE 0F BIRTH').single.field, PassportField.birthPlace);
      expect(PassportLabels.hitsIn('Dote of birth'), isEmpty); // a wrong letter is not a look-alike
      expect(PassportLabels.hitsIn('تاريخ الإصدار').single.field, PassportField.issueDate);
      expect(PassportLabels.hitsIn('تاريخ الاصدار').single.field, PassportField.issueDate);
    });

    test('two labels on one line are both found, left to right', () {
      final hits = PassportLabels.hitsIn('Date of birth  Sex');
      expect(hits.map((h) => h.field), [PassportField.birthDate, PassportField.other]);
    });
  });

  group('PassportLayout', () {
    test('value to the right of a Latin label', () {
      final label = line('Place of birth', 0, 100, width: 100);
      final value = line('KHARTOUM', 120, 100, width: 100);
      expect(candidates(label, [label, value]), [value]);
    });

    test('value to the left of an Arabic label (mirrored row)', () {
      final label = line('مكان الميلاد', 300, 100, width: 100);
      final value = line('الخرطوم', 150, 100, width: 100);
      expect(candidates(label, [label, value]), [value]);
    });

    test('value below the label in the same column', () {
      final label = line('Date of issue', 0, 100, width: 100);
      final value = line('2022/05/17', 5, 125, width: 90);
      expect(candidates(label, [label, value]), [value]);
    });

    test('column layout: each label gets the value under it', () {
      final birth = line('Place of birth', 0, 100, width: 100);
      final issue = line('Place of issue', 200, 100, width: 100);
      final birthValue = line('KHARTOUM', 0, 125, width: 100);
      final issueValue = line('PORT SUDAN', 200, 125, width: 100);
      final all = [birth, issue, birthValue, issueValue];
      expect(candidates(birth, all).first, birthValue);
      expect(candidates(issue, all).first, issueValue);
    });

    test('a label between the label and a value blocks that value', () {
      final a = line('Place of birth', 0, 100, width: 100);
      final b = line('Place of issue', 120, 100, width: 100);
      final value = line('PORT SUDAN', 240, 100, width: 100);
      expect(candidates(a, [a, b, value]), isEmpty);
      expect(candidates(b, [a, b, value]), [value]);
    });

    test('a value too far below is ignored', () {
      final label = line('Place of birth', 0, 100, width: 100);
      final far = line('UNRELATED', 0, 400, width: 100);
      expect(candidates(label, [label, far]), isEmpty);
    });

    test('a duplicate read of the label itself is not a value', () {
      final label = line('Place of birth', 0, 100, width: 100);
      final duplicate = line('Place of birth', 2, 101, width: 98);
      expect(candidates(label, [label, duplicate]), isEmpty);
    });
  });
}
