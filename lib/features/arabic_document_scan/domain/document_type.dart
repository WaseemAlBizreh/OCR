enum DocumentType {
  arabicId,
  passport,
}

extension DocumentTypeLabel on DocumentType {
  String get label => switch (this) {
        DocumentType.arabicId => 'Arabic Country ID',
        DocumentType.passport => 'Passport',
      };

  String get captureHint => switch (this) {
        DocumentType.arabicId => 'Capture the front of the national ID card',
        DocumentType.passport => 'Capture the passport data page (MRZ visible)',
      };
}
