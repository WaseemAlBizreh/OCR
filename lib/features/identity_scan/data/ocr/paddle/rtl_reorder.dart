/// Turns the recognizer's visual (left-to-right on the image) order into
/// logical order for right-to-left lines.
///
/// Same idea as PaddleOCR's own Arabic post-processing: reverse the whole
/// line, then put Latin/digit runs back the right way round. Arabic marks
/// (harakat) stay attached to the letter before them.
class RtlReorder {
  const RtlReorder._();

  static final _arabic = RegExp(r'[؀-ۿݐ-ݿﭐ-﷿ﹰ-﻿]');
  static final _mark = RegExp(r'[ً-ٰٟ]');
  // Numbers read left to right even inside Arabic text, Arabic-Indic digits
  // (٠-٩, ۰-۹) included, so they must not be reversed with the letters.
  static final _latinRun = RegExp(r'[A-Za-z0-9٠-٩۰-۹]');
  // Characters that may sit inside a number or Latin token (dates, ids).
  static final _runJoiner = RegExp(r'[.,:/\-]');

  /// Lines with no Arabic are returned unchanged.
  static String fix(String visual) {
    if (!_arabic.hasMatch(visual)) return visual;

    final clusters = _clusters(visual).toList().reversed.toList();

    final result = <String>[];
    var i = 0;
    while (i < clusters.length) {
      if (!_isRunChar(clusters[i], inRun: false)) {
        result.add(clusters[i]);
        i++;
        continue;
      }
      var j = i;
      while (j < clusters.length && _isRunChar(clusters[j], inRun: true)) {
        j++;
      }
      // A joiner at the edge of the run belongs to the text around it.
      while (j > i && !_latinRun.hasMatch(clusters[j - 1])) {
        j--;
      }
      result.addAll(clusters.sublist(i, j).reversed);
      i = j;
    }
    return result.join();
  }

  static bool _isRunChar(String cluster, {required bool inRun}) =>
      _latinRun.hasMatch(cluster) || (inRun && _runJoiner.hasMatch(cluster));

  static Iterable<String> _clusters(String s) sync* {
    final buffer = StringBuffer();
    for (final rune in s.runes) {
      final char = String.fromCharCode(rune);
      if (_mark.hasMatch(char) && buffer.isNotEmpty) {
        buffer.write(char);
        continue;
      }
      if (buffer.isNotEmpty) yield buffer.toString();
      buffer
        ..clear()
        ..write(char);
    }
    if (buffer.isNotEmpty) yield buffer.toString();
  }
}
