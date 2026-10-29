import 'package:flutter_test/flutter_test.dart';
import 'package:mrz/features/identity_scan/data/ocr/paddle/civil_registry/certificate_labels.dart';
import 'package:mrz/features/identity_scan/data/ocr/paddle/civil_registry/civil_registry_parser.dart';
import 'package:mrz/features/identity_scan/data/ocr/paddle/passport/passport_line.dart';

/// A line placed as Paddle would: Arabic labels sit on the right of the row,
/// their values to the left.
PassportLine at(String text, double x, double y, [double width = 200, List<String> alts = const []]) =>
    PassportLine(text, x, y, x + width, y + 20, alts: alts);

PassportLine label(String text, double y, [List<String> alts = const []]) =>
    at(text, 500, y, 160, alts);

PassportLine value(String text, double y) => at(text, 100, y, 340);

void main() {
  const parser = CivilRegistryParser();

  List<PassportLine> fullPage() => [
        at('جمهورية السودان', 250, 0, 300),
        at('شهادة قيد مدني', 250, 30, 300),
        label('مكتب التسجيل', 80), value('الخرطوم', 80),
        label('تاريخ استخراج الشهادة', 120), value('2026/10/05', 120),
        label('الرقم الوطني', 160), value('12345678901', 160),
        label('الاسم', 200), value('محمد احمد عثمان علي', 200),
        label('مكان الميلاد', 240), value('امدرمان', 240),
        label('تاريخ الميلاد', 280), value('1990/03/15', 280),
        label('الحالة الاجتماعية', 320), value('متزوج', 320),
        label('الجنس', 360), value('ذكر', 360),
        label('نوع الجنسية', 400), value('بالميلاد', 400),
        label('المهنة', 440), value('مهندس', 440),
        label('عنوان العمل', 480), value('الخرطوم بحري', 480),
        label('اسم الوالدة', 520), value('فاطمة محمد حسن', 520),
      ];

  test('reads all twelve fields from a label: value page', () {
    final page = parser.parse(fullPage());
    expect(page.fields, {
      'registryOffice': 'الخرطوم',
      'issueDate': '2026-10-05',
      'nationalNumber': '12345678901',
      'name': 'محمد احمد عثمان علي',
      'placeOfBirth': 'امدرمان',
      'dateOfBirth': '1990-03-15',
      'maritalStatus': 'متزوج',
      'gender': 'M',
      'nationalityType': 'بالميلاد',
      'profession': 'مهندس',
      'workAddress': 'الخرطوم بحري',
      'motherName': 'فاطمة محمد حسن',
    });
    expect(page.warnings, isEmpty);
  });

  test('Arabic-Indic digits are converted', () {
    final lines = fullPage()
      ..removeWhere((l) => l.text == '12345678901' || l.text == '1990/03/15')
      ..addAll([value('١٢٣٤٥٦٧٨٩٠١', 160), value('١٩٩٠/٠٣/١٥', 280)]);
    final page = parser.parse(lines);
    expect(page.fields['nationalNumber'], '12345678901');
    expect(page.fields['dateOfBirth'], '1990-03-15');
  });

  test('a garbled label is repaired: الرقم الوطي', () {
    final lines = fullPage()..removeWhere((l) => l.text == 'الرقم الوطني');
    lines.add(label('الرقم الوطي', 160));
    expect(parser.parse(lines).fields['nationalNumber'], '12345678901');
  });

  test('lost dots in several labels', () {
    final lines = [
      label('تاريخ المبلاد', 80), value('1990/03/15', 80),
      label('مكان المبلاد', 120), value('امدرمان', 120),
      label('الحالة الاجتماعبة', 160), value('مترزج', 160),
    ];
    final page = parser.parse(lines);
    expect(page.fields['dateOfBirth'], '1990-03-15');
    expect(page.fields['placeOfBirth'], 'امدرمان');
    expect(page.fields['maritalStatus'], 'متزوج');
  });

  test("the other engine's reading rescues a garbled label", () {
    final lines = [
      label('رقم وط', 160, const ['الرقم الوطني']), value('12345678901', 160),
    ];
    expect(parser.parse(lines).fields['nationalNumber'], '12345678901');
  });

  test('the value may sit in the row below its label', () {
    final lines = [
      at('الاسم', 400, 100, 160),
      at('محمد احمد عثمان علي', 150, 135, 410),
    ];
    expect(parser.parse(lines).fields['name'], 'محمد احمد عثمان علي');
  });

  test('the value may follow the label on the same line', () {
    final lines = [at('الجنس: ذكر', 300, 100, 260), at('المهنة : طبيب', 300, 140, 260)];
    final page = parser.parse(lines);
    expect(page.fields['gender'], 'M');
    expect(page.fields['profession'], 'طبيب');
  });

  test('a missing field stays null and is reported', () {
    final lines = fullPage()..removeWhere((l) => l.text == 'مهندس' || l.text == 'المهنة');
    final page = parser.parse(lines);
    expect(page.fields['profession'], isNull);
    expect(page.fields['name'], isNotNull);
    expect(page.warnings, contains('Missing field: profession'));
  });

  test('a national number is found even without its label', () {
    final lines = fullPage()..removeWhere((l) => l.text == 'الرقم الوطني');
    expect(parser.parse(lines).fields['nationalNumber'], '12345678901');
  });

  test('a date of birth after the issue date is dropped with a warning', () {
    final lines = fullPage()
      ..removeWhere((l) => l.text == '1990/03/15')
      ..add(value('2027/01/01', 280));
    final page = parser.parse(lines);
    expect(page.fields['dateOfBirth'], isNull);
    expect(page.fields['issueDate'], '2026-10-05');
    expect(page.warnings.any((w) => w.startsWith('Date of birth')), isTrue);
  });

  test('a heading is never taken as a value', () {
    final lines = [
      at('شهادة قيد مدني', 250, 0, 300),
      label('الاسم', 80),
    ];
    expect(parser.parse(lines).fields['name'], isNull);
  });

  group('real scan: values missing or wrong', () {
    test('غير متزوج is not read as متزوج', () {
      expect(CivilRegistryParser.marital('غير متزوج'), 'غير متزوج');
      expect(CivilRegistryParser.marital('غير متزوجة'), 'غير متزوجة');
      expect(CivilRegistryParser.marital('متزوج'), 'متزوج');
      expect(CivilRegistryParser.marital('الخرطوم'), isNull);
    });

    test('الجنسذكر (label glued to value) gives gender M', () {
      expect(parser.parse([at('الجنسذكر', 300, 100, 260)]).fields['gender'], 'M');
      expect(parser.parse([at('الجنسأنثى', 300, 100, 260)]).fields['gender'], 'F');
      expect(parser.parse([at('الجنسنذكر', 300, 100, 260)]).fields['gender'], 'M');
    });

    test('نكر is read as ذكر', () {
      final page = parser.parse([label('الجنس', 100), value('نكر', 100)]);
      expect(page.fields['gender'], 'M');
    });

    test('digits ML Kit read inside the label box are the value', () {
      // Paddle boxed label and value together and kept only the Arabic;
      // ML Kit's digits-only line sits inside that box.
      final lines = [
        at('الرقم الوطنى', 100, 100, 560),
        at('12345678901', 120, 102, 200),
        at('تاريخ استخراج الشهادة', 100, 140, 560),
        at('2026/10/05', 120, 142, 150),
        at('تاريخالميلاد', 100, 180, 560),
        at('15/03/1990', 120, 182, 150),
      ];
      final page = parser.parse(lines);
      expect(page.fields['nationalNumber'], '12345678901');
      expect(page.fields['issueDate'], '2026-10-05');
      expect(page.fields['dateOfBirth'], '1990-03-15');
    });

    test('dates whose labels were lost are told apart by order', () {
      final page = parser.parse([at('2026/10/05', 100, 100, 150), at('1990/03/15', 100, 140, 150)]);
      expect(page.fields['dateOfBirth'], '1990-03-15');
      expect(page.fields['issueDate'], '2026-10-05');
    });

    test('the label line is found even glued to a stray digit: الرقمالوطنى4', () {
      final glued = at('الرقمالوطنى4', 100, 100, 560);
      final found =
          parser.labelLine(CertificateField.nationalNumber, [glued, at('الاسم', 100, 140)]);
      expect(found?.text, glued.text);
      expect(found?.left, glued.left);
      expect(found?.top, glued.top);
      expect(parser.labelLine(CertificateField.profession, [glued]), isNull);
    });

    test('an empty work address stays empty next to the officer heading', () {
      final page = parser.parse([
        label('عنوان العمل', 100),
        label('الضابط المسئول', 140),
        label('الرتبه', 180),
      ]);
      expect(page.fields['workAddress'], isNull);
    });
  });

  group('value helpers', () {
    test('gender', () {
      expect(CivilRegistryParser.gender('ذكر'), 'M');
      expect(CivilRegistryParser.gender('أنثى'), 'F');
      expect(CivilRegistryParser.gender('انثي'), 'F');
      expect(CivilRegistryParser.gender('الخرطوم'), isNull);
    });

    test('snap to a closed vocabulary', () {
      expect(CivilRegistryParser.snap('اعزب', CivilRegistryParser.maritalValues), 'أعزب');
      expect(CivilRegistryParser.snap('مطلقه', CivilRegistryParser.maritalValues), 'مطلقة');
      expect(CivilRegistryParser.snap('بالتجنس', CivilRegistryParser.nationalityTypeValues), 'بالتجنس');
      expect(CivilRegistryParser.snap('الخرطوم', CivilRegistryParser.maritalValues), isNull);
    });

    test('national number', () {
      expect(CivilRegistryParser.nationalNumber('1234 5678 901'), '12345678901');
      expect(CivilRegistryParser.nationalNumber('2026/10/05'), isNull);
      expect(CivilRegistryParser.nationalNumber('123'), isNull);
    });
  });
}
