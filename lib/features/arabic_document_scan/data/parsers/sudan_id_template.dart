class SudanIdTemplate {
  const SudanIdTemplate();

  String get countryCode => 'sd';

  static const arabicNameLabels = <String>[
    'الإسم',
    'الاسم',
    ':الإسم',
    ':الاسم',
  ];

  static const nationalNumberLabels = <String>[
    'الرقم الوطني',
    'الرقم القومي',
  ];

  static const dateOfBirthLabels = <String>['تاريخ الميلاد'];

  static const placeOfBirthLabels = <String>['مكان الميلاد'];

  static const bloodTypeLabels = <String>['فصيلة الدم'];

  static const professionLabels = <String>['المهنة'];

  static const addressLabels = <String>['العنوان'];

  static const phoneLabels = <String>['ت /', 'ت/', 'هاتف', 'Tel'];

  static const requiredFields = <String>[
    'arabicName',
    'nationalNumber',
    'dateOfBirth',
  ];

  Map<String, List<String>> get fieldLabels => const {
        'arabicName': arabicNameLabels,
        'nationalNumber': nationalNumberLabels,
        'dateOfBirth': dateOfBirthLabels,
        'placeOfBirth': placeOfBirthLabels,
        'bloodType': bloodTypeLabels,
        'profession': professionLabels,
        'address': addressLabels,
        'phone': phoneLabels,
      };
}