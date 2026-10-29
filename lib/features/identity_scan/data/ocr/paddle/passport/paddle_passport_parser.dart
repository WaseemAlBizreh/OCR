import 'package:mrz/features/identity_scan/data/front/card_dates.dart';
import 'package:mrz/features/identity_scan/data/front/parser_utils.dart';
import 'package:mrz/features/identity_scan/data/ocr/paddle/passport/country_names.dart';
import 'package:mrz/features/identity_scan/data/ocr/paddle/passport/passport_labels.dart';
import 'package:mrz/features/identity_scan/data/ocr/paddle/passport/passport_layout.dart';
import 'package:mrz/features/identity_scan/data/ocr/paddle/passport/passport_line.dart';
import 'package:mrz/features/identity_scan/domain/mrz_data.dart';

/// Printed fields read from a passport data page.
class PassportPage {
  const PassportPage(this.fields, this.warnings);

  final Map<String, String?> fields;
  final List<String> warnings;
}

class _Hit {
  const _Hit(this.field, this.line, this.inline);

  final PassportField field;
  final PassportLine line;

  /// Text after the label on the same line (up to the next label).
  final String inline;
}

/// Reads the printed (visual inspection) zone of any passport data page.
///
/// Labels are found with one worldwide dictionary ([PassportLabels]) and each
/// value is located from line positions ([PassportLayout]), so no layout or
/// country is assumed. The MRZ is the anchor: its validated dates identify the
/// printed ones and the issue date is found by elimination. Anything not
/// found stays null; the caller still has the MRZ.
class PaddlePassportParser {
  const PaddlePassportParser();

  static final _mrzLike = RegExp(r'^[A-Z0-9<]{30,}$');
  static final _directionMarks =
      RegExp(r'[\u200e\u200f\u061c\u202a-\u202e\u2066-\u2069]');
  static final _latinWord = RegExp(r"[A-Za-z][A-Za-z.\-']+");
  static final _arabicWord = RegExp(r'[ء-يٮ-ۓ]{2,}');
  static const _maxCandidates = 4;

  PassportPage parse(List<PassportLine> lines, {MrzData? mrz}) {
    final page = [
      for (final line in lines)
        if (!_isMrz(line.text)) line.withText(line.text.replaceAll(_directionMarks, '')),
    ];
    final hits = _hits(page);
    final labelLines = {for (final h in hits) h.line};
    final labelFields = {for (final h in hits) h.line: h.field};

    List<PassportLine> candidates(_Hit hit) => PassportLayout.valueCandidates(
          hit.line,
          page,
          labelLines,
          labelFields: labelFields,
        ).take(_maxCandidates).toList();

    // Texts to try for one field, in priority order: the rest of the label's
    // own line, then the nearby lines.
    Iterable<({String text, List<String> alts})> sources(PassportField field) sync* {
      for (final hit in hits.where((h) => h.field == field)) {
        yield (text: hit.inline, alts: const <String>[]);
        for (final c in candidates(hit)) {
          yield (text: c.text, alts: c.alts);
        }
      }
    }

    Iterable<String> texts(PassportField field) => sources(field).map((s) => s.text);

    DateTime? dateOf(PassportField field) {
      for (final text in texts(field)) {
        final dates = CardDates.datesIn(text);
        if (dates.isNotEmpty) return dates.first;
      }
      return null;
    }

    ({String? latin, String? arabic}) placeOf(PassportField field) {
      String? latin;
      String? arabic;
      for (final source in sources(field)) {
        final found = _latinValue(source.text);
        latin ??= found == null ? null : _repairLatin(found, source.alts);
        arabic ??= _arabicValue(source.text);
        if (latin != null && arabic != null) break;
      }
      return (latin: latin, arabic: arabic);
    }

    final (issue, dob, expiry) = _dates(
      page,
      labelled: (
        dob: dateOf(PassportField.birthDate),
        issue: dateOf(PassportField.issueDate),
        expiry: dateOf(PassportField.expiryDate),
      ),
      dobMrz: _mrzDate(mrz?.dateOfBirth),
      expiryMrz: _mrzDate(mrz?.expiryDate),
    );

    final birthPlace = placeOf(PassportField.birthPlace);
    final issuePlace = placeOf(PassportField.issuePlace);

    String? arabicName;
    for (final text in texts(PassportField.arabicName)) {
      arabicName ??= _arabicValue(text, minWords: 2);
    }

    String? nationalNumber;
    for (final text in texts(PassportField.nationalNumber)) {
      nationalNumber ??= _nationalNumber(text);
    }

    String? nationality;
    String? nationalityArabic;
    for (final text in texts(PassportField.nationality)) {
      nationality ??= _latinValue(text);
      nationalityArabic ??= _arabicValue(text);
    }
    // Some pages print the ICAO code (SDN) instead of the country name.
    if (nationality != null && RegExp(r'^[A-Z]{3}$').hasMatch(nationality)) {
      nationality = countryName(nationality) ?? nationality;
    }

    String? passportNumber;
    for (final text in texts(PassportField.passportNumber)) {
      passportNumber ??= _passportNumber(text);
    }

    final fields = <String, String?>{
      'passportNumber': passportNumber,
      'arabicName': arabicName,
      'nationalNumber': nationalNumber,
      'nationalityText': nationality,
      'nationalityTextArabic': nationalityArabic,
      'dateOfBirth': dob == null ? null : CardDates.slashed(dob),
      'placeOfBirth': birthPlace.latin,
      'placeOfBirthArabic': birthPlace.arabic,
      'issueDate': issue == null ? null : CardDates.slashed(issue),
      'placeOfIssue': issuePlace.latin,
      'placeOfIssueArabic': issuePlace.arabic,
      'expiryDate': expiry == null ? null : CardDates.slashed(expiry),
    };

    return PassportPage(
      fields,
      ParserUtils.collectWarnings(
        fields,
        const ['placeOfBirth', 'issueDate', 'placeOfIssue'],
      ),
    );
  }

  // ------------------------------------------------------------------ labels

  static bool _isMrz(String text) {
    if (text.contains('<')) return true;
    return _mrzLike.hasMatch(text.replaceAll(RegExp(r'\s+'), '').toUpperCase());
  }

  static List<_Hit> _hits(List<PassportLine> lines) {
    final hits = <_Hit>[];
    for (final line in lines) {
      final found = PassportLabels.hitsIn(line.text);
      if (found.isNotEmpty) {
        for (var i = 0; i < found.length; i++) {
          final end = i + 1 < found.length ? found[i + 1].start : line.text.length;
          final inline = line.text.substring(found[i].end, end).replaceAll(RegExp(r'^[\s:\-./]+'), '');
          hits.add(_Hit(found[i].field, line, inline));
        }
        continue;
      }
      // The title may be garbled in this reading but fine in the other
      // engine's (alts), or in the other language of a bilingual title.
      // Nothing after a fuzzy label is trusted as an inline value.
      final fuzzy = PassportLabels.fuzzyHit(line.text) ?? _labelInAlts(line);
      if (fuzzy != null) hits.add(_Hit(fuzzy.field, line, ''));
    }
    // Reading order, so the first hit of a field is the topmost one.
    hits.sort((a, b) {
      final dy = a.line.centerY - b.line.centerY;
      return dy.abs() < a.line.height * 0.6 ? a.line.left.compareTo(b.line.left) : dy.sign.toInt();
    });
    return hits;
  }

  static PassportLabelHit? _labelInAlts(PassportLine line) {
    for (final alt in line.alts) {
      final exact = PassportLabels.hitsIn(alt);
      if (exact.isNotEmpty) return exact.first;
    }
    for (final alt in line.alts) {
      final fuzzy = PassportLabels.fuzzyHit(alt);
      if (fuzzy != null) return fuzzy;
    }
    return null;
  }

  // ------------------------------------------------------------------ values

  /// Upper-cased Latin words of [text] that are not label words.
  static String? _latinValue(String text) {
    // Values are printed in capitals; lower-case fragments next to them are
    // noise (an Arabic word or label read as Latin letters).
    final tokens = _latinWord.allMatches(text).map((m) => m.group(0)!).toList();
    final capitals = tokens.where((w) => w == w.toUpperCase()).toList();
    final words = (capitals.isNotEmpty ? capitals : tokens)
        .map((w) => w.toUpperCase().replaceAll(RegExp(r"^[.\-']+|[.\-']+$"), ''))
        .where((w) => w.length >= 2 && !PassportLabels.latinLabelWords.contains(w))
        .toList();
    return words.isEmpty ? null : words.join(' ');
  }

  /// Paddle sometimes cuts the last letter of a Latin word (`OMDURMA`) while
  /// ML Kit reads it whole but glues a stray `I` or `L` (an Arabic letter it
  /// cannot read) to the end (`OMDURMANI`). When the other reading extends this
  /// one by one or two characters and ends in such a letter, the word is the
  /// other reading without it.
  static String _repairLatin(String latin, List<String> alts) {
    if (alts.isEmpty) return latin;
    final altWords = [
      for (final alt in alts) ...RegExp(r'[A-Z]{4,}').allMatches(alt).map((m) => m.group(0)!),
    ];
    return latin.split(' ').map((word) {
      if (word.length < 4) return word;
      for (final other in altWords) {
        final extra = other.length - word.length;
        if (extra < 1 || extra > 2 || !other.startsWith(word)) continue;
        final trimmed = other.replaceFirst(RegExp(r'[IL]+$'), '');
        if (trimmed.length > word.length && trimmed.startsWith(word) && trimmed.length < other.length) {
          return trimmed;
        }
      }
      return word;
    }).join(' ');
  }

  static String? _arabicValue(String text, {int minWords = 1}) {
    final words = _arabicWord
        .allMatches(text)
        .map((m) => ParserUtils.normalizeArabic(m.group(0)!))
        .where((w) => !PassportLabels.arabicLabelWords.contains(w))
        .toList();
    return words.length >= minWords ? words.join(' ') : null;
  }

  /// A national number is a long digit run (spaces and hyphens allowed) that
  /// is not a date.
  static String? _nationalNumber(String text) {
    if (CardDates.datesIn(text).isNotEmpty) return null;
    final compact = ParserUtils.normalizeDigits(text).replaceAll(RegExp(r'[\s\-]'), '');
    final match = RegExp(r'(?<!\d)\d{8,16}(?!\d)').firstMatch(compact);
    return match?.group(0);
  }

  /// A passport number mixes letters and digits and has at least one digit.
  static String? _passportNumber(String text) {
    for (final m in RegExp(r'(?<![A-Z0-9])[A-Z0-9]{6,9}(?![A-Z0-9])').allMatches(text.toUpperCase())) {
      final value = m.group(0)!;
      if (RegExp(r'\d').hasMatch(value)) return value;
    }
    return null;
  }

  // ------------------------------------------------------------------- dates

  static DateTime? _mrzDate(String? iso) {
    final parsed = iso == null ? null : DateTime.tryParse(iso);
    return parsed == null ? null : DateTime.utc(parsed.year, parsed.month, parsed.day);
  }

  /// (issue, dateOfBirth, expiry) as printed.
  ///
  /// The MRZ dates are validated, so a printed date equal to one of them is
  /// that date whatever its label was read as; the issue date is the printed
  /// date strictly between them.
  static (DateTime?, DateTime?, DateTime?) _dates(
    List<PassportLine> lines, {
    required ({DateTime? dob, DateTime? issue, DateTime? expiry}) labelled,
    DateTime? dobMrz,
    DateTime? expiryMrz,
  }) {
    final all = {
      for (final line in lines) ...CardDates.datesIn(line.text),
    }.toList()
      ..sort();

    var dob = labelled.dob;
    var expiry = labelled.expiry;
    var issue = labelled.issue;
    if (dobMrz != null && all.contains(dobMrz)) dob = dobMrz;
    if (expiryMrz != null && all.contains(expiryMrz)) expiry = expiryMrz;

    // No MRZ to anchor on: the earliest date is the birth date and the latest
    // the expiry date, which leaves the ones in between for the issue date.
    final noMrz = dobMrz == null && expiryMrz == null;
    if (noMrz && all.length >= 3) {
      dob ??= all.first;
      expiry ??= all.last;
    }

    final lowerBound = dobMrz ?? dob;
    final upperBound = expiryMrz ?? expiry;
    final candidates = all.where((d) {
      if (d == dob || d == expiry) return false;
      if (lowerBound != null && !d.isAfter(lowerBound)) return false;
      if (upperBound != null && !d.isBefore(upperBound)) return false;
      return true;
    }).toList();

    final labelledIssueOk = issue != null &&
        (lowerBound == null || issue.isAfter(lowerBound)) &&
        (upperBound == null || issue.isBefore(upperBound));
    if (!labelledIssueOk) {
      issue = switch (candidates.length) {
        0 => null,
        1 => candidates.first,
        _ => _closestToValidity(candidates, upperBound),
      };
    }

    return (issue, dob, expiry);
  }

  /// Passports are valid for a whole number of years (typically 5 or 10), so
  /// among several candidates the one that fits is the issue date.
  static DateTime _closestToValidity(List<DateTime> candidates, DateTime? expiry) {
    if (expiry != null) {
      for (final candidate in candidates.reversed) {
        final years = expiry.difference(candidate).inDays / 365.25;
        if ((years - years.round()).abs() < 0.03 && years.round() >= 1) return candidate;
      }
    }
    return candidates.last;
  }
}
