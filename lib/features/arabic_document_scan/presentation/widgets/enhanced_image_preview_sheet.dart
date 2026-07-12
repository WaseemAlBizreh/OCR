import 'dart:io';

import 'package:flutter/material.dart';

enum ImagePreviewAction { retake, accept }

class EnhancedImagePreviewSheet extends StatelessWidget {
  const EnhancedImagePreviewSheet({
    super.key,
    required this.previewPath,
    required this.originalPath,
    this.warning,
  });

  final String previewPath;
  final String originalPath;
  final String? warning;

  static Future<ImagePreviewAction?> show(
    BuildContext context, {
    required String previewPath,
    required String originalPath,
    String? warning,
  }) {
    return showModalBottomSheet<ImagePreviewAction>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => EnhancedImagePreviewSheet(
        previewPath: previewPath,
        originalPath: originalPath,
        warning: warning,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showComparison = previewPath != originalPath;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Review enhanced image',
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Retake',
                    onPressed: () => Navigator.of(context).pop(
                      ImagePreviewAction.retake,
                    ),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'This is how your document will be processed for OCR. '
                      'Accept to continue or retake if the image is unclear.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (warning != null) ...[
                      const SizedBox(height: 12),
                      Card(
                        color: theme.colorScheme.errorContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            warning!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    if (showComparison) ...[
                      Text(
                        'Enhanced',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                    ],
                    _ImagePreviewCard(path: previewPath),
                    if (showComparison) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Original',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      _ImagePreviewCard(path: originalPath),
                    ],
                  ],
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).pop(
                          ImagePreviewAction.retake,
                        ),
                        icon: const Icon(Icons.camera_alt_outlined),
                        label: const Text('Retake'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => Navigator.of(context).pop(
                          ImagePreviewAction.accept,
                        ),
                        icon: const Icon(Icons.check),
                        label: const Text('Accept'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ImagePreviewCard extends StatelessWidget {
  const _ImagePreviewCard({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: Image.file(
          File(path),
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => const Center(
            child: Icon(Icons.broken_image_outlined, size: 48),
          ),
        ),
      ),
    );
  }
}
