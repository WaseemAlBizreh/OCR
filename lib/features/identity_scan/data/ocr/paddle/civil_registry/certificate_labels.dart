/// Printed fields of a civil registry certificate (شهادة قيد مدني).
///
/// [other] holds headings and labels that are not read but must still be
/// recognised, so a heading line is never mistaken for a value.
enum CertificateField {
  registryOffice,
  issueDate,
  nationalNumber,
  name,
  placeOfBirth,
  dateOfBirth,
  maritalStatus,
  gender,
  nationalityType,
  profession,
  workAddress,
  motherName,
  other,
}

/// A label found in a line of text.
class CertificateLabelHit {
  const CertificateLabelHit(this.field, this.start, this.end);

  final CertificateField field;
  final int start;
  final int end;
}

/// Label dictionary of the certificate, with the same garbled-label repair as
/// the passport (`PassportLabels`): an exact spelling-tolerant match first,
/// then a fuzzy match on dot-less letter shapes (`الرقم الوطي` is still
/// `الرقم الوطني`).
///
/// Re-implemented for [CertificateField] instead of shared, so the passport
/// files stay untouched.
class CertificateLabels {
  CertificateLabels._();

  static const _labels = <CertificateField, List<String>>{
    CertificateField.registryOffice: [
      'مكتب التسجيل', 'مكتب السجل المدني', 'مكتب تسجيل',
    ],
    CertificateField.issueDate: [
      'تاريخ استخراج الشهادة', 'تاريخ الاستخراج', 'تاريخ الاصدار', 'تاريخ الإصدار',
    ],
    CertificateField.nationalNumber: ['الرقم الوطني', 'الرقم القومي'],
    CertificateField.name: ['الاسم الكامل', 'الاسم'],
    CertificateField.placeOfBirth: ['مكان الميلاد', 'مكان الولادة'],
    CertificateField.dateOfBirth: ['تاريخ الميلاد', 'تاريخ الولادة'],
    CertificateField.maritalStatus: ['الحالة الاجتماعية'],
    CertificateField.gender: ['الجنس', 'النوع'],
    CertificateField.nationalityType: ['نوع الجنسية'],
    CertificateField.profession: ['المهنة'],
    CertificateField.workAddress: ['عنوان العمل'],
    CertificateField.motherName: ['اسم الوالدة', 'اسم الأم'],
    CertificateField.other: [
      'شهادة قيد مدني', 'شهادة قيد', 'جمهورية السودان', 'وزارة الداخلية',
      'السجل المدني', 'الرقم التسلسلي', 'رقم الشهادة', 'التوقيع', 'الختم',
      'مدير السجل المدني', 'الجنسية', 'العنوان', 'الضابط المسئول', 'الضابط المسؤول',
      'الرتبة', 'رئاسة قوات الشرطة', 'هيئة الجوازات والسجل المدني', 'الادارة العامة للسجل المدني',
    ],
  };

  static final _compiled = <(CertificateField, RegExp)>[
    for (final entry in _labels.entries)
      for (final label in entry.value) ...[
        (entry.key, _compile(label)),
        (entry.key, _compile(label, glued: true)),
      ],
  ];

  /// Start of a value that OCR may have printed with no space after its label
  /// (`الجنسذكر`): the closed-vocabulary values and their one-letter misreads.
  static const _valueStart =
      '(?:ذكر|نكر|[اأإ]نثى|[اأإ]نثي|[اأإ]عزب|عزباء|متزوج|غير|مطلق|[اأإ]رمل|بالميلاد|بالتجنس|بالزواج)';

  /// Matches [label] as a whole word, however OCR spelled the look-alike
  /// Arabic letters (alef, ya, ta marbuta) or added tatweel.
  ///
  /// With [glued] the label may be followed directly by a known value.
  static RegExp _compile(String label, {bool glued = false}) {
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
    final end = glued ? '(?=$_valueStart)' : '(?![؀-ۿ])';
    return RegExp('(?<![؀-ۿ])$buffer$end');
  }

  /// Labels in [text], left to right. A longer label wins over any shorter
  /// one it overlaps (`الاسم الكامل` over `الاسم`).
  static List<CertificateLabelHit> hitsIn(String text) {
    final all = <CertificateLabelHit>[];
    for (final (field, regex) in _compiled) {
      for (final m in regex.allMatches(text)) {
        all.add(CertificateLabelHit(field, m.start, m.end));
      }
    }
    all.sort((a, b) => (b.end - b.start).compareTo(a.end - a.start));
    final accepted = <CertificateLabelHit>[];
    for (final hit in all) {
      final overlaps = accepted.any((o) => hit.start < o.end && o.start < hit.end);
      if (!overlaps) accepted.add(hit);
    }
    accepted.sort((a, b) => a.start.compareTo(b.start));
    return accepted;
  }

  // ------------------------------------------------------------- fuzzy match

  /// Only labels of 6+ letters are fuzzy-matched; shorter ones (`الاسم`,
  /// `الجنس`) would match too many unrelated words.
  static final _fuzzyLabels = <({CertificateField field, String key})>[
    for (final entry in _labels.entries)
      for (final label in entry.value)
        if (_key(label).length >= 6) (field: entry.key, key: _key(label)),
  ];

  /// Letters that differ only by their dots share one shape; OCR often loses
  /// or moves the dots, so labels are compared by shape.
  static const _arabicShapes = {
    'أ': 'ا', 'إ': 'ا', 'آ': 'ا', 'ى': 'ب', 'ي': 'ب', 'ئ': 'ب', 'ت': 'ب',
    'ث': 'ب', 'ن': 'ب', 'خ': 'ح', 'ج': 'ح', 'ذ': 'د', 'ز': 'ر', 'ش': 'س',
    'ض': 'ص', 'ظ': 'ط', 'غ': 'ع', 'ق': 'ف', 'ة': 'ه', 'ؤ': 'و',
  };

  /// Dot-less shapes of the Arabic letters in [text]; spaces, digits and
  /// punctuation are dropped.
  static String _key(String text) {
    final out = StringBuffer();
    for (final c in text.split('')) {
      final code = c.codeUnitAt(0);
      if (code >= 0x0621 && code <= 0x064A) out.write(_arabicShapes[c] ?? c);
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

  /// The label [text] most likely is when OCR garbled it (`الرقم الوطي`), or
  /// null. Used only when no exact label matched.
  ///
  /// A label may lose about a third of its letters, but a line must still be
  /// at least three quarters of its length. A short title or a line much longer than the label never matches, and two different fields that
  /// fit about equally well cancel out.
  static CertificateLabelHit? fuzzyHit(String text) {
    final key = _key(text);
    if (key.isEmpty) return null;

    ({CertificateField field, double ratio})? best;
    ({CertificateField field, double ratio})? second;
    for (final label in _fuzzyLabels) {
      final length = label.key.length;
      // A value that merely resembles part of a label (بالميلاد next to
      // تاريخ الميلاد) must cover most of the label to count.
      if (key.length < length * 0.75 || key.length > length * 2.5 + 4) continue;
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
    return CertificateLabelHit(best.field, 0, text.length);
  }
}
