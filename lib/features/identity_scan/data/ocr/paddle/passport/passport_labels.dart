/// Printed fields of a passport data page that the parser looks for.
///
/// [other] holds labels that are not read but must still be recognised as
/// labels, so a label line is never mistaken for a value.
enum PassportField {
  arabicName,
  birthDate,
  birthPlace,
  issueDate,
  issuePlace,
  expiryDate,
  nationality,
  nationalNumber,
  passportNumber,
  other,
}

/// A label found in a line of text.
class PassportLabelHit {
  const PassportLabelHit(this.field, this.start, this.end);

  final PassportField field;
  final int start;
  final int end;
}

/// One label dictionary for every country.
///
/// ICAO 9303 puts English (or French) labels on every data page, and Arabic
/// labels are added by Arab-world issuers, so these spellings cover passports
/// without knowing the issuing country.
class PassportLabels {
  PassportLabels._();

  static const _labels = <PassportField, List<String>>{
    PassportField.arabicName: [
      'FULL NAME', 'NAME', 'الاسم الكامل', 'الاسم',
    ],
    PassportField.birthDate: [
      'DATE OF BIRTH', 'BIRTH DATE', 'DATE DE NAISSANCE', 'تاريخ الميلاد', 'تاريخ الولادة',
    ],
    PassportField.birthPlace: [
      'PLACE OF BIRTH', 'LIEU DE NAISSANCE', 'مكان الميلاد', 'مكان الولادة',
    ],
    PassportField.issueDate: [
      'DATE OF ISSUE', 'ISSUE DATE', 'DATE DE DELIVRANCE', 'تاريخ الاصدار', 'تاريخ الإصدار',
    ],
    PassportField.issuePlace: [
      'PLACE OF ISSUE', 'ISSUING AUTHORITY', 'AUTHORITY', 'AUTORITE',
      'مكان الاصدار', 'مكان الإصدار', 'جهة الاصدار', 'جهة الإصدار', 'سلطة الاصدار', 'سلطة الإصدار',
    ],
    PassportField.expiryDate: [
      'DATE OF EXPIRY', 'EXPIRY DATE', 'DATE OF EXPIRATION', "DATE D'EXPIRATION",
      'تاريخ الانتهاء', 'تاريخ الصلاحية', 'تاريخ انتهاء الصلاحية',
    ],
    PassportField.nationality: [
      'NATIONALITY', 'NATIONALITE', 'الجنسية',
    ],
    PassportField.nationalNumber: [
      'NATIONAL NO', 'NATIONAL NUMBER', 'NATIONAL ID NO', 'NATIONAL ID', 'ID NUMBER',
      'الرقم الوطني', 'الرقم القومي',
    ],
    PassportField.passportNumber: [
      'PASSPORT NO', 'PASSPORT NUMBER', 'رقم الجواز', 'رقم جواز السفر',
    ],
    PassportField.other: [
      'SURNAME', 'GIVEN NAMES', 'GIVEN NAME', 'SEX', 'GENDER', 'TYPE', 'PASSPORT TYPE',
      'COUNTRY CODE', 'CODE', 'HOLDER', 'SIGNATURE', 'PASSPORT', 'PERSONAL NO',
      'الجنس', 'النوع', 'اللقب', 'رمز الدولة', 'جواز سفر', 'التوقيع',
    ],
  };

  static final _compiled = <(PassportField, RegExp)>[
    for (final entry in _labels.entries)
      for (final label in entry.value) (entry.key, _compile(label)),
  ];

  static final _arabicLetter = RegExp(r'[؀-ۿ]');

  /// Matches [label] as a whole word, however OCR spelled the look-alike
  /// letters (O/0, I/1, S/5, B/8) or the Arabic alef, ya, ta marbuta, tatweel.
  static RegExp _compile(String label) {
    final buffer = StringBuffer();
    for (final rune in label.runes) {
      final c = String.fromCharCode(rune);
      buffer.write(switch (c) {
        ' ' => r'\s*',
        "'" => '[\'’]?',
        'O' => '[O0]',
        'I' => '[I1L]',
        'L' => '[L1I]',
        'S' => '[S5]',
        'B' => '[B8]',
        'ا' || 'إ' || 'أ' || 'آ' => '[اإأآ]ـ*',
        'ي' || 'ى' => '[يى]ـ*',
        'ة' || 'ه' => '[ةه]ـ*',
        _ => _arabicLetter.hasMatch(c) ? '$cـ*' : RegExp.escape(c),
      });
    }
    final edge = _arabicLetter.hasMatch(label) ? r'؀-ۿ' : 'A-Za-z';
    return RegExp('(?<![$edge])$buffer(?![$edge])', caseSensitive: false);
  }

  /// Labels in [text], left to right. A longer label wins over any shorter
  /// one it overlaps (`ISSUING AUTHORITY` over `AUTHORITY`).
  static List<PassportLabelHit> hitsIn(String text) {
    final all = <PassportLabelHit>[];
    for (final (field, regex) in _compiled) {
      for (final m in regex.allMatches(text)) {
        all.add(PassportLabelHit(field, m.start, m.end));
      }
    }
    all.sort((a, b) => (b.end - b.start).compareTo(a.end - a.start));
    final accepted = <PassportLabelHit>[];
    for (final hit in all) {
      final overlaps = accepted.any((o) => hit.start < o.end && o.start < hit.end);
      if (!overlaps) accepted.add(hit);
    }
    accepted.sort((a, b) => a.start.compareTo(b.start));
    return accepted;
  }

  // ------------------------------------------------------------- fuzzy match

  static final _fuzzyLabels = <({PassportField field, String key, bool arabic})>[
    for (final entry in _labels.entries)
      for (final label in entry.value)
        if (_key(label).length >= 6)
          (
            field: entry.key,
            key: _key(label),
            arabic: _arabicLetter.hasMatch(label),
          ),
  ];

  /// Letters that differ only by their dots (ب ت ث ن ي, ج ح خ, ...) share one
  /// shape; OCR often loses or moves the dots, so they are compared by shape.
  static const _arabicShapes = {
    'أ': 'ا', 'إ': 'ا', 'آ': 'ا', 'ى': 'ب', 'ي': 'ب', 'ئ': 'ب', 'ت': 'ب',
    'ث': 'ب', 'ن': 'ب', 'خ': 'ح', 'ج': 'ح', 'ذ': 'د', 'ز': 'ر', 'ش': 'س',
    'ض': 'ص', 'ظ': 'ط', 'غ': 'ع', 'ق': 'ف', 'ة': 'ه', 'ؤ': 'و',
  };

  /// Comparison key: Latin letters upper-cased (digits that look like letters
  /// mapped back), or the dot-less shapes of the Arabic letters, whichever
  /// script [text] is in. Spaces and punctuation are dropped.
  static String _key(String text) {
    final arabic = _arabicLetter.hasMatch(text);
    final out = StringBuffer();
    for (final c in text.toUpperCase().split('')) {
      if (arabic) {
        final code = c.codeUnitAt(0);
        if (code >= 0x0621 && code <= 0x064A) out.write(_arabicShapes[c] ?? c);
      } else {
        final letter = switch (c) { '0' => 'O', '1' => 'I', '5' => 'S', '8' => 'B', _ => c };
        final code = letter.codeUnitAt(0);
        if (code >= 65 && code <= 90) out.write(letter);
      }
    }
    return out.toString();
  }

  /// Smallest edit distance between [label] and any substring of [text].
  static int _bestSubstringDistance(String label, String text) {
    var previous = List<int>.filled(text.length + 1, 0);
    for (var i = 1; i <= label.length; i++) {
      final current = List<int>.filled(text.length + 1, 0)..[0] = i;
      for (var j = 1; j <= text.length; j++) {
        final substitution = previous[j - 1] + (label[i - 1] == text[j - 1] ? 0 : 1);
        final deletion = previous[j] + 1;
        final insertion = current[j - 1] + 1;
        current[j] = [substitution, deletion, insertion].reduce((a, b) => a < b ? a : b);
      }
      previous = current;
    }
    return previous.reduce((a, b) => a < b ? a : b);
  }

  /// The label [text] most likely is when OCR garbled it (`Pace o Bthia`,
  /// `الرقم الوطي`), or null. Used only when no exact label matched.
  ///
  /// A label may lose about a third of its letters. A short title or a line
  /// that is much longer than the label never matches, and two different
  /// fields that fit about equally well cancel out.
  static PassportLabelHit? fuzzyHit(String text) {
    final latinKey = _key(text.replaceAll(_arabicLetter, ' '));
    final arabicKey = _key(text.replaceAll(RegExp(r'[A-Za-z]'), ' '));

    ({PassportField field, double ratio})? best;
    ({PassportField field, double ratio})? second;
    for (final label in _fuzzyLabels) {
      final key = label.arabic ? arabicKey : latinKey;
      final length = label.key.length;
      if (key.length < length * 0.6 || key.length > length * 2.5 + 4) continue;
      final allowed = length >= 10 ? (length * 0.34).floor() : (length * 0.2).floor();
      final distance = _bestSubstringDistance(label.key, key);
      if (distance > allowed) continue;
      final candidate = (field: label.field, ratio: distance / length);
      if (best == null || candidate.ratio < best.ratio) {
        if (best != null && best.field != candidate.field) second = best;
        best = candidate;
      } else if (candidate.field != best.field &&
          (second == null || candidate.ratio < second.ratio)) {
        second = candidate;
      }
    }
    if (best == null) return null;
    if (second != null && second.ratio - best.ratio < 0.05) return null; // ambiguous
    return PassportLabelHit(best.field, 0, text.length);
  }

  /// Upper-case Latin words that occur in labels; never part of a value.
  static final latinLabelWords = <String>{
    for (final labels in _labels.values)
      for (final label in labels)
        if (!_arabicLetter.hasMatch(label))
          ...label.toUpperCase().split(RegExp(r"[^A-Z]+")).where((w) => w.length >= 2),
    'REPUBLIC', 'THE', 'KINGDOM', 'STATE', 'PEOPLES', 'DEMOCRATIC', 'FEDERAL', 'FEDERATION',
    'DE', 'LA', 'DU', 'DES', 'DATE', 'LIEU',
  };

  /// Arabic words that occur in labels or page headings.
  static final arabicLabelWords = <String>{
    for (final labels in _labels.values)
      for (final label in labels)
        if (_arabicLetter.hasMatch(label))
          ...label.split(' ').map(_stripHamza),
    'جمهورية', 'مملكة', 'دولة', 'وزارة', 'الداخلية', 'الشعبية', 'الديمقراطية',
  };

  static String _stripHamza(String word) =>
      word.replaceAll(RegExp('[إأآ]'), 'ا');
}
