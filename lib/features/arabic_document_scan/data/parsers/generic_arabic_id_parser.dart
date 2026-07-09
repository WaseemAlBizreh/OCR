import 'package:mrz/features/arabic_document_scan/data/parsers/country_parser.dart';
import 'package:mrz/features/arabic_document_scan/domain/document_scan_result.dart';
import 'package:mrz/features/arabic_document_scan/domain/document_type.dart';

class GenericArabicIdParser implements CountryParser {
  GenericArabicIdParser({required this.countryCode});

  @override
  final String countryCode;

  static final _arabicBlock = RegExp(r'[\u0600-\u06FF\u0750-\u077F\s]+');
  static final _englishName = RegExp(r'\b[A-Z][A-Z\s,\-]{4,}\b');
  static final _gregorianDate = RegExp(r'\b(\d{1,2})[/.-](\d{1,2})[/.-](\d{2,4})\b');
  static final _hijriDate = RegExp(r'\b(\d{1,2})[/.-](\d{1,2})[/.-](\d{4})\s*هـ');
  static final _arabicIndicDigits = RegExp(r'[\u0660-\u0669\u06F0-\u06F9]+');
  static final _westernDigits = RegExp(r'\b\d{6,14}\b');

  @override
  DocumentScanResult parse(
    String ocrText, {
    required String imagePath,
    OcrEngineComparison? ocrComparison,
  }) {
    final normalized = _normalizeDigits(ocrText);
    final lines = normalized
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.length > 1)
        .toList();

    final warnings = <String>[];
    final arabicName = _extractArabicName(lines);
    final englishName = _extractEnglishName(lines);
    final identityNumber = _extractIdentityNumber(normalized, countryCode);
    final dateOfBirth = _extractDateOfBirth(lines);
    final gender = _extractGender(normalized);

    if (arabicName == null) {
      warnings.add('Arabic name not found — review raw OCR text.');
    }
    if (identityNumber == null) {
      warnings.add('Identity number not found — review raw OCR text.');
    }
    if (englishName == null) {
      warnings.add('English name not found.');
    }

    return DocumentScanResult(
      documentType: DocumentType.arabicId,
      countryCode: countryCode,
      fields: {
        'arabicName': arabicName,
        'englishName': englishName,
        'identityNumber': identityNumber,
        'dateOfBirth': dateOfBirth,
        'gender': gender,
        'confidence': warnings.isEmpty ? 'medium' : 'low',
      },
      rawOcrText: ocrText,
      imagePath: imagePath,
      warnings: warnings,
      ocrComparison: ocrComparison,
    );
  }

  String _normalizeDigits(String text) {
    const arabicIndic = '٠١٢٣٤٥٦٧٨٩';
    const easternArabic = '۰۱۲۳۴۵۶۷۸۹';
    var result = text;
    for (var i = 0; i < 10; i++) {
      result = result
          .replaceAll(arabicIndic[i], '$i')
          .replaceAll(easternArabic[i], '$i');
    }
    return result;
  }

  String? _extractArabicName(List<String> lines) {
    String? best;
    const skipKeywords = [
      'الجمهورية',
      'المملكة',
      'بطاقة',
      'تحقيق',
      'الهوية',
      'الجنسية',
      'تاريخ',
      'رقم',
      'جمهورية',
    ];

    for (final line in lines) {
      if (!_arabicBlock.hasMatch(line)) continue;
      final arabicOnly = line.replaceAll(RegExp(r'[^\u0600-\u06FF\s]'), '').trim();
      if (arabicOnly.length < 6) continue;
      if (skipKeywords.any(arabicOnly.contains)) continue;
      if (arabicOnly.split(RegExp(r'\s+')).length < 2) continue;
      if (best == null || arabicOnly.length > best.length) {
        best = arabicOnly;
      }
    }
    return best;
  }

  String? _extractEnglishName(List<String> lines) {
    for (final line in lines) {
      final match = _englishName.firstMatch(line);
      if (match != null && match.group(0)!.length >= 6) {
        return match.group(0)!.trim();
      }
    }
    return null;
  }

  String? _extractIdentityNumber(String text, String country) {
    final lengths = _idLengthsForCountry(country);
    for (final length in lengths) {
      final pattern = RegExp('\\b\\d{$length}\\b');
      final match = pattern.firstMatch(text);
      if (match != null) return match.group(0);
    }
    if (_westernDigits.hasMatch(text)) {
      return _westernDigits.allMatches(text).map((m) => m.group(0)).firstWhere(
            (value) => (value?.length ?? 0) >= 8,
            orElse: () => null,
          );
    }
    if (_arabicIndicDigits.hasMatch(text)) {
      final normalized = _normalizeDigits(text);
      return _westernDigits.firstMatch(normalized)?.group(0);
    }
    return null;
  }

  List<int> _idLengthsForCountry(String country) => switch (country) {
        'ae' => [15],
        'sd' => [10],
        _ => [10, 15],
      };

  String? _extractDateOfBirth(List<String> lines) {
    for (final line in lines) {
      if (line.contains('الميلاد') || line.contains('Birth')) {
        final hijri = _hijriDate.firstMatch(line);
        if (hijri != null) return hijri.group(0);
        final greg = _gregorianDate.firstMatch(line);
        if (greg != null) return greg.group(0);
      }
    }
    for (final line in lines) {
      final greg = _gregorianDate.firstMatch(line);
      if (greg != null) return greg.group(0);
    }
    return null;
  }

  String? _extractGender(String text) {
    final lower = text.toLowerCase();
    if (text.contains('ذكر') || lower.contains('male') || RegExp(r'\bM\b').hasMatch(text)) {
      return 'M';
    }
    if (text.contains('أنثى') || text.contains('انثى') || lower.contains('female') || RegExp(r'\bF\b').hasMatch(text)) {
      return 'F';
    }
    return null;
  }
}
