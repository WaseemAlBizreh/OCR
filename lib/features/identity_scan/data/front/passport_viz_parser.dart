import 'package:mrz/features/identity_scan/data/front/card_dates.dart';
import 'package:mrz/features/identity_scan/data/front/parser_utils.dart';
import 'package:mrz/features/identity_scan/data/front/sudan_card_parser.dart';
import 'package:mrz/features/identity_scan/domain/mrz_data.dart';

/// Reads the printed (visual inspection) zone of a passport data page.
///
/// The MRZ has no place of birth, issue date or place of issue; they exist
/// only as printed text, in English and Arabic. The MRZ is still the anchor:
/// its date of birth and expiry date are known and validated, so the issue
/// date is found by elimination even when its label is garbled.
class PassportVizParser {
  const PassportVizParser();

  static final _nationalHyphenated =
      RegExp(r'(?<!\d)\d{3}\s*-\s*\d{4}\s*-\s*\d{4}(?!\d)');
  static final _eleven = RegExp(r'(?<!\d)\d{11}(?!\d)');
  static final _passportNumber = RegExp(r'(?<![A-Z0-9])P\d{8}(?![0-9])');

  /// Words that belong to labels, never to a value.
  static const _labelWords = {
    'PLACE', 'OF', 'BIRTH', 'DATE', 'ISSUE', 'ISSUED', 'EXPIRY', 'EXPIRES',
    'SEX', 'NATIONALITY', 'NATIONAL', 'NUMBER', 'SURNAME', 'GIVEN', 'NAMES',
    'NAME', 'PASSPORT', 'NO', 'TYPE', 'CODE', 'FULL', 'AUTHORITY', 'ISSUING',
    'COUNTRY', 'HOLDER', 'SIGNATURE', 'ID', 'THE', 'REPUBLIC',
  };
  static const _arabicLabelWords = {
    'مكان', 'الميلاد', 'الاصدار', 'اصدار', 'جهة', 'سلطة', 'تاريخ', 'الجنسية',
    'الاسم', 'الكامل', 'الرقم', 'الوطني', 'الصلاحية', 'الانتهاء', 'الجواز',
  };

  // Label patterns tolerate the usual OCR substitutions (O/0, I/1/L, S/5, B/8).
  static final _dobLabel = _label('DATE OF BIRTH');
  static final _issueLabel = RegExp(
    '${_label('DATE OF ISSUE').pattern}|${_label('ISSUE DATE').pattern}',
    caseSensitive: false,
  );
  static final _expiryLabel = RegExp(
    '${_label('DATE OF EXPIRY').pattern}|${_label('EXPIRY DATE').pattern}',
    caseSensitive: false,
  );
  static final _birthPlaceLabel = _label('PLACE OF BIRTH');
  static final _issuePlaceLabel = RegExp(
    '${_label('PLACE OF ISSUE').pattern}|${_label('ISSUING AUTHORITY').pattern}|${_label('AUTHORITY').pattern}',
    caseSensitive: false,
  );
  static final _nationalLabel = RegExp(
    '${_label('NATIONAL NO').pattern}|${_label('NATIONAL NUMBER').pattern}|${_label('NATIONAL ID').pattern}',
    caseSensitive: false,
  );
  static final _nationalityLabel = _label('NATIONALITY');

  static RegExp _label(String text) {
    const alternatives = {
      'O': '[O0]', 'I': '[I1L]', 'L': '[L1I]', 'S': '[S5]', 'B': '[B8]',
    };
    final pattern = text.split('').map((c) {
      if (c == ' ') return r'\s*';
      return alternatives[c] ?? c;
    }).join();
    return RegExp(pattern, caseSensitive: false);
  }

  static const _dobArabic = ['تاريخ الميلاد'];
  static const _issueArabic = ['تاريخ الاصدار', 'تاريخ الإصدار'];
  static const _expiryArabic = ['تاريخ الصلاحية', 'تاريخ الانتهاء'];
  static const _birthPlaceArabic = ['مكان الميلاد'];
  static const _issuePlaceArabic = ['مكان الاصدار', 'مكان الإصدار', 'جهة الاصدار', 'جهة الإصدار', 'سلطة الاصدار'];
  static const _nationalArabic = ['الرقم الوطني'];
  static const _nationalityArabic = ['الجنسية'];
  static const _nameArabic = ['الاسم الكامل', 'الاسم'];

  CardFields parse(String ocrText, {MrzData? mrz}) {
    final lines = ParserUtils.rawLines(_stripMarks(ocrText))
        .where((line) => !line.contains('<')) // MRZ lines
        .toList();
    final text = lines.join('\n');

    final dobMrz = _mrzDate(mrz?.dateOfBirth);
    final expiryMrz = _mrzDate(mrz?.expiryDate);
    final (issue, printedDob, printedExpiry) = _dates(
      lines,
      text,
      dobMrz: dobMrz,
      expiryMrz: expiryMrz,
    );

    final birthPlace = _place(lines, _birthPlaceLabel, _birthPlaceArabic);
    final issuePlace = _place(lines, _issuePlaceLabel, _issuePlaceArabic);

    final fields = <String, String?>{
      'passportNumber': _passportNumber.firstMatch(text.toUpperCase())?.group(0),
      'arabicName': _arabicName(lines),
      'nationalNumber': _nationalNumber(lines, text),
      'nationalityText': _nationalityText(lines),
      'dateOfBirth': printedDob == null ? null : CardDates.slashed(printedDob),
      'placeOfBirth': birthPlace.english,
      'placeOfBirthArabic': birthPlace.arabic,
      'issueDate': issue == null ? null : CardDates.slashed(issue),
      'placeOfIssue': issuePlace.english,
      'placeOfIssueArabic': issuePlace.arabic,
      'expiryDate': printedExpiry == null ? null : CardDates.slashed(printedExpiry),
    };

    return CardFields(
      fields: fields,
      warnings: ParserUtils.collectWarnings(
        fields,
        const ['placeOfBirth', 'issueDate', 'placeOfIssue'],
      ),
    );
  }

  // ------------------------------------------------------------------ dates

  /// (issue, dateOfBirth, expiry) as printed.
  (DateTime?, DateTime?, DateTime?) _dates(
    List<String> lines,
    String text, {
    DateTime? dobMrz,
    DateTime? expiryMrz,
  }) {
    final all = CardDates.datesIn(text).toSet().toList()..sort();

    var dob = _dateNear(lines, _dobLabel, _dobArabic);
    var expiry = _dateNear(lines, _expiryLabel, _expiryArabic);
    var issue = _dateNear(lines, _issueLabel, _issueArabic);

    // The MRZ dates are validated, so a printed date equal to one of them is
    // that date, whatever its label was read as.
    if (dobMrz != null && all.contains(dobMrz)) dob = dobMrz;
    if (expiryMrz != null && all.contains(expiryMrz)) expiry = expiryMrz;

    final lowerBound = dobMrz ?? dob;
    final upperBound = expiryMrz ?? expiry;
    final candidates = all.where((d) {
      if (d == dob || d == expiry) return false;
      if (lowerBound != null && !d.isAfter(lowerBound)) return false;
      if (upperBound != null && !d.isBefore(upperBound)) return false;
      return true;
    }).toList();

    final labeledIssueOk = issue != null &&
        (lowerBound == null || issue.isAfter(lowerBound)) &&
        (upperBound == null || issue.isBefore(upperBound));
    if (!labeledIssueOk) {
      issue = switch (candidates.length) {
        0 => null,
        1 => candidates.first,
        _ => _closestToValidity(candidates, upperBound),
      };
    }

    // Without an MRZ and without labels the order is all there is: date of
    // birth, issue date, expiry date.
    if (mrzAbsent(dobMrz, expiryMrz) && all.length >= 3) {
      dob ??= all.first;
      expiry ??= all.last;
      issue ??= all.length == 3 ? all[1] : null;
    }
    return (issue, dob, expiry);
  }

  static bool mrzAbsent(DateTime? dob, DateTime? expiry) => dob == null && expiry == null;

  /// Passports are valid for a whole number of years (typically 5 or 10), so
  /// among several candidates the one that fits is the issue date.
  DateTime _closestToValidity(List<DateTime> candidates, DateTime? expiry) {
    if (expiry != null) {
      for (final candidate in candidates.reversed) {
        final days = expiry.difference(candidate).inDays;
        final years = days / 365.25;
        if ((years - years.round()).abs() < 0.03 && years.round() >= 1) return candidate;
      }
    }
    return candidates.last;
  }

  DateTime? _dateNear(List<String> lines, RegExp english, List<String> arabic) {
    final index = _labelIndex(lines, english, arabic);
    if (index == -1) return null;
    for (final line in lines.skip(index).take(2)) {
      final dates = CardDates.datesIn(line);
      if (dates.isNotEmpty) return dates.first;
    }
    return null;
  }

  static DateTime? _mrzDate(String? iso) {
    final parsed = iso == null ? null : DateTime.tryParse(iso);
    return parsed == null ? null : DateTime.utc(parsed.year, parsed.month, parsed.day);
  }

  // ----------------------------------------------------------------- places

  ({String? english, String? arabic}) _place(
    List<String> lines,
    RegExp english,
    List<String> arabic,
  ) {
    final index = _labelIndex(lines, english, arabic);
    if (index == -1) return (english: null, arabic: null);

    String? latin;
    String? arabicValue;
    for (var i = index; i < lines.length && i <= index + 1; i++) {
      var line = lines[i];
      if (i > index && _looksLikeLabelLine(line)) break;
      if (i == index) line = line.replaceAll(english, ' ');
      latin ??= _latinValue(line);
      arabicValue ??= _arabicValue(line);
    }
    return (english: latin, arabic: arabicValue);
  }

  /// Upper-cased Latin words of [line] that are not label words.
  static String? _latinValue(String line) {
    final words = RegExp(r'[A-Za-z][A-Za-z.\-]+')
        .allMatches(line)
        .map((m) => m.group(0)!.toUpperCase())
        .where((w) => w.length >= 2 && !_labelWords.contains(w.replaceAll(RegExp(r'[.\-]'), '')))
        .toList();
    return words.isEmpty ? null : words.join(' ');
  }

  static String? _arabicValue(String line, {int minWords = 1}) {
    final words = RegExp(r'[ء-يٮ-ۓ]{2,}')
        .allMatches(line)
        .map((m) => ParserUtils.normalizeArabic(m.group(0)!))
        .where((w) => !_arabicLabelWords.contains(w))
        .toList();
    return words.length >= minWords ? words.join(' ') : null;
  }

  // ------------------------------------------------------------ other fields

  String? _arabicName(List<String> lines) {
    final index = _labelIndex(lines, RegExp(r'FULL\s*NAME', caseSensitive: false), _nameArabic);
    if (index == -1) return null;
    for (final line in lines.skip(index).take(2)) {
      final value = _arabicValue(line, minWords: 2);
      if (value != null) return value;
    }
    return null;
  }

  String? _nationalityText(List<String> lines) {
    final index = _labelIndex(lines, _nationalityLabel, _nationalityArabic);
    if (index == -1) return null;
    for (final line in lines.skip(index).take(2)) {
      final value = _latinValue(line.replaceAll(_nationalityLabel, ' '));
      if (value != null) return value;
    }
    return null;
  }

  /// Sudanese national numbers are printed `123-4567-8901` (11 digits).
  String? _nationalNumber(List<String> lines, String text) {
    final digits = ParserUtils.normalizeDigits(text);
    final hyphenated = _nationalHyphenated.firstMatch(digits);
    if (hyphenated != null) return hyphenated[0]!.replaceAll(RegExp(r'\D'), '');

    final index = _labelIndex(lines, _nationalLabel, _nationalArabic);
    if (index != -1) {
      for (final line in lines.skip(index).take(2)) {
        final match = _eleven.firstMatch(ParserUtils.normalizeDigits(line).replaceAll(RegExp(r'[\s-]'), ''));
        if (match != null) return match[0];
      }
    }
    return _eleven.firstMatch(digits)?.group(0);
  }

  // ---------------------------------------------------------------- helpers

  int _labelIndex(List<String> lines, RegExp english, List<String> arabic) {
    final arabicNeedles = arabic.map(ParserUtils.normalizeForParsing).toList();
    return lines.indexWhere((line) {
      if (english.hasMatch(line)) return true;
      final normalized = ParserUtils.normalizeForParsing(line);
      return arabicNeedles.any(normalized.contains);
    });
  }

  static bool _looksLikeLabelLine(String line) {
    final upper = line.toUpperCase();
    return RegExp(r'PLACE\s*OF|DATE\s*OF|NATIONAL|SURNAME|GIVEN|SEX|AUTHORITY|PASSPORT')
            .hasMatch(upper) ||
        RegExp(r'مكان|تاريخ|الجنسية|الرقم').hasMatch(ParserUtils.normalizeForParsing(line));
  }

  static final _directionMarks =
      RegExp(r'[\u200e\u200f\u061c\u202a-\u202e\u2066-\u2069]');

  static String _stripMarks(String text) => text.replaceAll(_directionMarks, '');
}
