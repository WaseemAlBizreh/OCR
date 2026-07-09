enum IdCardSide {
  front,
  back,
}

extension IdCardSideLabel on IdCardSide {
  String get label => switch (this) {
        IdCardSide.front => 'Front',
        IdCardSide.back => 'Back',
      };

  String get captureHint => switch (this) {
        IdCardSide.front => 'Capture the front of the ID card',
        IdCardSide.back => 'Capture the back of the ID card (MRZ visible)',
      };
}
