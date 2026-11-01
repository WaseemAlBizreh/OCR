import 'dart:io';
import 'dart:typed_data';

import 'package:idlens/src/domain/document_kind.dart';

/// One captured page of a document, ready to upload or store.
class ScannedImage {
  /// Creates an image of [side] stored in [file].
  const ScannedImage({
    required this.side,
    required this.file,
    this.isTemporary = false,
  });

  /// Which page of the document this is.
  final DocumentSide side;

  /// The image file (JPEG or PNG).
  final File file;

  /// True when idlens created [file] in the temporary folder. Result
  /// `dispose()` deletes only such files. Files passed in by the host app
  /// are never deleted.
  final bool isTemporary;

  /// The file's content, for uploads that need bytes.
  Future<Uint8List> bytes() => file.readAsBytes();

  /// A JSON-friendly description of the image (side and path).
  Map<String, dynamic> toJson() => {'side': side.name, 'path': file.path};
}
