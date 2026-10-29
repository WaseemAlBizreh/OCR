/// Reads the printed text of a card page. The classic [OcrEngine] and the
/// Paddle engine both implement it, so the scan service and the parsers stay
/// the same whichever engine produced the text.
abstract interface class CardTextRecognizer {
  /// Text lines in reading order, Arabic normalised.
  Future<String> recognizeCardText(String imagePath);
}
