/// Greedy CTC decoding for the PaddleOCR recognizer output.
///
/// Class 0 is the CTC blank; class `i` (i >= 1) maps to `dictionary[i - 1]`.
/// A trailing space class is appended by PaddleOCR when `use_space_char` is on,
/// so it is included in [dictionary] by the caller.
class CtcDecoder {
  const CtcDecoder(this.dictionary);

  final List<String> dictionary;

  /// [logits] is `[timeSteps][classes]`. Returns the decoded text and the mean
  /// confidence of the emitted characters (0 when nothing was emitted).
  ({String text, double confidence}) greedy(List<List<double>> logits) {
    final out = StringBuffer();
    var previous = 0;
    var total = 0.0;
    var count = 0;

    for (final step in logits) {
      var best = 0;
      for (var i = 1; i < step.length; i++) {
        if (step[i] > step[best]) best = i;
      }
      if (best != 0 && best != previous && best - 1 < dictionary.length) {
        out.write(dictionary[best - 1]);
        total += step[best];
        count++;
      }
      previous = best;
    }

    return (text: out.toString(), confidence: count == 0 ? 0 : total / count);
  }
}
