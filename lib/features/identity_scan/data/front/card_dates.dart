import 'package:mrz/features/identity_scan/data/front/parser_utils.dart';

/// Date reading shared by the ID card and passport parsers.
class CardDates {
  CardDates._();

  static final _ymd =
      RegExp(r'(?<!\d)(\d{4})\s*[/.-]\s*(\d{1,2})\s*[/.-]\s*(\d{1,2})(?!\d)');
  static final _dmy =
      RegExp(r'(?<!\d)(\d{1,2})\s*[/.-]\s*(\d{1,2})\s*[/.-]\s*(\d{4})(?!\d)');
  static final _dayMonthName = RegExp(
    r'(?<!\d)(\d{1,2})\s*[-/ ]?\s*(JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC)[A-Z]*\s*[-/ ]?\s*(\d{4})(?!\d)',
    caseSensitive: false,
  );
  static const _months = [
    'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
    'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
  ];

  /// Every plausible date in [text]: `yyyy/mm/dd`, `dd/mm/yyyy` (also with `-`
  /// or `.`) and `dd MMM yyyy`. Arabic-Indic digits are accepted.
  static List<DateTime> datesIn(String text) {
    final normalized = ParserUtils.normalizeDigits(text);
    final dates = <DateTime>[];
    for (final m in _ymd.allMatches(normalized)) {
      final date = _safeDate(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
      if (date != null) dates.add(date);
    }
    for (final m in _dmy.allMatches(normalized)) {
      var day = int.parse(m[1]!);
      var month = int.parse(m[2]!);
      if (month > 12 && day <= 12) (day, month) = (month, day);
      final date = _safeDate(int.parse(m[3]!), month, day);
      if (date != null) dates.add(date);
    }
    for (final m in _dayMonthName.allMatches(normalized)) {
      final month = _months.indexOf(m[2]!.toUpperCase()) + 1;
      final date = _safeDate(int.parse(m[3]!), month, int.parse(m[1]!));
      if (date != null) dates.add(date);
    }
    return dates;
  }

  static DateTime? _safeDate(int year, int month, int day) {
    if (year < 1900 || year > 2100 || month < 1 || month > 12 || day < 1 || day > 31) {
      return null;
    }
    final date = DateTime.utc(year, month, day);
    return date.month == month ? date : null; // rejects 31 February and the like
  }

  /// `yyyy/mm/dd`, the format the card parsers report.
  static String slashed(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

  /// ISO `yyyy-mm-dd`.
  static String iso(DateTime d) => slashed(d).replaceAll('/', '-');
}
