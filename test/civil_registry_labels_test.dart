import 'package:flutter_test/flutter_test.dart';
import 'package:mrz/features/identity_scan/data/ocr/paddle/civil_registry/certificate_labels.dart';

CertificateField? exact(String text) {
  final hits = CertificateLabels.hitsIn(text);
  return hits.isEmpty ? null : hits.first.field;
}

CertificateField? fuzzy(String text) => CertificateLabels.fuzzyHit(text)?.field;

void main() {
  group('exact labels', () {
    test('every printed label is recognised', () {
      expect(exact('مكتب التسجيل'), CertificateField.registryOffice);
      expect(exact('تاريخ استخراج الشهادة'), CertificateField.issueDate);
      expect(exact('الرقم الوطني'), CertificateField.nationalNumber);
      expect(exact('الاسم'), CertificateField.name);
      expect(exact('مكان الميلاد'), CertificateField.placeOfBirth);
      expect(exact('تاريخ الميلاد'), CertificateField.dateOfBirth);
      expect(exact('الحالة الاجتماعية'), CertificateField.maritalStatus);
      expect(exact('الجنس'), CertificateField.gender);
      expect(exact('نوع الجنسية'), CertificateField.nationalityType);
      expect(exact('المهنة'), CertificateField.profession);
      expect(exact('عنوان العمل'), CertificateField.workAddress);
      expect(exact('اسم الوالدة'), CertificateField.motherName);
    });

    test('alef, ya and ta marbuta spellings and tatweel are tolerated', () {
      expect(exact('الرقم الوطنى'), CertificateField.nationalNumber);
      expect(exact('الحاله الاجتماعيه'), CertificateField.maritalStatus);
      expect(exact('اسم الوالده'), CertificateField.motherName);
      expect(exact('تـاريخ الميـلاد'), CertificateField.dateOfBirth);
      expect(exact('تاريخ الإصدار'), CertificateField.issueDate);
    });

    test('a longer label wins over a shorter one it contains', () {
      expect(exact('نوع الجنسية'), CertificateField.nationalityType);
      expect(exact('الاسم الكامل'), CertificateField.name);
    });

    test('a label glued to its value is still a label: الجنسذكر', () {
      expect(exact('الجنسذكر'), CertificateField.gender);
      expect(exact('الجنسنكر'), CertificateField.gender);
      expect(exact('الحالة الاجتماعيةغير متزوج'), CertificateField.maritalStatus);
      expect(exact('الجنسية'), isNot(CertificateField.gender));
    });

    test('a label inside a longer word is not a label', () {
      expect(exact('الاسماء'), isNull);
    });
  });

  group('garbled labels (fuzzy)', () {
    test('الرقم الوطي is الرقم الوطني', () {
      expect(exact('الرقم الوطي'), isNull);
      expect(fuzzy('الرقم الوطي'), CertificateField.nationalNumber);
    });

    test('lost or moved dots', () {
      expect(fuzzy('تاريخ المبلاد'), CertificateField.dateOfBirth);
      expect(fuzzy('مكان المبلاد'), CertificateField.placeOfBirth);
      expect(fuzzy('الحالة الاجتماعبة'), CertificateField.maritalStatus);
      expect(fuzzy('عنوان العمل'), CertificateField.workAddress);
    });

    test('missing letters', () {
      expect(fuzzy('الحالة الاجتماع'), CertificateField.maritalStatus);
      expect(fuzzy('تاريخ استخراج الشهاد'), CertificateField.issueDate);
      expect(fuzzy('مكتب التسجل'), CertificateField.registryOffice);
    });

    test('ordinary words and bare "تاريخ" are not labels', () {
      expect(fuzzy('الخرطوم أم درمان'), isNull);
      expect(fuzzy('تاريخ'), isNull);
      expect(fuzzy('محمد أحمد عثمان'), isNull);
    });

    test('digits and Latin text have no Arabic shape to match', () {
      expect(fuzzy('12345678901'), isNull);
      expect(fuzzy('Passport'), isNull);
    });
  });
}
