/// Reads the printed text of a card page. The Paddle engines implement it, so
/// the scan service and the parsers stay independent of the OCR engine.
abstract interface class CardTextRecognizer {
  /// Text lines in reading order, Arabic normalised.
  Future<String> recognizeCardText(String imagePath);
}
