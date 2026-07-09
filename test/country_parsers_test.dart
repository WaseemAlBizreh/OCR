import 'package:flutter_test/flutter_test.dart';
import 'package:mrz/features/arabic_document_scan/data/parsers/parser_utils.dart';
import 'package:mrz/features/arabic_document_scan/data/parsers/sudan_id_front_parser.dart';
import 'package:mrz/features/arabic_document_scan/data/parsers/uae_id_parser.dart';
import 'package:mrz/features/arabic_document_scan/domain/document_type.dart';

void main() {
  group('ParserUtils', () {
    test('normalizeArabic strips tatweel and dash noise', () {
      expect(
        ParserUtils.normalizeArabic('الإســــم'),
        'الاسم',
      );
      expect(
        ParserUtils.normalizeArabic('الإس---م'),
        'الاسم',
      );
    });

    test('extractArabicColonValue returns multi-word Arabic after colon', () {
      const text = '??? : ميرغني مكي ميرغني عثمان';

      final value = ParserUtils.extractArabicColonValue(text, minWords: 3);

      expect(value, contains('ميرغني'));
      expect(value, contains('عثمان'));
    });
  });

  group('SudanIdFrontParser', () {
    const sampleOcr = '''
جمهورية السودان
11974221992
بطاقة إثبات الشخصية ID CARD
الإسم : ميرغنى مكى ميرغنى عثمان
تاريخ الميلاد : 1992/09/23
مكان الميلاد : الخرطوم - امدرمان
الرقم الوطني : 11974221992
فصيلة الدم : O+
المهنة : طالب
العنوان : كافورى والسفارات، بحرى، بحرى، الخرطوم
ت / 0924201374
''';

    test('extracts Sudan ID front fields', () {
      final result = SudanIdFrontParser().parse(
        sampleOcr,
        imagePath: '/tmp/sudan_front.jpg',
      );

      expect(result.documentType, DocumentType.arabicId);
      expect(result.countryCode, 'sd');
      expect(result.fields['arabicName'], contains('ميرغنى'));
      expect(result.fields['nationalNumber'], '11974221992');
      expect(result.fields['dateOfBirth'], '1992/09/23');
      expect(result.fields['placeOfBirth'], contains('الخرطوم'));
      expect(result.fields['bloodType'], 'O+');
      expect(result.fields['profession'], 'طالب');
      expect(result.fields['phone'], isNotNull);
    });

    test('extracts arabic name when label contains kashida', () {
      const ocrText = '''
جمهورية السودان
بطاقة إثبات الشخصية ID CARD
الإســــم: ميرغني مكي ميرغني عثمان
تاريخ الميلاد : 1992/09/23
الرقم الوطني : 11974221992
''';

      final result = SudanIdFrontParser().parse(
        ocrText,
        imagePath: '/tmp/sudan_front_kashida.jpg',
      );

      expect(result.fields['arabicName'], contains('ميرغني'));
      expect(result.fields['arabicName'], contains('عثمان'));
    });

    test('extracts arabic name when colon precedes kashida label', () {
      const ocrText = '''
جمهورية السودان
بطاقة إثبات الشخصية ID CARD
:الإســــم ميرغني مكي ميرغني عثمان
تاريخ الميلاد : 1992/09/23
الرقم الوطني : 11974221992
''';

      final result = SudanIdFrontParser().parse(
        ocrText,
        imagePath: '/tmp/sudan_front_rtl_colon.jpg',
      );

      expect(result.fields['arabicName'], contains('ميرغني'));
      expect(result.fields['arabicName'], contains('عثمان'));
    });

    test('extracts arabic name when kashida is read as dashes', () {
      const ocrText = '''
جمهورية السودان
بطاقة إثبات الشخصية ID CARD
الإس---م: ميرغني مكي ميرغني عثمان
تاريخ الميلاد : 1992/09/23
الرقم الوطني : 11974221992
''';

      final result = SudanIdFrontParser().parse(
        ocrText,
        imagePath: '/tmp/sudan_front_dash_noise.jpg',
      );

      expect(result.fields['arabicName'], contains('ميرغني'));
      expect(result.fields['arabicName'], contains('عثمان'));
    });

    test('extracts arabic name via colon fallback when label is garbled', () {
      const ocrText = '''
جمهورية السودان
بطاقة إثبات الشخصية ID CARD
??? : ميرغني مكي ميرغني عثمان
تاريخ الميلاد : 1992/09/23
الرقم الوطني : 11974221992
''';

      final result = SudanIdFrontParser().parse(
        ocrText,
        imagePath: '/tmp/sudan_front_colon_fallback.jpg',
      );

      expect(result.fields['arabicName'], contains('ميرغني'));
      expect(result.fields['arabicName'], contains('عثمان'));
    });
  });

  group('UaeIdParser', () {
    const sampleOcr = '''
UNITED ARAB EMIRATES
Resident Identity Card
ID Number / رقم الهوية
784-1995-8026406-9
Name: Mohammed Adam Esmaeel Eshag
:الاسم محمد آدم اسماعيل اسحاق
Date of Birth : 18/08/1995
:تاريخ الميلاد
Nationality: Sudan
:الجنسية جمهورية السودان
Issuing Date / تاريخ الاصدار 09/05/2025
Expiry Date / تاريخ الانتهاء 12/05/2026
Sex: M
:الجنس ذكر
''';

    test('extracts UAE resident ID fields', () {
      final result = UaeIdParser().parse(
        sampleOcr,
        imagePath: '/tmp/uae_id.jpg',
      );

      expect(result.countryCode, 'ae');
      expect(result.fields['idNumber'], '784-1995-8026406-9');
      expect(result.fields['arabicName'], contains('محمد'));
      expect(result.fields['englishName'], contains('Mohammed'));
      expect(result.fields['dateOfBirth'], '18/08/1995');
      expect(result.fields['nationalityEnglish'], contains('Sudan'));
      expect(result.fields['issuingDate'], '09/05/2025');
      expect(result.fields['expiryDate'], '12/05/2026');
      expect(result.fields['sex'], 'M');
    });
  });
}
