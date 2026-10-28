enum DocumentKind {
  sudanId,
  passport,
}

extension DocumentKindInfo on DocumentKind {
  String get label => switch (this) {
        DocumentKind.sudanId => 'Sudan ID card',
        DocumentKind.passport => 'Passport',
      };

  /// Pages the user has to scan, in order.
  List<DocumentSide> get sides => switch (this) {
        DocumentKind.sudanId => const [DocumentSide.front, DocumentSide.back],
        DocumentKind.passport => const [DocumentSide.dataPage],
      };

  /// Width / height of the physical document (ID-1 card or ID-3 data page).
  double get aspectRatio => switch (this) {
        DocumentKind.sudanId => 85.6 / 54.0,
        DocumentKind.passport => 125.0 / 88.0,
      };

  /// Fraction of the cropped image height, from the bottom, that the MRZ
  /// reader looks at. Generous on purpose: a card held a little low or high
  /// must still have its MRZ inside it.
  double get mrzBandFraction => switch (this) {
        DocumentKind.sudanId => 0.42,
        DocumentKind.passport => 0.32,
      };

  /// Height of the MRZ guide drawn on the camera screen, as a fraction of the
  /// card. Tighter than [mrzBandFraction] because it only shows where to put
  /// the MRZ; it is not the area that gets read.
  double get mrzGuideFraction => switch (this) {
        DocumentKind.sudanId => 0.34,
        DocumentKind.passport => 0.25,
      };
}

enum DocumentSide {
  front,
  back,
  dataPage,
}

extension DocumentSideInfo on DocumentSide {
  String get label => switch (this) {
        DocumentSide.front => 'Front',
        DocumentSide.back => 'Back',
        DocumentSide.dataPage => 'Data page',
      };

  String get hint => switch (this) {
        DocumentSide.front => 'Fit the front of the ID card inside the frame',
        DocumentSide.back =>
          'Fit the back of the ID card inside the frame (MRZ visible)',
        DocumentSide.dataPage =>
          'Fit the passport data page inside the frame (MRZ visible)',
      };
}
