import 'package:mrz/features/identity_scan/data/front/parser_utils.dart';
import 'package:mrz/features/identity_scan/data/front/sudan_card_parser.dart'
    show CardFields;

/// Parser for the Sudan ID card text produced by the Paddle engine.
///
/// Independent of the classic [SudanCardParser]: Paddle returns one clean line
/// per text box, so every field is read from its own labelled line, values are
/// validated by shape (an 11-digit national number is digits, a blood type is
/// `A/B/AB/O` with a sign), and a missing value stays `null` instead of
/// borrowing the next line.
class PaddleSudanCardParser {
  const PaddleSudanCardParser();

  static const _digit = r'[0-9٠-٩۰-۹]';

  static final _label = {
    'name': RegExp(
      r'(?<![\u0600-\u06FF])[اإأآ]{1,2}\u0640*ل?[اإأآ]?\u0640*سم(?![\u0600-\u06FF])',
    ),
    'dob': _labelRegex('تاريخ الميلاد'),
    'birthPlace': _labelRegex('مكان الميلاد'),
    'national': _labelRegex('الرقم الوطني'),
    'blood': _labelRegex('فصيلة الدم'),
    'profession': _labelRegex('المهنة'),
    'address': _labelRegex('العنوان'),
    // The ":" printed after the label is often read as a last letter, so
    // الإصدار comes out as الإصدان (also ز/د/ا).
    'issuePlace': RegExp(r'مكان\s*ال[اإأآ]\u0640*صدا[رنزدا]?'),
  };

  /// Words that mark a line as something other than a name or address value.
  static final _stopWords = RegExp(
    '${_labelRegex('سلطة الاصدار').pattern}|لواء|شرطة|شرطه|جمهورية|وزارة|الداخلية|بطاقة|اثبات|الشخصية|السودان',
  );

  static final _nationalNumber = RegExp('(?<!$_digit)$_digit{11}(?!$_digit)');
  static final _ymd = RegExp(r'(\d{4})\s*[/.\-]\s*(\d{1,2})\s*[/.\-]\s*(\d{1,2})');
  static final _dmy = RegExp(r'(\d{1,2})\s*[/.\-]\s*(\d{1,2})\s*[/.\-]\s*(\d{4})');
  static final _mrzLike = RegExp(r'^[A-Z0-9<\s]{20,}$');

  /// Matches [label] however OCR spelled the alef, ya, ta marbuta or tatweel.
  static RegExp _labelRegex(String label) {
    final buffer = StringBuffer();
    for (final rune in label.runes) {
      final c = String.fromCharCode(rune);
      buffer.write(switch (c) {
        ' ' => r'\s*',
        'ا' || 'إ' || 'أ' || 'آ' => '[اإأآ]ـ*',
        'ي' || 'ى' => '[يى]ـ*',
        'ة' || 'ه' => '[ةه]ـ*',
        _ => '$cـ*',
      });
    }
    return RegExp(buffer.toString());
  }

  CardFields parseFront(String ocrText) {
    final lines = ParserUtils.rawLines(ocrText);

    final dobLine = _indexOf(lines, _label['dob']!);
    final fields = <String, String?>{
      'arabicName': _name(lines, dobLine),
      'nationalNumber': _nationalNumberOf(lines),
      'dateOfBirth': _dateOfBirth(lines),
      'placeOfBirth': _arabicValue(lines, _label['birthPlace']!),
      'bloodType': _bloodType(lines),
      'profession': _arabicValue(lines, _label['profession']!),
      'address': _address(lines),
      'phone': _phoneOf(lines),
    };

    final phone = fields['phone'];
    return CardFields(
      fields: fields,
      warnings: [
        ...ParserUtils.collectWarnings(
          fields,
          const ['arabicName', 'nationalNumber'],
        ),
        if (phone != null && phone.length != 10)
          'Phone number may be incomplete (${phone.length} digits read).',
      ],
    );
  }

  CardFields parseBack(String ocrText) {
    final lines = ParserUtils.rawLines(ocrText)
        .where((line) => !line.contains('<') && !_mrzLike.hasMatch(line))
        .toList();

    // The back also prints the date of birth, and Paddle often places it right
    // after the issue/expiry labels, so labels cannot be trusted to pick the
    // date. The two most recent distinct dates are issue and expiry; the date
    // of birth is always the oldest.
    final all = {for (final line in lines) ..._datesIn(line)}.toList()..sort();
    final issue = all.length >= 2 ? all[all.length - 2] : null;
    final expiry = all.length >= 2 ? all.last : null;

    final fields = <String, String?>{
      'placeOfIssue': _arabicValue(lines, _label['issuePlace']!),
      'issueDate': issue == null ? null : _format(issue),
      'expiryDate': expiry == null ? null : _format(expiry),
    };
    return CardFields(fields: fields, warnings: const []);
  }

  // ---- fields -------------------------------------------------------------

  String? _name(List<String> lines, int dobLine) {
    final labelled = _arabicValue(lines, _label['name']!, minWords: 2);
    if (labelled != null) return labelled;

    // Label lost: the name is the first multi-word Arabic line above the date
    // of birth that is not a heading or another field.
    final end = dobLine == -1 ? lines.length : dobLine;
    for (var i = 0; i < end; i++) {
      final line = lines[i];
      if (_stopWords.hasMatch(line) || _isAnyLabel(line)) continue;
      final value = _cleanArabic(line);
      if (value != null && value.split(' ').length >= 3) return value;
    }
    return null;
  }

  String? _nationalNumberOf(List<String> lines) {
    final labelled = _indexOf(lines, _label['national']!);
    if (labelled != -1) {
      final match = _nationalNumber.firstMatch(lines[labelled]);
      if (match != null) return ParserUtils.normalizeDigits(match[0]!);
    }
    for (final line in lines) {
      final match = _nationalNumber.firstMatch(line);
      if (match != null) return ParserUtils.normalizeDigits(match[0]!);
    }
    return null;
  }

  String? _dateOfBirth(List<String> lines) {
    final labelled = _indexOf(lines, _label['dob']!);
    if (labelled != -1) {
      final date = _datesIn(lines[labelled]).firstOrNull;
      if (date != null) return _format(date);
    }
    for (final line in lines) {
      final date = _datesIn(line).firstOrNull;
      if (date != null) return _format(date);
    }
    return null;
  }

  /// `A+`, `O-`, `AB+`... The value is often its own text box (and can come
  /// from the Latin pass), so after the label's own line, short lines with no
  /// Arabic are tried. The sign can come out on either side of the letter, and
  /// OCR may read `O` as `0`.
  String? _bloodType(List<String> lines) {
    final labelled = _indexOf(lines, _label['blood']!);
    final candidates = [
      if (labelled != -1) lines[labelled].replaceFirst(_label['blood']!, ''),
      ...lines.where(
        (l) => !l.contains(RegExp(r'[\u0600-\u06FF]')) && l.trim().length <= 8,
      ),
    ];

    for (final raw in candidates) {
      final text = raw.toUpperCase().replaceAllMapped(
            RegExp(r'0(?=\s*[+\-])|(?<=[+\-]\s*)0'),
            (_) => 'O',
          );
      final after = RegExp(r'(?<![A-Z])(AB|A|B|O)\s*([+\-])').firstMatch(text);
      if (after != null) return '${after[1]}${after[2]}';
      final before = RegExp(r'([+\-])\s*(AB|A|B|O)(?![A-Z])').firstMatch(text);
      if (before != null) return '${before[2]}${before[1]}';
    }
    return null;
  }

  /// The address is the text after its label on the same line (minus the phone
  /// part) or, failing that, the first real Arabic line below it. Paddle sorts
  /// boxes by height, so the issuing-authority block can sit between the label
  /// and the address: such lines are skipped, not treated as the end.
  String? _address(List<String> lines) {
    final start = _indexOf(lines, _label['address']!);
    if (start == -1) return null;

    final sameLine = _cleanArabic(
      _withoutPhone(lines[start].replaceFirst(_label['address']!, '')),
    );
    if (sameLine != null && !_stopWords.hasMatch(sameLine)) return sameLine;

    final end = (start + 5).clamp(0, lines.length);
    for (var i = start + 1; i < end; i++) {
      final line = lines[i];
      if (_stopWords.hasMatch(line) || _isAnyLabel(line)) continue;
      final value = _cleanArabic(_withoutPhone(line));
      // Short fragments are stamp text or noise, not an address.
      if (value != null && value.replaceAll(RegExp(r'[\s\-]'), '').length >= 6) {
        return value;
      }
    }
    return null;
  }

  /// The phone: the digits printed after `ت/` on the address row, after the
  /// word العنوان. It is the only number the card prints in Arabic-Indic digits,
  /// so any line carrying a run of those digits is the phone row even when the
  /// label or the `ت/` came out garbled. Whatever digits were read are
  /// returned (a wrong count is flagged by [parseFront], not hidden).
  String? _phoneOf(List<String> lines) {
    final marked = RegExp(r'ت\s*/|/\s*ت|هاتف|tel', caseSensitive: false);
    final labelled = lines.where(
      (l) => marked.hasMatch(l) || _label['address']!.hasMatch(l),
    );

    for (final line in [...labelled, ...lines]) {
      final text = line.replaceFirst(_label['address']!, '');

      var digits = ParserUtils.normalizeDigits(
        text.replaceAll(RegExp(r'[^٠-٩۰-۹]'), ''),
      );
      // Latin digits only count on a line known to be the address row, and
      // never an 11-digit run (that is the national number).
      if (digits.length < 6 && labelled.contains(line)) {
        final latin = text.replaceAll(RegExp('[Oo]'), '0').replaceAll(RegExp(r'\D'), '');
        if (latin.length >= 6 && latin.length != 11) digits = latin;
      }
      if (digits.length < 6) continue;

      // The leading 0 is a small dot and the digit most often lost; the `/`
      // is sometimes read as an extra trailing 1.
      if (digits.length == 9 && '19'.contains(digits[0])) digits = '0$digits';
      if (digits.length > 10 && digits.startsWith('0')) digits = digits.substring(0, 10);
      // Ten digits without the leading 0: the 0 was lost and the `/` was read
      // as a trailing digit, which is how Paddle misreads this row.
      if (digits.length == 10 && '19'.contains(digits[0])) {
        digits = '0${digits.substring(0, 9)}';
      }
      return digits;
    }
    return null;
  }

  // ---- helpers ------------------------------------------------------------

  String? _arabicValue(List<String> lines, RegExp label, {int minWords = 1}) {
    final index = _indexOf(lines, label);
    if (index == -1) return null;
    final value = _cleanArabic(lines[index].replaceFirst(label, ''));
    if (value == null || value.split(' ').length < minWords) return null;
    return value;
  }

  int _indexOf(List<String> lines, RegExp label) =>
      lines.indexWhere(label.hasMatch);

  bool _isAnyLabel(String line) => _label.values.any((l) => l.hasMatch(line));

  /// Arabic letters and single dashes only, tidy spacing; `null` when nothing
  /// meaningful is left.
  String? _cleanArabic(String text) {
    final cleaned = text
        .replaceAll('ـ', '')
        .replaceAll(RegExp(r'[،؛؟]'), ' ')
        .replaceAll(RegExp(r'[^؀-ۿ\s\-]'), ' ')
        .replaceAll(RegExp(r'[٠-٩۰-۹]'), ' ')
        .replaceAll(RegExp(r'\s*-\s*'), ' - ')
        .replaceAll(RegExp(r'^[\s\-]+|[\s\-]+$'), '')
        .replaceAll(RegExp(r'\s+'), ' ');
    final letters = cleaned.replaceAll(RegExp(r'[\s\-]'), '');
    return letters.length >= 2 ? cleaned : null;
  }

  String _withoutPhone(String text) => text
      .replaceAll(RegExp('ت\\s*/?\\s*[0-9٠-٩۰-۹][\\s0-9٠-٩۰-۹]*'), ' ')
      .replaceAll(RegExp('[0-9٠-٩۰-۹][\\s0-9٠-٩۰-۹]*/\\s*ت'), ' ');

  List<DateTime> _datesIn(String line) {
    final text = ParserUtils.normalizeDigits(line);
    final result = <DateTime>[];
    for (final m in _ymd.allMatches(text)) {
      _add(result, m[1]!, m[2]!, m[3]!);
    }
    for (final m in _dmy.allMatches(text)) {
      _add(result, m[3]!, m[2]!, m[1]!);
    }
    return result;
  }

  void _add(List<DateTime> into, String y, String m, String d) {
    final year = int.parse(y), month = int.parse(m), day = int.parse(d);
    if (year < 1900 || year > 2100 || month < 1 || month > 12) return;
    if (day < 1 || day > 31) return;
    into.add(DateTime(year, month, day));
  }

  String _format(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
}
