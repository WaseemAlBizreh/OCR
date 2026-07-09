enum ArabicCountry {
  sudan('sd', 'Sudan', 'جمهورية السودان'),
  uae('ae', 'United Arab Emirates', 'الإمارات العربية المتحدة');

  const ArabicCountry(this.code, this.englishName, this.arabicName);

  final String code;
  final String englishName;
  final String arabicName;

  static ArabicCountry? fromCode(String? code) {
    if (code == null) return null;
    for (final country in ArabicCountry.values) {
      if (country.code == code) return country;
    }
    return null;
  }
}
