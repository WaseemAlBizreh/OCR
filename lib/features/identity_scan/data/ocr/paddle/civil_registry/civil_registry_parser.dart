import 'package:mrz/features/identity_scan/data/front/card_dates.dart';
import 'package:mrz/features/identity_scan/data/front/parser_utils.dart';
import 'package:mrz/features/identity_scan/data/ocr/paddle/civil_registry/certificate_labels.dart';
import 'package:mrz/features/identity_scan/data/ocr/paddle/passport/passport_layout.dart';
import 'package:mrz/features/identity_scan/data/ocr/paddle/passport/passport_line.dart';

/// Printed fields read from a civil registry certificate.
class CertificatePage {
  const CertificatePage(this.fields, this.confidence, this.warnings);

  /// Keyed by [CertificateField.name]; null when not found.
  final Map<String, String?> fields;

  /// OCR confidence (0..1) of the line each value came from.
  final Map<String, double> confidence;
  final List<String> warnings;
}

class _Hit {
  const _Hit(this.field, this.line, this.inline);

  final CertificateField field;
  final PassportLine line;

  /// Text after the label on the same line (up to the next label).
  final String inline;
}

/// Reads the fields of a civil registry certificate (A4, `label: value` rows).
///
/// Labels are found with [CertificateLabels] (exact, then fuzzy, then the other
/// engine's reading) and each value is located from line positions
/// ([PassportLayout]), so row order and column layout are not assumed. Values
/// are validated by field type; anything not found stays null.
class CivilRegistryParser {
  const CivilRegistryParser();

  static const _maxCandidates = 4;

  static final _directionMarks =
      RegExp(r'[\u200e\u200f\u061c\u202a-\u202e\u2066-\u2069]');
  static final _arabicWord = RegExp(r'[ء-يٮ-ۓ]{2,}');
  static final _hasDigit = RegExp(r'[0-9٠-٩۰-۹]');

  static const maritalValues = [
    'أعزب', 'عزباء', 'عازب', 'متزوج', 'متزوجة', 'مطلق', 'مطلقة', 'أرمل', 'أرملة',
  ];
  static const nationalityTypeValues = [
    'بالميلاد', 'بالتجنس', 'بالزواج', 'بالإقامة',
  ];

  static final _readable = [
    for (final f in CertificateField.values)
      if (f != CertificateField.other) f,
  ];

  CertificatePage parse(List<PassportLine> lines) {
    final page = [
      for (final line in lines) line.withText(line.text.replaceAll(_directionMarks, '')),
    ];
    final hits = _hits(page);
    final labelLines = {for (final h in hits) h.line};

    List<PassportLine> candidates(_Hit hit) =>
        PassportLayout.valueCandidates(hit.line, page, labelLines)
            .take(_maxCandidates)
            .toList();

    // Texts to try for one field, in priority order: the rest of the label's
    // own line, then the nearby lines.
    Iterable<({String text, double confidence})> sources(CertificateField field) sync* {
      for (final hit in hits.where((h) => h.field == field)) {
        yield (text: hit.inline, confidence: hit.line.confidence);
        // Digits ML Kit read inside the label's own box (Paddle drops them).
        for (final d in page) {
          if (!identical(d, hit.line) &&
              !labelLines.contains(d) &&
              _hasDigit.hasMatch(d.text) &&
              hit.line.overlapRatio(d) > 0.6) {
            yield (text: d.text, confidence: d.confidence);
          }
        }
        for (final c in candidates(hit)) {
          yield (text: c.text, confidence: c.confidence);
        }
      }
    }

    final fields = <String, String?>{};
    final confidence = <String, double>{};
    for (final field in _readable) {
      String? value;
      for (final source in sources(field)) {
        value = _extract(field, source.text);
        if (value != null) {
          confidence[field.name] = source.confidence;
          break;
        }
      }
      fields[field.name] = value;
    }

    // The number is the one field that can be found without its label.
    fields[CertificateField.nationalNumber.name] ??= _unlabelledNumber(page);

    _dateFallback(fields, page);
    final warnings = _crossValidate(fields);
    warnings.addAll(ParserUtils.collectWarnings(
      fields,
      [for (final f in _readable) f.name],
    ));
    return CertificatePage(fields, confidence, warnings);
  }

  /// The line carrying the label of [field], or null when it was not found.
  PassportLine? labelLine(CertificateField field, List<PassportLine> lines) {
    final page = [
      for (final line in lines) line.withText(line.text.replaceAll(_directionMarks, '')),
    ];
    for (final hit in _hits(page)) {
      if (hit.field == field) return hit.line;
    }
    return null;
  }

  // ------------------------------------------------------------------ labels

  static List<_Hit> _hits(List<PassportLine> lines) {
    final hits = <_Hit>[];
    for (final line in lines) {
      final found = CertificateLabels.hitsIn(line.text);
      if (found.isNotEmpty) {
        for (var i = 0; i < found.length; i++) {
          final end = i + 1 < found.length ? found[i + 1].start : line.text.length;
          final inline = line.text
              .substring(found[i].end, end)
              .replaceAll(RegExp(r'^[\s:\-./]+'), '');
          hits.add(_Hit(found[i].field, line, inline));
        }
        continue;
      }
      // The title may be garbled in this reading but fine in the other
      // engine's (alts). Nothing after a fuzzy label is trusted as a value.
      if (_isKnownValue(line.text)) continue; // a value, not a garbled label
      final fuzzy = CertificateLabels.fuzzyHit(line.text) ?? _labelInAlts(line);
      if (fuzzy != null) hits.add(_Hit(fuzzy.field, line, ''));
    }
    // Reading order, so the first hit of a field is the topmost one.
    hits.sort((a, b) {
      final dy = a.line.centerY - b.line.centerY;
      return dy.abs() < a.line.height * 0.6 ? b.line.left.compareTo(a.line.left) : dy.sign.toInt();
    });
    return hits;
  }

  /// Closed-vocabulary values (marital status, nationality type, gender) look
  /// enough like some labels to fool the fuzzy match; they are never labels.
  static bool _isKnownValue(String text) =>
      snap(text, maritalValues, tolerant: false) != null ||
      snap(text, nationalityTypeValues, tolerant: false) != null ||
      gender(text, tolerant: false) != null;

  static CertificateLabelHit? _labelInAlts(PassportLine line) {
    for (final alt in line.alts) {
      final exact = CertificateLabels.hitsIn(alt);
      if (exact.isNotEmpty) return exact.first;
    }
    for (final alt in line.alts) {
      final fuzzy = CertificateLabels.fuzzyHit(alt);
      if (fuzzy != null) return fuzzy;
    }
    return null;
  }

  // ------------------------------------------------------------------ values

  /// A date whose label was not read: of the dates on the page, the earliest
  /// is the birth date and the latest the issue date.
  static void _dateFallback(Map<String, String?> fields, List<PassportLine> lines) {
    final all = {
      for (final l in lines) ...CardDates.datesIn(l.text).map(CardDates.iso),
    }.toList()
      ..sort();
    const birthKey = 'dateOfBirth', issueKey = 'issueDate';
    final birth = fields[birthKey], issue = fields[issueKey];
    if (birth == null && issue == null && all.length >= 2) {
      fields[birthKey] = all.first;
      fields[issueKey] = all.last;
    } else if (birth == null && issue != null) {
      final earlier = all.where((d) => d.compareTo(issue) < 0);
      if (earlier.isNotEmpty) fields[birthKey] = earlier.first;
    } else if (issue == null && birth != null) {
      final later = all.where((d) => d.compareTo(birth) > 0);
      if (later.isNotEmpty) fields[issueKey] = later.last;
    }
  }

  static String? _extract(CertificateField field, String text) {
    if (text.trim().isEmpty) return null;
    switch (field) {
      case CertificateField.nationalNumber:
        return nationalNumber(text);
      case CertificateField.issueDate:
      case CertificateField.dateOfBirth:
        final dates = CardDates.datesIn(text);
        return dates.isEmpty ? null : CardDates.iso(dates.first);
      case CertificateField.gender:
        return gender(text);
      case CertificateField.maritalStatus:
        return marital(text);
      case CertificateField.nationalityType:
        return snap(text, nationalityTypeValues) ?? arabicValue(text);
      case CertificateField.name:
      case CertificateField.motherName:
        return arabicValue(text, minWords: 2);
      case CertificateField.registryOffice:
      case CertificateField.placeOfBirth:
      case CertificateField.profession:
      case CertificateField.workAddress:
        return arabicValue(text);
      case CertificateField.other:
        return null;
    }
  }

  /// Arabic words of [text], tatweel and alef variants normalised; null when
  /// fewer than [minWords] words are there.
  static String? arabicValue(String text, {int minWords = 1}) {
    final words = _arabicWord
        .allMatches(text)
        .map((m) => ParserUtils.normalizeArabic(m.group(0)!))
        .toList();
    return words.length >= minWords ? words.join(' ') : null;
  }

  /// An 11-digit national number (the Sudan length), else any 8-16 digit run;
  /// spaces and hyphens inside are ignored and dates are not numbers.
  static String? nationalNumber(String text) {
    if (CardDates.datesIn(text).isNotEmpty) return null;
    final compact = ParserUtils.normalizeDigits(text).replaceAll(RegExp(r'[\s\-]'), '');
    return RegExp(r'(?<!\d)\d{11}(?!\d)').firstMatch(compact)?.group(0) ??
        RegExp(r'(?<!\d)\d{8,16}(?!\d)').firstMatch(compact)?.group(0);
  }

  /// The only 11-digit number on the page, when its label was not read.
  static String? _unlabelledNumber(List<PassportLine> lines) {
    final found = <String>{};
    for (final line in lines) {
      final compact = ParserUtils.normalizeDigits(line.text).replaceAll(RegExp(r'[\s\-]'), '');
      if (CardDates.datesIn(line.text).isNotEmpty) continue;
      for (final m in RegExp(r'(?<!\d)\d{11}(?!\d)').allMatches(compact)) {
        found.add(m.group(0)!);
      }
    }
    return found.length == 1 ? found.first : null;
  }

  /// Marital status; `غير متزوج` ("not married") must not read as `متزوج`.
  static String? marital(String text) {
    final negated = RegExp('(?<![ء-ي])غ[يب]ر(?![ء-ي])').hasMatch(ParserUtils.normalizeArabic(text));
    final status = snap(text, maritalValues);
    if (status == null) return negated ? 'غير متزوج' : null;
    if (!negated) return status;
    return status.endsWith('ة') ? 'غير متزوجة' : 'غير متزوج';
  }

  /// `M` or `F` from ذكر / أنثى, tolerating one wrong letter in أنثى.
  static String? gender(String text, {bool tolerant = true}) {
    final fromUtils = ParserUtils.extractGender(text);
    if (fromUtils != null) return fromUtils;
    final words = _arabicWord.allMatches(ParserUtils.normalizeArabic(text)).map((m) => m.group(0)!);
    for (final word in words) {
      if (word == 'ذكر') return 'M';
      // OCR often turns the dotted ذ into ن (`نكر`): one wrong letter.
      if (tolerant && word.length == 3 && _distance(_shape(word), _shape('ذكر')) <= 1) return 'M';
      if (word.length >= 4 && _distance(_shape(word), _shape('انثى')) <= 1) return 'F';
    }
    return null;
  }

  /// The entry of [vocabulary] that a word of [text] is, allowing for lost
  /// dots and (when [tolerant]) one wrong letter, two for long words; null
  /// when none is near.
  static String? snap(String text, List<String> vocabulary, {bool tolerant = true}) {
    final words = _arabicWord.allMatches(text).map((m) => _shape(m.group(0)!));
    String? best;
    var bestDistance = 1 << 30;
    for (final word in words) {
      for (final entry in vocabulary) {
        final target = _shape(entry);
        final allowed =
            !tolerant ? 0 : (target.length >= 7 ? 2 : (target.length >= 4 ? 1 : 0));
        final d = _distance(word, target);
        if (d <= allowed && d < bestDistance) {
          best = entry;
          bestDistance = d;
        }
      }
    }
    return best;
  }

  /// Comparison form of an Arabic word: alef variants, ya/alef maqsura and
  /// ta marbuta unified, and the dotted letters folded to their bare shape.
  static String _shape(String word) {
    const shapes = {
      'أ': 'ا', 'إ': 'ا', 'آ': 'ا', 'ى': 'ب', 'ي': 'ب', 'ئ': 'ب', 'ت': 'ب',
      'ث': 'ب', 'ن': 'ب', 'خ': 'ح', 'ج': 'ح', 'ذ': 'د', 'ز': 'ر', 'ش': 'س',
      'ض': 'ص', 'ظ': 'ط', 'غ': 'ع', 'ق': 'ف', 'ة': 'ه', 'ؤ': 'و',
    };
    return word.split('').map((c) => shapes[c] ?? c).join();
  }

  static int _distance(String a, String b) {
    var previous = List<int>.generate(b.length + 1, (j) => j);
    for (var i = 1; i <= a.length; i++) {
      final current = List<int>.filled(b.length + 1, 0)..[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final substitution = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1);
        current[j] = [substitution, previous[j] + 1, current[j - 1] + 1]
            .reduce((x, y) => x < y ? x : y);
      }
      previous = current;
    }
    return previous[b.length];
  }

  // ------------------------------------------------------------- validation

  /// The birth date must precede the issue date; if not, one of the two is
  /// misread and the birth date is dropped rather than reported wrong.
  static List<String> _crossValidate(Map<String, String?> fields) {
    final birth = fields[CertificateField.dateOfBirth.name];
    final issue = fields[CertificateField.issueDate.name];
    if (birth != null && issue != null && birth.compareTo(issue) >= 0) {
      fields[CertificateField.dateOfBirth.name] = null;
      return ['Date of birth ($birth) is not before the issue date ($issue); check both.'];
    }
    return [];
  }
}
