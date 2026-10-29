import 'package:flutter_test/flutter_test.dart';
import 'package:mrz/features/identity_scan/data/mrz/mrz_parser.dart';
import 'package:mrz/features/identity_scan/data/ocr/paddle/passport/paddle_passport_parser.dart';
import 'package:mrz/features/identity_scan/data/ocr/paddle/passport/passport_line.dart';
import 'package:mrz/features/identity_scan/domain/mrz_data.dart';

PassportLine at(String text, double x, double y, [double width = 140, List<String> alts = const []]) =>
    PassportLine(text, x, y, x + width, y + 20, alts: alts);

String cd(String v) => MrzParser.checkDigit(v).toString();

/// A valid TD3 MRZ for [country], built with real check digits.
({MrzData mrz, List<PassportLine> lines}) buildMrz(String country, {String personal = ''}) {
  const doc = 'P05000040', dob = '920923', exp = '270516';
  final personalField = personal.padRight(14, '<');
  final line1 = 'P<${country}OSMAN<<MERGHANI<MEKKI'.padRight(44, '<');
  final composite =
      cd('$doc${cd(doc)}$dob${cd(dob)}$exp${cd(exp)}$personalField${cd(personalField)}');
  final line2 = '$doc${cd(doc)}$country$dob${cd(dob)}M$exp${cd(exp)}'
      '$personalField${cd(personalField)}$composite';
  final mrz = MrzParser(clock: () => DateTime(2026, 10, 28))
      .parseLines([line1, line2], MrzFormat.td3)!;
  return (
    mrz: mrz,
    lines: [at(line1, 0, 600, 600), at(line2, 0, 630, 600)],
  );
}

void main() {
  const parser = PaddlePassportParser();
  final sudan = buildMrz('SDN', personal: '11974221992');

  test('the sample MRZ is valid', () {
    expect(sudan.mrz.isValid, isTrue);
  });

  test('bilingual rows: English label, Latin value, Arabic value, Arabic label', () {
    final lines = [
      at('Passport No', 0, 20), at('P05000040', 160, 20),
      at('Full Name', 0, 60), at('MERGHANI MEKKI OSMAN', 160, 60, 150),
      at('ميرغني مكي ميرغني عثمان', 330, 60, 150), at('الاسم الكامل', 500, 60),
      at('National No', 0, 100), at('119-7422-1992', 160, 100),
      at('Nationality', 0, 140), at('SUDANESE', 160, 140),
      at('Date of Birth', 0, 180), at('23-09-1992', 160, 180),
      at('Place of Birth', 0, 220), at('OMDURMAN', 160, 220), at('امدرمان', 330, 220),
      at('مكان الميلاد', 500, 220),
      at('Date of Issue', 0, 260), at('17-05-2022', 160, 260),
      at('Place of Issue', 0, 300), at('KHARTOUM', 160, 300), at('الخرطوم', 330, 300),
      at('مكان الإصدار', 500, 300),
      at('Date of Expiry', 0, 340), at('16-05-2027', 160, 340),
      ...sudan.lines,
    ];
    final fields = parser.parse(lines, mrz: sudan.mrz).fields;

    expect(fields['passportNumber'], 'P05000040');
    expect(fields['arabicName'], 'ميرغني مكي ميرغني عثمان');
    expect(fields['nationalNumber'], '11974221992');
    expect(fields['nationalityText'], 'SUDANESE');
    expect(fields['dateOfBirth'], '1992/09/23');
    expect(fields['placeOfBirth'], 'OMDURMAN');
    expect(fields['placeOfBirthArabic'], 'امدرمان');
    expect(fields['issueDate'], '2022/05/17');
    expect(fields['placeOfIssue'], 'KHARTOUM');
    expect(fields['placeOfIssueArabic'], 'الخرطوم');
    expect(fields['expiryDate'], '2027/05/16');
  });

  test('column layout: values sit below their labels', () {
    final lines = [
      at('Place of Birth', 0, 100), at('Place of Issue', 200, 100), at('Date of Issue', 400, 100),
      at('Omdurman', 0, 125), at('Khartoum', 200, 125), at('17 MAY 2022', 400, 125),
      ...sudan.lines,
    ];
    final fields = parser.parse(lines, mrz: sudan.mrz).fields;
    expect(fields['placeOfBirth'], 'OMDURMAN');
    expect(fields['placeOfIssue'], 'KHARTOUM');
    expect(fields['issueDate'], '2022/05/17');
  });

  test('English-only passport from another country', () {
    final gbr = buildMrz('GBR');
    final lines = [
      at('Nationality', 0, 20), at('BRITISH CITIZEN', 160, 20),
      at('Date of birth', 0, 60), at('23 SEP 92', 160, 60),
      at('Place of birth', 0, 100), at('LONDON', 160, 100),
      at('Date of issue', 0, 140), at('17 MAY 2022', 160, 140),
      at('Authority', 0, 180), at('HMPO', 160, 180),
      at('Date of expiry', 0, 220), at('16 MAY 2027', 160, 220),
      ...gbr.lines,
    ];
    final fields = parser.parse(lines, mrz: gbr.mrz).fields;
    expect(fields['nationalityText'], 'BRITISH CITIZEN');
    expect(fields['placeOfBirth'], 'LONDON');
    expect(fields['placeOfBirthArabic'], isNull);
    expect(fields['placeOfIssue'], 'HMPO');
    expect(fields['issueDate'], '2022/05/17');
    expect(fields['arabicName'], isNull);
  });

  test('finds the issue date by elimination when its label is garbled', () {
    final lines = [
      at('Date of Birth', 0, 20), at('23-09-1992', 160, 20),
      at('Dote of lssve', 0, 60), at('17-05-2022', 160, 60),
      at('Date of Expiry', 0, 100), at('16-05-2027', 160, 100),
      ...sudan.lines,
    ];
    expect(parser.parse(lines, mrz: sudan.mrz).fields['issueDate'], '2022/05/17');
  });

  test('prefers the date that fits a whole-year validity among noise dates', () {
    final lines = [
      at('23-09-1992', 0, 20), at('01-01-2015', 0, 60),
      at('17-05-2017', 0, 100), at('16-05-2027', 0, 140),
    ];
    expect(parser.parse(lines, mrz: sudan.mrz).fields['issueDate'], '2017/05/17');
  });

  test('without an MRZ, three dates are birth, issue, expiry in order', () {
    final fields = parser.parse([
      at('23-09-1992', 0, 20), at('17-05-2022', 0, 60), at('16-05-2027', 0, 100),
    ]).fields;
    expect(fields['dateOfBirth'], '1992/09/23');
    expect(fields['issueDate'], '2022/05/17');
    expect(fields['expiryDate'], '2027/05/16');
  });

  test('a page with nothing readable gives null fields and soft warnings, not a crash', () {
    final result = parser.parse(sudan.lines, mrz: sudan.mrz);
    expect(result.fields.values.every((v) => v == null), isTrue);
    expect(result.warnings, contains('Missing field: placeOfBirth'));
    expect(parser.parse(const []).fields['issueDate'], isNull);
  });

  test('MRZ lines mixed into the page text are never read as values', () {
    final lines = [
      at('Place of Birth', 0, 20),
      ...sudan.lines.map((l) => PassportLine(l.text, 160, 20, 600, 40)), // same row, right side
    ];
    expect(parser.parse(lines, mrz: sudan.mrz).fields['placeOfBirth'], isNull);
  });

  group('real capture: new Sudanese passport (labels row, values row below)', () {
    // Paddle's garbled bilingual titles carry ML Kit's English reading as an
    // alternative; the layout is right to left (first column on the right).
    final sdn = buildMrz('SDN');
    List<PassportLine> page() => [
          at('جمهورية السودان', 380, 0, 180), at('THE REPUBLIC OF THE SUDAN', 100, 0, 250),
          at('Passpon petal', 300, 40), at('جواز سفر', 400, 40),
          at('P09128281', 420, 70, 120), at('SDN', 260, 70), at('PC', 100, 70),
          at('الاسم الكامل', 400, 110),
          at('ايمن احمد عباس ابراهيم', 300, 140, 260),
          at('AYMAN AHMED ABBAS IBRAHIM', 300, 170, 260),
          at('الرقم الوطي N', 400, 210, 160, ['NatonalNo']),
          at('الجنمية ityىtiorوN', 200, 210, 160),
          at('241-7644-9282', 400, 240), at('السودانSDN', 200, 240),
          at('ناريح اB Da', 400, 290, 160, ['Date of Brthi']),
          at('كان الا', 200, 290, 160, ['Pace o Bthia']),
          at('24-12-2001', 400, 320), at('السعوديةK.S.A', 200, 320),
          at('فار ا D', 400, 370, 160, ['Dahe cf issue']),
          at('الجنس اxعS', 200, 370, 160),
          at('10-03-2022', 400, 400), at('دكرM', 200, 400),
          at('اتهاالة D', 400, 450, 160, ['Date of Expry']),
          at('اان الاصار ا', 200, 450, 160),
          at('09-03-2032', 400, 480), at('امدرمان', 200, 480),
          at('حوقيع امل ال', 300, 530),
          ...sdn.lines,
        ];

    test('reads every printed field the page carries', () {
      final fields = parser.parse(page(), mrz: sdn.mrz).fields;
      expect(fields['arabicName'], 'ايمن احمد عباس ابراهيم');
      expect(fields['englishName'], 'AYMAN AHMED ABBAS IBRAHIM');
      expect(fields['nationalNumber'], '24176449282');
      expect(fields['nationalityText'], 'Sudan'); // the page prints the code SDN
      expect(fields['nationalityTextArabic'], 'السودان');
      expect(fields['dateOfBirth'], '2001/12/24');
      expect(fields['placeOfBirth'], 'K.S.A');
      expect(fields['placeOfBirthArabic'], 'السعودية');
      expect(fields['issueDate'], '2022/03/10');
      expect(fields['placeOfIssueArabic'], 'امدرمان');
      expect(fields['expiryDate'], '2032/03/09');
    });

    test('headings and values are not mistaken for titles', () {
      final result = parser.parse(page(), mrz: sdn.mrz);
      expect(result.fields['placeOfBirth'], isNot(contains('REPUBLIC')));
      expect(result.fields['arabicName'], isNot(contains('السودان')));
    });
  });

  group('real capture 2: same passport design, other holder', () {
    // Names, dates and garbled titles copied from a second device capture.
    // The place value is cut by Paddle (OMDURMA) and glued with a stray I by
    // ML Kit (OMDURMANI).
    final holder = buildMrz('SDN');
    List<PassportLine> page() => [
          at('جمهورية السودان', 380, 0, 180), at('THE REPUBLIC OF THE SUDAN', 100, 0, 250),
          at('نوع الجواز', 400, 40), at('جواز سفر', 300, 40),
          at('P11133268', 420, 70, 120), at('SDN', 260, 70), at('PC', 100, 70),
          at('الاسم الكامل', 400, 110),
          at('ميرغنى مكى ميرغنى عثمان', 300, 140, 260),
          at('MERGHANI MEKKI MERGHANI OSMAN', 300, 170, 260),
          at('الرئم الوطي', 400, 210, 160, ['National No']),
          at('الجنة Nationaty', 200, 210, 160, ['Nalonaly']),
          at('119-7422-1992', 400, 240), at('السودان/SDN', 200, 240),
          at('ناريع الملا Df', 400, 290, 160, ['Date of Brthal']),
          at('مكتان الملاد', 200, 290, 160, ['Pace of Brth/e']),
          at('23-09-1992', 400, 320),
          at('امدرمان/OMDURMA', 200, 320, 160, ['OMDURMANI ole yaal']),
          at('ناريخ الادار', 400, 370, 160, ['Date of lnue gl']),
          at('الجنسx', 200, 370, 160, ['Sex fyal']),
          at('13-10-2023', 400, 400), at('دكرM', 200, 400),
          at('اها اللاة', 400, 450, 160, ['Date of Expiry/ ll']),
          at('مكان ااار', 200, 450, 160, ['Place of ssue/ gla']),
          at('12-10-2033', 400, 480),
          at('سنار /SENNAR', 200, 480, 160, ['SENNAR']),
          at('نوفيع املالار', 300, 530),
          ...holder.lines,
        ];

    test('reads every printed field the page carries', () {
      final fields = parser.parse(page(), mrz: holder.mrz).fields;
      expect(fields['arabicName'], 'ميرغنى مكى ميرغنى عثمان');
      expect(fields['englishName'], 'MERGHANI MEKKI MERGHANI OSMAN');
      expect(fields['nationalNumber'], '11974221992');
      expect(fields['nationalityText'], 'Sudan');
      expect(fields['nationalityTextArabic'], 'السودان');
      expect(fields['placeOfBirthArabic'], 'امدرمان');
      expect(fields['placeOfBirth'], 'OMDURMAN');
      expect(fields['placeOfIssueArabic'], 'سنار');
      expect(fields['placeOfIssue'], 'SENNAR');
      expect(fields['issueDate'], '2023/10/13');
    });
  });
}
