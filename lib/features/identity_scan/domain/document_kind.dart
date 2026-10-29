enum DocumentKind {
  sudanId,
  passport,
  civilRegistryCertificate,
}

extension DocumentKindInfo on DocumentKind {
  String get label => switch (this) {
        DocumentKind.sudanId => 'Sudan ID card',
        DocumentKind.passport => 'Passport',
        DocumentKind.civilRegistryCertificate => 'Civil registry certificate',
      };

  /// Pages the user has to scan, in order.
  List<DocumentSide> get sides => switch (this) {
        DocumentKind.sudanId => const [DocumentSide.front, DocumentSide.back],
        DocumentKind.passport => const [DocumentSide.dataPage],
        DocumentKind.civilRegistryCertificate => const [DocumentSide.page],
      };

  /// Whether the document has a machine-readable zone to guide and read.
  bool get hasMrz => this != DocumentKind.civilRegistryCertificate;

  /// Width / height of the physical document (ID-1 card or ID-3 data page).
  double get aspectRatio => switch (this) {
        DocumentKind.sudanId => 85.6 / 54.0,
        DocumentKind.passport => 125.0 / 88.0,
        DocumentKind.civilRegistryCertificate => 210.0 / 297.0, // A4 portrait
      };

  /// Fraction of the cropped image height, from the bottom, that the MRZ
  /// reader looks at. Generous on purpose: a card held a little low or high
  /// must still have its MRZ inside it.
  double get mrzBandFraction => switch (this) {
        DocumentKind.sudanId => 0.42,
        DocumentKind.passport => 0.32,
        DocumentKind.civilRegistryCertificate => 0,
      };

  /// Height of the MRZ guide drawn on the camera screen, as a fraction of the
  /// card. Tighter than [mrzBandFraction] because it only shows where to put
  /// the MRZ; it is not the area that gets read.
  double get mrzGuideFraction => switch (this) {
        DocumentKind.sudanId => 0.34,
        DocumentKind.passport => 0.25,
        DocumentKind.civilRegistryCertificate => 0,
      };

  /// How to take the photos, shown on the preview page.
  List<String> get photoTips => switch (this) {
        DocumentKind.sudanId => const [
            'Lay the card flat on a plain surface in good light.',
            'Fit the whole card inside the frame and hold the phone steady, straight above the card.',
            'Avoid glare and shadows. If a bright spot appears on the card, tilt it slightly.',
            _flashTip,
          ],
        DocumentKind.passport => const [
            'Open the passport flat so the data page does not curve, in good light.',
            'Fit the whole data page inside the frame and hold the phone steady, straight above it.',
            'Avoid glare on the photo and the laminate. If a bright spot appears, tilt the page slightly.',
            _flashTip,
          ],
        DocumentKind.civilRegistryCertificate => const [
            'Lay the certificate flat on a dark, plain surface in good light.',
            'Fit the whole page inside the frame, with its four corners visible, and hold the phone steady and straight above it.',
            'Avoid shadows and glare, especially over the stamp and the printed lines.',
            _flashTip,
          ],
      };

  static const _flashTip =
      'In dim light, tap the flash icon at the top right of the camera screen. '
      'The light stays on while you take the photo.';

  /// What happens when capturing starts.
  String get captureOrder => switch (this) {
        DocumentKind.sudanId =>
          'You will capture the front of the card first, then the back.',
        DocumentKind.passport => 'You will capture the data page.',
        DocumentKind.civilRegistryCertificate => 'You will capture the whole certificate page.',
      };

  /// What to look for in each photo before scanning.
  List<String> get checkTips => switch (this) {
        DocumentKind.sudanId => const [
            'Front: the name, national number and dates are sharp and fully inside the photo.',
            'Back: the three lines of letters and < signs at the bottom (the MRZ) are complete and sharp.',
            'No finger, shadow or reflection covers any text.',
          ],
        DocumentKind.passport => const [
            'All printed text is sharp and nothing is cut off.',
            'The two lines of letters and < signs at the bottom (the MRZ) are complete.',
            'No finger, shadow or reflection covers any text.',
          ],
        DocumentKind.civilRegistryCertificate => const [
            'All four corners of the page are inside the photo and the text is sharp.',
            'The registry office, the dates and the national number are fully visible.',
            'No finger, shadow or reflection covers any text.',
          ],
      };
}

enum DocumentSide {
  front,
  back,
  dataPage,
  page,
}

extension DocumentSideInfo on DocumentSide {
  String get label => switch (this) {
        DocumentSide.front => 'Front',
        DocumentSide.back => 'Back',
        DocumentSide.dataPage => 'Data page',
        DocumentSide.page => 'Certificate',
      };

  String get hint => switch (this) {
        DocumentSide.front => 'Fit the front of the ID card inside the frame',
        DocumentSide.back =>
          'Fit the back of the ID card inside the frame (MRZ visible)',
        DocumentSide.dataPage =>
          'Fit the passport data page inside the frame (MRZ visible)',
        DocumentSide.page =>
          'Fit the whole certificate page inside the frame',
      };
}
