import 'package:mrz/features/identity_scan/domain/mrz_data.dart';

/// ICAO 9303 parser for TD1 (ID cards) and TD3 (passports).
///
/// OCR input is never trusted: every field is coerced to the character class
/// it must belong to (digits, letters) and the check digits decide whether the
/// read is good. Alphanumeric fields that fail their check digit are retried
/// with the usual look-alike swaps (O/0, I/1, S/5, B/8, Z/2).
class MrzParser {
  const MrzParser({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  static const _toDigit = {
    'O': '0', 'Q': '0', 'D': '0', 'I': '1', 'L': '1', 'Z': '2',
    'S': '5', 'B': '8', 'G': '6',
  };
  static const _toLetter = {
    '0': 'O', '1': 'I', '2': 'Z', '5': 'S', '8': 'B', '6': 'G',
  };
  static const _swaps = {
    'O': '0', '0': 'O', 'I': '1', '1': 'I', 'S': '5', '5': 'S',
    'B': '8', '8': 'B', 'Z': '2', '2': 'Z',
  };

  static final _lineLike = RegExp(r'^[A-Z0-9<«‹〈＜≪⪡⟨《]+$');

  /// A trailing run of filler, possibly ending in the last check digit(s).
  /// OCR often reads some of its `<` as `K`; the run must start with `<`, so
  /// a K that belongs to a name (`MARK`, `KHALID`) before it is never touched.
  static final _fillerTail = RegExp(r'<[<K]{2,}(?=\d{0,2}$)');

  static String normalizeLine(String raw) {
    final cleaned = raw.toUpperCase().replaceAll(RegExp(r'\s+'), '');
    final mapped = cleaned
        .replaceAll(RegExp('[«‹〈＜]'), '<')
        .replaceAll(RegExp(r'[^A-Z0-9<]'), '<');
    final tail = _fillerTail.firstMatch(mapped);
    if (tail == null) return mapped;
    return mapped.replaceRange(tail.start, tail.end, tail[0]!.replaceAll('K', '<'));
  }

  static bool _looksLikeMrzLine(String raw) {
    final compact = raw.toUpperCase().replaceAll(RegExp(r'\s+'), '');
    if (compact.length < 24 || compact.length > 50) return false;
    final good = compact.split('').where((c) => _lineLike.hasMatch(c)).length;
    return good / compact.length >= 0.85;
  }

  /// Finds the best MRZ block inside free OCR text, or null when no block
  /// passes at least two check digits.
  MrzData? parseText(String ocrText, {Iterable<MrzFormat>? formats}) {
    final candidates = ocrText
        .split('\n')
        .where(_looksLikeMrzLine)
        .map(normalizeLine)
        .toList();

    MrzData? best;
    for (final format in formats ?? MrzFormat.values) {
      for (var i = 0; i + format.lineCount <= candidates.length; i++) {
        final window = candidates.sublist(i, i + format.lineCount);
        if (window.any((l) => (l.length - format.lineLength).abs() > 3)) {
          continue;
        }
        final parsed = parseLines(window, format);
        if (parsed == null) continue;
        if (best == null || parsed.passedChecks > best.passedChecks) {
          best = parsed;
        }
      }
    }
    if (best == null || best.passedChecks < 2) return null;
    return best;
  }

  MrzData? parseLines(List<String> lines, MrzFormat format) {
    if (lines.length != format.lineCount) return null;
    // Only the filler runs of the fixed-field lines may be stretched; the
    // name line is padded on the right.
    final nameLine = format == MrzFormat.td1 ? 2 : 0;
    final fitted = [
      for (var i = 0; i < lines.length; i++)
        _fit(lines[i], format.lineLength, stretchFiller: i != nameLine),
    ];
    return switch (format) {
      MrzFormat.td1 => _parseTd1(fitted),
      MrzFormat.td3 => _parseTd3(fitted),
    };
  }

  MrzData _parseTd1(List<String> l) {
    final docNo = _repaired(l[0].substring(5, 14), l[0][14], numeric: false);
    final dob = _repaired(l[1].substring(0, 6), l[1][6], numeric: true);
    final exp = _repaired(l[1].substring(8, 14), l[1][14], numeric: true);
    final optional1 = l[0].substring(15, 30);
    final optional2 = l[1].substring(18, 29);

    final composite = _verify(
      '${docNo.field}${docNo.check}$optional1'
      '${dob.field}${dob.check}${exp.field}${exp.check}$optional2',
      l[1][29],
    );
    final (surname, given) = _names(l[2]);

    return MrzData(
      format: MrzFormat.td1,
      lines: l,
      documentCode: _letters(l[0].substring(0, 2)),
      issuingCountry: _letters(l[0].substring(2, 5)),
      documentNumber: _clean(docNo.field),
      dateOfBirth: _isoDate(dob.field, isBirth: true),
      sex: _sex(l[1][7]),
      expiryDate: _isoDate(exp.field, isBirth: false),
      nationality: _letters(l[1].substring(15, 18)),
      surname: surname,
      givenNames: given,
      optionalData: _clean('$optional1$optional2'),
      checks: {
        'documentNumber': docNo.passed,
        'dateOfBirth': dob.passed,
        'expiryDate': exp.passed,
        'composite': composite,
      },
    );
  }

  MrzData _parseTd3(List<String> l) {
    final docNo = _repaired(l[1].substring(0, 9), l[1][9], numeric: false);
    final dob = _repaired(l[1].substring(13, 19), l[1][19], numeric: true);
    final exp = _repaired(l[1].substring(21, 27), l[1][27], numeric: true);
    final personal = l[1].substring(28, 42);
    final personalPassed = personal.replaceAll('<', '').isEmpty
        ? '<0'.contains(l[1][42])
        : _verify(personal, l[1][42]);

    final composite = _verify(
      '${docNo.field}${docNo.check}'
      '${dob.field}${dob.check}${exp.field}${exp.check}'
      '$personal${l[1][42]}',
      l[1][43],
    );
    final (surname, given) = _names(l[0].substring(5));

    return MrzData(
      format: MrzFormat.td3,
      lines: l,
      documentCode: _letters(l[0].substring(0, 2)),
      issuingCountry: _letters(l[0].substring(2, 5)),
      documentNumber: _clean(docNo.field),
      dateOfBirth: _isoDate(dob.field, isBirth: true),
      sex: _sex(l[1][20]),
      expiryDate: _isoDate(exp.field, isBirth: false),
      nationality: _letters(l[1].substring(10, 13)),
      surname: surname,
      givenNames: given,
      optionalData: _clean(personal),
      checks: {
        'documentNumber': docNo.passed,
        'dateOfBirth': dob.passed,
        'expiryDate': exp.passed,
        'personalNumber': personalPassed,
        'composite': composite,
      },
    );
  }

  // ---------------------------------------------------------------- checks

  static int checkDigit(String value) {
    const weights = [7, 3, 1];
    var sum = 0;
    for (var i = 0; i < value.length; i++) {
      sum += _charValue(value.codeUnitAt(i)) * weights[i % 3];
    }
    return sum % 10;
  }

  static int _charValue(int c) {
    if (c >= 48 && c <= 57) return c - 48;
    if (c >= 65 && c <= 90) return c - 55;
    return 0;
  }

  static bool _verify(String field, String check) {
    final digit = int.tryParse(_toDigit[check] ?? check);
    return digit != null && checkDigit(field) == digit;
  }

  /// Coerces [field] to its character class and, if the check digit still
  /// fails, tries look-alike swaps on at most six ambiguous positions.
  ({String field, String check, bool passed}) _repaired(
    String field,
    String check, {
    required bool numeric,
  }) {
    final fixedCheck = _toDigit[check] ?? check;
    final base = numeric ? _digits(field) : field;
    if (_verify(base, fixedCheck)) {
      return (
        field: numeric ? base : _preferDigits(base, fixedCheck),
        check: fixedCheck,
        passed: true,
      );
    }
    if (!numeric) {
      final positions = [
        for (var i = 0; i < base.length; i++)
          if (_swaps.containsKey(base[i])) i,
      ].take(6).toList();
      for (var mask = 1; mask < (1 << positions.length); mask++) {
        final chars = base.split('');
        for (var bit = 0; bit < positions.length; bit++) {
          if (mask & (1 << bit) != 0) {
            chars[positions[bit]] = _swaps[chars[positions[bit]]]!;
          }
        }
        final candidate = chars.join();
        if (_verify(candidate, fixedCheck)) {
          return (
            field: _preferDigits(candidate, fixedCheck),
            check: fixedCheck,
            passed: true,
          );
        }
      }
    }
    return (field: base, check: fixedCheck, passed: false);
  }

  /// The check digit cannot tell `OO` from `00` (weights 7 and 3 sum to 10),
  /// so in a mostly numeric field look-alike letters are read as digits.
  String _preferDigits(String field, String check) {
    final body = field.replaceAll('<', '');
    final digitCount = RegExp(r'\d').allMatches(body).length;
    if (body.isEmpty || digitCount * 2 < body.length) return field;
    final candidate = field
        .split('')
        .map((c) => 'OIZSB'.contains(c) ? _toDigit[c]! : c)
        .join();
    return _verify(candidate, check) ? candidate : field;
  }

  // ---------------------------------------------------------------- fields

  /// Forces [line] to [length]. A dropped or doubled filler character is the
  /// most common OCR length error, so when [stretchFiller] is set the longest
  /// `<` run absorbs the difference; that keeps every later field aligned.
  static String _fit(String line, int length, {required bool stretchFiller}) {
    var fitted = line;
    while (stretchFiller && fitted.length != length) {
      final run = RegExp('<+')
          .allMatches(fitted)
          .fold<RegExpMatch?>(null, (best, m) {
        return best == null || m.end - m.start > best.end - best.start
            ? m
            : best;
      });
      if (run == null) break;
      if (fitted.length < length) {
        fitted = fitted.replaceRange(run.start, run.start, '<');
      } else if (run.end - run.start >= 2) {
        fitted = fitted.replaceRange(run.start, run.start + 1, '');
      } else {
        break;
      }
    }
    if (fitted.length >= length) return fitted.substring(0, length);
    return fitted.padRight(length, '<');
  }

  static String _digits(String s) =>
      s.split('').map((c) => _toDigit[c] ?? c).join();

  static String _letters(String s) =>
      s.split('').map((c) => _toLetter[c] ?? c).join().replaceAll('<', '');

  static String _clean(String s) => s.replaceAll(RegExp(r'<+$'), '').replaceAll('<', ' ').trim();

  static String _sex(String c) => 'MFX'.contains(c) ? c : '';

  (String, String) _names(String field) {
    final trimmed = field.replaceAll(RegExp(r'<+$'), '');
    final split = trimmed.indexOf('<<');
    final surname = split == -1 ? trimmed : trimmed.substring(0, split);
    final given = split == -1 ? '' : trimmed.substring(split + 2);
    String tidy(String s) => _letters(s.replaceAll('<', ' '))
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return (tidy(surname.replaceAll('<', ' ')), tidy(given));
  }

  String _isoDate(String yymmdd, {required bool isBirth}) {
    if (!RegExp(r'^\d{6}$').hasMatch(yymmdd)) return yymmdd;
    final yy = int.parse(yymmdd.substring(0, 2));
    final month = int.parse(yymmdd.substring(2, 4));
    final day = int.parse(yymmdd.substring(4, 6));
    if (month < 1 || month > 12 || day < 1 || day > 31) return yymmdd;
    final currentYy = _clock().year % 100;
    final year = isBirth && yy > currentYy ? 1900 + yy : 2000 + yy;
    String two(int n) => n.toString().padLeft(2, '0');
    return '$year-${two(month)}-${two(day)}';
  }
}
