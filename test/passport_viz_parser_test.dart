import 'package:flutter_test/flutter_test.dart';
import 'package:mrz/features/identity_scan/data/front/passport_viz_parser.dart';
import 'package:mrz/features/identity_scan/data/mrz/mrz_parser.dart';
import 'package:mrz/features/identity_scan/domain/mrz_data.dart';

void main() {
  const parser = PassportVizParser();

  String cd(String v) => MrzParser.checkDigit(v).toString();

  /// A valid TD3 MRZ, built with real check digits.
  late final MrzData mrz;
  late final String mrzLines;
  setUpAll(() {
    const doc = 'P05000040', dob = '920923', exp = '270516';
    final personal = '11974221992'.padRight(14, '<');
    final line1 = 'P<SDNOSMAN<<MERGHANI<MEKKI<MERGHANI'.padRight(44, '<');
    final composite =
        cd('$doc${cd(doc)}$dob${cd(dob)}$exp${cd(exp)}$personal${cd(personal)}');
    final line2 = '$doc${cd(doc)}SDN$dob${cd(dob)}M$exp${cd(exp)}'
        '$personal${cd(personal)}$composite';
    mrzLines = '$line1\n$line2';
    mrz = MrzParser(clock: () => DateTime(2026, 10, 28))
        .parseLines([line1, line2], MrzFormat.td3)!;
  });

  const header = 'REPUBLIC OF THE SUDAN\nجمهورية السودان\n';

  test('the sample MRZ is valid and carries the national number', () {
    expect(mrz.isValid, isTrue);
    expect(mrz.optionalData, '11974221992');
  });

  test('reads English and Arabic labelled fields', () {
    final fields = parser.parse('''${header}Passport Type P   Country Code SDN   Passport No P05000040
Full Name MERGHANI MEKKI MERGHANI OSMAN
الاسم الكامل ميرغني مكي ميرغني عثمان
Nationality SUDANESE
National No 119-7422-1992
Date of Birth 23-09-1992   Sex M
Place of Birth OMDURMAN   مكان الميلاد امدرمان
Date of Issue 17-05-2022
Place of Issue KHARTOUM   مكان الإصدار الخرطوم
Date of Expiry 16-05-2027
$mrzLines''', mrz: mrz).fields;

    expect(fields['passportNumber'], 'P05000040');
    expect(fields['arabicName'], 'ميرغني مكي ميرغني عثمان');
    expect(fields['nationalNumber'], '11974221992');
    expect(fields['nationalityText'], 'SUDANESE');
    expect(fields['placeOfBirth'], 'OMDURMAN');
    expect(fields['placeOfBirthArabic'], 'امدرمان');
    expect(fields['issueDate'], '2022/05/17');
    expect(fields['placeOfIssue'], 'KHARTOUM');
    expect(fields['placeOfIssueArabic'], 'الخرطوم');
    expect(fields['expiryDate'], '2027/05/16');
  });

  test('finds the issue date by elimination when its label is garbled', () {
    final fields = parser.parse('''${header}Date of Birth 23-09-1992
Dote of lssve 17-05-2022
Date of Expiry 16-05-2027
Place of lssue KHARTOUM
$mrzLines''', mrz: mrz).fields;
    expect(fields['issueDate'], '2022/05/17');
    expect(fields['placeOfIssue'], 'KHARTOUM');
  });

  test('reads month-name dates and values printed below their labels', () {
    final fields = parser.parse('''${header}23 SEP 1992
17 MAY 2022
16 MAY 2027
Place of Birth
Omdurman''', mrz: mrz).fields;
    expect(fields['issueDate'], '2022/05/17');
    expect(fields['placeOfBirth'], 'OMDURMAN');
  });

  test('prefers the date that fits a whole-year validity among noise dates', () {
    final fields = parser.parse('''${header}23-09-1992
01-01-2015
17-05-2017
16-05-2027''', mrz: mrz).fields;
    expect(fields['issueDate'], '2017/05/17');
  });

  test('without an MRZ, three dates are birth, issue, expiry in order', () {
    final fields = parser.parse('''${header}23-09-1992
17-05-2022
16-05-2027''').fields;
    expect(fields['dateOfBirth'], '1992/09/23');
    expect(fields['issueDate'], '2022/05/17');
    expect(fields['expiryDate'], '2027/05/16');
  });
}
