class ParserUtils {
  ParserUtils._();

  static final _dateYmd = RegExp(r'(\d{4})[/.-](\d{1,2})[/.-](\d{1,2})');
  static final _dateDmy = RegExp(r'(\d{1,2})[/.-](\d{1,2})[/.-](\d{4})');
  static final _arabicText = RegExp(r'[\u0600-\u06FF\u0750-\u077F\s\-،]+');
  static final _arabicNoiseBetweenLetters =
      RegExp(r'(?<=[\u0600-\u06FF])[_\-.]+(?=[\u0600-\u06FF])');
  static final _alefVariants = RegExp(r'[إأآ]');

  static const _colonFieldSkipKeywords = [
    'تاريخ',
    'رقم',
    'مكان',
    'فصيلة',
    'المهنة',
    'العنوان',
    'الجنسية',
    'بطاقة',
    'جمهورية',
    'المملكة',
    'الهوية',
    'الجنس',
    'الاصدار',
    'الانتهاء',
    'انتهاء',
  ];

  static String normalizeDigits(String text) {
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

  /// Strips kashida/tatweel, OCR dash noise, and unifies alef variants for matching.
  static String normalizeArabic(String text) {
    var result = text.replaceAll('\u0640', '');
    while (_arabicNoiseBetweenLetters.hasMatch(result)) {
      result = result.replaceAll(_arabicNoiseBetweenLetters, '');
    }
    result = result.replaceAll(_alefVariants, 'ا');
    result = result.replaceAll(RegExp(r'\s+'), ' ');
    return result.trim();
  }

  /// Digit + Arabic normalization used before label and line matching.
  static String normalizeForParsing(String text) {
    return normalizeArabic(normalizeDigits(text));
  }

  static List<String> rawLines(String text) {
    return text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
  }

  static List<String> lines(String text) {
    return rawLines(text);
  }

  static String? extractLabeledValue(
    String text, {
    required List<String> labels,
    RegExp? valuePattern,
    bool arabicValue = false,
  }) {
    final normalized = normalizeForParsing(text);
    final allLines = lines(text);

    for (final line in allLines) {
      for (final label in labels) {
        final matchRange = _findNormalizedLabelRange(line, label);
        if (matchRange == null) continue;

        var remainder = line.substring(matchRange.end).trim();
        remainder = remainder.replaceFirst(RegExp(r'^[:：\s]+'), '').trim();

        if (remainder.isNotEmpty) {
          if (valuePattern != null) {
            final patternMatch = valuePattern.firstMatch(remainder);
            if (patternMatch != null) {
              return patternMatch.groupCount >= 1
                  ? (patternMatch.group(1) ?? patternMatch.group(0))
                  : patternMatch.group(0);
            }
          }
          final value = _pickValue(remainder, null, arabicValue);
          if (value != null) return value;
        }
      }
    }

    for (var i = 0; i < allLines.length - 1; i++) {
      final line = allLines[i];
      if (labels.any((label) => _lineContainsNormalizedLabel(line, label))) {
        final next = allLines[i + 1];
        final value = _pickValue(next, valuePattern, arabicValue);
        if (value != null) return value;
      }
    }

    if (valuePattern != null) {
      return valuePattern.firstMatch(normalized)?.group(0);
    }

    return null;
  }

  /// Fallback for Arabic values on lines with a colon when label OCR is garbled.
  static String? extractArabicColonValue(
    String text, {
    int minWords = 2,
  }) {
    for (final line in lines(text)) {
      final normalizedLine = normalizeForParsing(line);
      if (_colonFieldSkipKeywords.any(normalizedLine.contains)) continue;

      final colonIndex = _firstColonIndex(line);
      if (colonIndex == -1) continue;

      final afterColon = line.substring(colonIndex + 1).trim();
      final valueFromAfter = _extractArabicFromSegment(afterColon, minWords);
      if (valueFromAfter != null) return valueFromAfter;

      if (afterColon.isEmpty) {
        final beforeColon = line.substring(0, colonIndex).trim();
        final valueFromBefore = _extractArabicFromSegment(beforeColon, minWords);
        if (valueFromBefore != null) return valueFromBefore;
      }
    }

    return null;
  }

  static String? _extractArabicFromSegment(String segment, int minWords) {
    var cleaned = segment.trim();
    cleaned = cleaned.replaceFirst(RegExp(r'^[:：\s]+'), '').trim();
    cleaned = cleaned.replaceFirst(RegExp(r'^(ال)?[اإأآ]سم\s*'), '').trim();
    if (cleaned.isEmpty) return null;

    final value = _pickValue(cleaned, null, true);
    if (value == null) return null;

    final wordCount = value.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    if (wordCount >= minWords) return value;
    return null;
  }

  static int _firstColonIndex(String line) {
    final asciiColon = line.indexOf(':');
    final fullWidthColon = line.indexOf('：');
    if (asciiColon == -1) return fullWidthColon;
    if (fullWidthColon == -1) return asciiColon;
    return asciiColon < fullWidthColon ? asciiColon : fullWidthColon;
  }

  static bool _lineContainsNormalizedLabel(String line, String label) {
    return normalizeForParsing(line).contains(normalizeForParsing(label));
  }

  static ({int start, int end})? _findNormalizedLabelRange(
    String line,
    String label,
  ) {
    final normalizedLabel = normalizeForParsing(label);
    if (normalizedLabel.isEmpty) return null;

    for (var start = 0; start < line.length; start++) {
      for (var end = start + 1; end <= line.length; end++) {
        final segment = line.substring(start, end);
        if (normalizeForParsing(segment) == normalizedLabel) {
          return (start: start, end: end);
        }
      }
    }
    return null;
  }

  static String? _pickValue(
    String candidate,
    RegExp? valuePattern,
    bool arabicValue,
  ) {
    if (valuePattern != null) {
      final match = valuePattern.firstMatch(candidate);
      if (match != null) {
        return match.groupCount >= 1 ? (match.group(1) ?? match.group(0)) : match.group(0);
      }
    }

    if (arabicValue) {
      final match = _arabicText.firstMatch(candidate);
      if (match != null) {
        final value = match.group(0)!.trim();
        if (value.length >= 2) return value;
      }
    }

    final cleaned = candidate.trim();
    return cleaned.isEmpty ? null : cleaned;
  }

  static String? extractDate(String text, List<String> labels) {
    final normalized = normalizeForParsing(text);

    for (final label in labels) {
      final normalizedLabel = normalizeForParsing(label);
      final labelIndex = normalized.indexOf(normalizedLabel);
      if (labelIndex == -1) continue;
      final afterLabel = normalized.substring(labelIndex + normalizedLabel.length);
      final match = _dateYmd.firstMatch(afterLabel) ?? _dateDmy.firstMatch(afterLabel);
      if (match != null) return match.group(0);
    }

    for (final line in lines(text)) {
      if (!labels.any((label) => _lineContainsNormalizedLabel(line, label))) continue;
      final normalizedLine = normalizeForParsing(line);
      final match = _dateYmd.firstMatch(normalizedLine) ?? _dateDmy.firstMatch(normalizedLine);
      if (match != null) return match.group(0);
    }

    return _dateYmd.firstMatch(normalized)?.group(0) ??
        _dateDmy.firstMatch(normalized)?.group(0);
  }

  static String? extractEnglishNameLine(String text, {List<String> labels = const ['NAME']}) {
    final value = extractLabeledValue(
      text,
      labels: labels,
      valuePattern: RegExp(r'([A-Z][A-Z\s<]{4,})'),
    );
    return value?.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String? extractGender(String text) {
    final normalized = normalizeForParsing(text);
    if (normalized.contains('ذكر') ||
        RegExp(r'\bM\b').hasMatch(normalized) ||
        normalized.toLowerCase().contains('male')) {
      return 'M';
    }
    if (normalized.contains('أنثى') ||
        normalized.contains('انثى') ||
        RegExp(r'\bF\b').hasMatch(normalized) ||
        normalized.toLowerCase().contains('female')) {
      return 'F';
    }
    return null;
  }

  static List<String> collectWarnings(Map<String, dynamic> fields, List<String> requiredKeys) {
    final warnings = <String>[];
    for (final key in requiredKeys) {
      final value = fields[key];
      if (value == null || '$value'.trim().isEmpty) {
        warnings.add('Missing field: $key');
      }
    }
    return warnings;
  }
}
