enum MrzFormat {
  td1(lineCount: 3, lineLength: 30),
  td3(lineCount: 2, lineLength: 44);

  const MrzFormat({required this.lineCount, required this.lineLength});

  final int lineCount;
  final int lineLength;
}

class MrzData {
  const MrzData({
    required this.format,
    required this.lines,
    required this.documentCode,
    required this.issuingCountry,
    required this.documentNumber,
    required this.dateOfBirth,
    required this.sex,
    required this.expiryDate,
    required this.nationality,
    required this.surname,
    required this.givenNames,
    required this.optionalData,
    required this.checks,
  });

  final MrzFormat format;
  final List<String> lines;
  final String documentCode;
  final String issuingCountry;
  final String documentNumber;

  /// ISO yyyy-MM-dd, or the raw yyMMdd when the digits are not a real date.
  final String dateOfBirth;
  final String sex;
  final String expiryDate;
  final String nationality;
  final String surname;
  final String givenNames;
  final String optionalData;

  /// Check-digit results keyed by field (documentNumber, dateOfBirth,
  /// expiryDate, composite, and personalNumber for TD3).
  final Map<String, bool> checks;

  bool get isValid => checks.values.every((passed) => passed);

  int get passedChecks => checks.values.where((passed) => passed).length;

  String get fullName => '$givenNames $surname'.trim();

  Map<String, dynamic> toJson() => {
        'format': format.name.toUpperCase(),
        'documentCode': documentCode,
        'issuingCountry': issuingCountry,
        'documentNumber': documentNumber,
        'dateOfBirth': dateOfBirth,
        'sex': sex,
        'expiryDate': expiryDate,
        'nationality': nationality,
        'surname': surname,
        'givenNames': givenNames,
        'optionalData': optionalData,
        'checks': checks,
        'isValid': isValid,
        'lines': lines,
      };
}
