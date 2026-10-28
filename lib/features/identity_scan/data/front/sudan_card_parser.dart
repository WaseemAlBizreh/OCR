import 'package:mrz/features/identity_scan/data/front/card_dates.dart';
import 'package:mrz/features/identity_scan/data/front/parser_utils.dart';

/// Fields read from the printed (Arabic) side of a card.
class CardFields {
  const CardFields({required this.fields, required this.warnings});

  final Map<String, String?> fields;
  final List<String> warnings;
}

/// Label-driven parser for the Sudan national ID card.
class SudanCardParser {
  const SudanCardParser();

  /// The national number printed on the card has 11 digits.
  static final _nationalNumber = RegExp(r'\b\d{11}\b');
  static final _phone = RegExp(r'(?:ت\s*/\s*)?0?\d{9,10}');
  static final _bloodType = RegExp(r'\b[ABO][+-]\b', caseSensitive: false);

  CardFields parseFront(String ocrText) {
    final normalized = ParserUtils.normalizeDigits(ocrText);

    final fields = <String, String?>{
      'arabicName': ParserUtils.extractLabeledValue(
            ocrText,
            labels: const ['الإسم', 'الاسم', ':الإسم', ':الاسم'],
            arabicValue: true,
          ) ??
          ParserUtils.extractArabicColonValue(ocrText, minWords: 3),
      'nationalNumber': ParserUtils.extractLabeledValue(
            ocrText,
            labels: const ['الرقم الوطني', 'الرقم القومي'],
            valuePattern: _nationalNumber,
          ) ??
          _nationalNumber.firstMatch(normalized)?.group(0),
      'dateOfBirth': ParserUtils.extractDate(ocrText, const ['تاريخ الميلاد']),
      'placeOfBirth': ParserUtils.extractLabeledValue(
        ocrText,
        labels: const ['مكان الميلاد'],
        arabicValue: true,
      ),
      'bloodType': ParserUtils.extractLabeledValue(
        ocrText,
        labels: const ['فصيلة الدم'],
        valuePattern: _bloodType,
      ),
      'profession': ParserUtils.extractLabeledValue(
        ocrText,
        labels: const ['المهنة'],
        arabicValue: true,
      ),
      'address': ParserUtils.extractLabeledValue(
        ocrText,
        labels: const ['العنوان'],
        arabicValue: true,
      ),
      'phone': ParserUtils.extractLabeledValue(
        ocrText,
        labels: const ['ت /', 'ت/', 'هاتف', 'Tel'],
        valuePattern: _phone,
      ),
    };

    return CardFields(
      fields: fields,
      warnings: ParserUtils.collectWarnings(
        fields,
        const ['arabicName', 'nationalNumber', 'dateOfBirth'],
      ),
    );
  }

  CardFields parseBack(String ocrText) {
    final (issue, expiry) = _issueAndExpiry(ocrText);
    final fields = <String, String?>{
      'placeOfIssue': ParserUtils.extractLabeledValue(
        ocrText,
        labels: const ['مكان الإصدار', 'مكان الاصدار'],
        arabicValue: true,
      ),
      'issueDate': issue == null ? null : CardDates.slashed(issue),
      'expiryDate': expiry == null ? null : CardDates.slashed(expiry),
    };
    return CardFields(fields: fields, warnings: const []);
  }

  /// Issue and expiry dates from the back of the card.
  ///
  /// A date next to its label is trusted when both labels are found and agree
  /// (issue before expiry). When labels are garbled or contradict each other,
  /// the two most recent distinct dates are used instead: the earlier is the
  /// issue date and the later the expiry date. That is independent of the
  /// order OCR returns them in, and it ignores the date of birth, which is
  /// printed on the back as well. MRZ lines are excluded from the search.
  (DateTime?, DateTime?) _issueAndExpiry(String ocrText) {
    final text = ocrText
        .split('\n')
        .where((line) => !line.contains('<'))
        .join('\n');
    final unique = CardDates.datesIn(text).toSet().toList()..sort();

    var issue = _dateNearLabel(text, const ['تاريخ الإصدار', 'تاريخ الاصدار']);
    var expiry = _dateNearLabel(
      text,
      const ['تاريخ الإنتهاء', 'تاريخ الانتهاء', 'تاريخ الانتها'],
    );

    final contradictory =
        issue != null && expiry != null && !issue.isBefore(expiry);
    if (issue != null && expiry != null && !contradictory) return (issue, expiry);

    if (unique.length >= 2) {
      if (issue == null && expiry == null || contradictory) {
        return (unique[unique.length - 2], unique.last);
      }
      if (expiry == null) {
        expiry = unique.where((d) => d.isAfter(issue!)).lastOrNull;
      } else {
        issue = unique.where((d) => d.isBefore(expiry!)).lastOrNull;
      }
    }
    return contradictory ? (null, null) : (issue, expiry);
  }

  DateTime? _dateNearLabel(String text, List<String> labels) {
    final normalized = ParserUtils.normalizeForParsing(text);
    for (final label in labels) {
      final needle = ParserUtils.normalizeForParsing(label);
      final index = normalized.indexOf(needle);
      if (index == -1) continue;
      final start = index + needle.length;
      final window = normalized.substring(start, (start + 40).clamp(0, normalized.length));
      final dates = CardDates.datesIn(window);
      if (dates.isNotEmpty) return dates.first;
    }
    return null;
  }
}
