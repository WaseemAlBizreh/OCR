import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mrz/core/config/injection.dart';
import 'package:mrz/features/arabic_document_scan/data/document_scan_service.dart';
import 'package:mrz/features/arabic_document_scan/domain/custom_enhancement_settings.dart';
import 'package:mrz/features/arabic_document_scan/domain/image_enhancement_preset.dart';
import 'package:mrz/features/arabic_document_scan/domain/image_enhancement_preview.dart';

class EnhancedImagePreviewSheet extends StatefulWidget {
  const EnhancedImagePreviewSheet({
    super.key,
    required this.preview,
    required this.onEnsurePreset,
    required this.onEnsureCustom,
  });

  final ImageEnhancementPreview preview;
  final Future<String> Function(EnhancementPreset preset) onEnsurePreset;
  final Future<String> Function(CustomEnhancementSettings settings)
      onEnsureCustom;

  static Future<ImagePreviewSelection?> show(
    BuildContext context, {
    required ImageEnhancementPreview preview,
    required Future<String> Function(EnhancementPreset preset) onEnsurePreset,
    required Future<String> Function(CustomEnhancementSettings settings)
        onEnsureCustom,
  }) {
    return showModalBottomSheet<ImagePreviewSelection>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => EnhancedImagePreviewSheet(
        preview: preview,
        onEnsurePreset: onEnsurePreset,
        onEnsureCustom: onEnsureCustom,
      ),
    );
  }

  @override
  State<EnhancedImagePreviewSheet> createState() =>
      _EnhancedImagePreviewSheetState();
}

class _EnhancedImagePreviewSheetState extends State<EnhancedImagePreviewSheet> {
  late EnhancementPreset _selectedPreset;
  late Map<EnhancementPreset, String> _generatedPaths;
  late Map<String, String> _customGeneratedPaths;
  late CustomEnhancementSettings _customSettings;
  String? _displayPath;
  bool _isLoadingPreset = false;
  Timer? _customDebounce;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _selectedPreset = widget.preview.enhancementFailed
        ? EnhancementPreset.original
        : widget.preview.selectedPreset;
    _generatedPaths = Map.of(widget.preview.presetPaths);
    _customGeneratedPaths = {};
    _customSettings = CustomEnhancementSettings.defaults;
    _displayPath = widget.preview.pathFor(_selectedPreset);
    if (_selectedPreset == EnhancementPreset.custom) {
      _loadCustom(_customSettings);
    } else if (_selectedPreset != EnhancementPreset.original) {
      _loadPreset(_selectedPreset);
    }
  }

  @override
  void dispose() {
    _customDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadPreset(EnhancementPreset preset) async {
    final generation = ++_loadGeneration;
    _customDebounce?.cancel();

    setState(() {
      _isLoadingPreset = true;
      _selectedPreset = preset;
    });

    try {
      final path = await widget.onEnsurePreset(preset);
      if (!mounted || generation != _loadGeneration) return;
      if (preset != EnhancementPreset.original) {
        _generatedPaths[preset] = path;
      }
      setState(() {
        _displayPath = path;
        _isLoadingPreset = false;
      });
    } catch (e) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _displayPath = widget.preview.originalPath;
        _selectedPreset = EnhancementPreset.original;
        _isLoadingPreset = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load preset: $e')),
      );
    }
  }

  Future<void> _loadCustom(CustomEnhancementSettings settings) async {
    final generation = ++_loadGeneration;

    setState(() {
      _isLoadingPreset = true;
      _selectedPreset = EnhancementPreset.custom;
      _customSettings = settings;
    });

    try {
      final path = await widget.onEnsureCustom(settings);
      if (!mounted || generation != _loadGeneration) return;
      _customGeneratedPaths[settings.cacheKey] = path;
      setState(() {
        _displayPath = path;
        _isLoadingPreset = false;
      });
    } catch (e) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _displayPath = widget.preview.originalPath;
        _isLoadingPreset = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not apply custom filter: $e')),
      );
    }
  }

  void _scheduleCustomPreview(CustomEnhancementSettings settings) {
    _customDebounce?.cancel();
    _customDebounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted || _isLoadingPreset) return;
      _loadCustom(settings);
    });
  }

  void _onCustomSliderChanged(
    CustomEnhancementSettings Function(CustomEnhancementSettings current) update,
  ) {
    final next = update(_customSettings);
    setState(() => _customSettings = next);
    _scheduleCustomPreview(next);
  }

  void _pop(ImagePreviewAction action) {
    final ocrPath = switch (_selectedPreset) {
      EnhancementPreset.original => widget.preview.originalPath,
      EnhancementPreset.custom =>
        _customGeneratedPaths[_customSettings.cacheKey] ??
            widget.preview.originalPath,
      _ => _generatedPaths[_selectedPreset] ?? widget.preview.originalPath,
    };

    Navigator.of(context).pop(
      ImagePreviewSelection(
        action: action,
        preset: _selectedPreset,
        ocrImagePath: ocrPath,
        generatedPaths: Map.of(_generatedPaths),
        customSettings:
            _selectedPreset == EnhancementPreset.custom ? _customSettings : null,
        customGeneratedPaths: Map.of(_customGeneratedPaths),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final presets = [
      if (!widget.preview.enhancementFailed) EnhancementPreset.standard,
      EnhancementPreset.original,
      if (!widget.preview.enhancementFailed) ...[
        EnhancementPreset.minimal,
        EnhancementPreset.enhanced,
        EnhancementPreset.custom,
      ],
    ];

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
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
                      'Review image for OCR',
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Retake',
                    onPressed: () => _pop(ImagePreviewAction.retake),
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
                      'Choose a preset or use Custom to tune contrast, brightness, '
                      'and details manually.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (widget.preview.warning != null) ...[
                      const SizedBox(height: 12),
                      Card(
                        color: theme.colorScheme.errorContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            widget.preview.warning!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final preset in presets)
                          ChoiceChip(
                            label: Text(preset.label),
                            selected: _selectedPreset == preset,
                            onSelected: _isLoadingPreset
                                ? null
                                : (_) {
                                    if (preset == EnhancementPreset.custom) {
                                      _loadCustom(_customSettings);
                                    } else {
                                      _loadPreset(preset);
                                    }
                                  },
                          ),
                      ],
                    ),
                    if (_selectedPreset == EnhancementPreset.custom) ...[
                      const SizedBox(height: 16),
                      _CustomFilterControls(
                        settings: _customSettings,
                        enabled: !_isLoadingPreset,
                        onChanged: _onCustomSliderChanged,
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      _selectedPreset.label,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    if (_isLoadingPreset)
                      const Card(
                        child: AspectRatio(
                          aspectRatio: 4 / 3,
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      )
                    else
                      _ImagePreviewCard(path: _displayPath!),
                    if (_selectedPreset != EnhancementPreset.original) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Original',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      _ImagePreviewCard(path: widget.preview.originalPath),
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
                        onPressed: _isLoadingPreset
                            ? null
                            : () => _pop(ImagePreviewAction.retake),
                        icon: const Icon(Icons.camera_alt_outlined),
                        label: const Text('Retake'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _isLoadingPreset
                            ? null
                            : () => _pop(ImagePreviewAction.accept),
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

class _CustomFilterControls extends StatelessWidget {
  const _CustomFilterControls({
    required this.settings,
    required this.enabled,
    required this.onChanged,
  });

  final CustomEnhancementSettings settings;
  final bool enabled;
  final void Function(
    CustomEnhancementSettings Function(CustomEnhancementSettings current),
  ) onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Custom filter',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            _FilterSlider(
              label: 'Contrast',
              value: settings.contrast.toDouble(),
              enabled: enabled,
              onChanged: (value) => onChanged(
                (current) => current.copyWith(contrast: value.round()),
              ),
            ),
            _FilterSlider(
              label: 'Brightness',
              value: settings.brightness.toDouble(),
              enabled: enabled,
              onChanged: (value) => onChanged(
                (current) => current.copyWith(brightness: value.round()),
              ),
            ),
            _FilterSlider(
              label: 'Details',
              value: settings.details.toDouble(),
              enabled: enabled,
              onChanged: (value) => onChanged(
                (current) => current.copyWith(details: value.round()),
              ),
            ),
            _FilterSlider(
              label: 'Shadow removal',
              value: settings.shadowRemoval.toDouble(),
              enabled: enabled,
              onChanged: (value) => onChanged(
                (current) => current.copyWith(shadowRemoval: value.round()),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Darken text for OCR'),
              subtitle: const Text('Forces text strokes darker'),
              value: settings.textDarkening,
              onChanged: enabled
                  ? (value) => onChanged(
                        (current) => current.copyWith(textDarkening: value),
                      )
                  : null,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Grayscale OCR mode'),
              subtitle: const Text('Black & white output, best for text'),
              value: settings.grayscale,
              onChanged: enabled
                  ? (value) => onChanged(
                        (current) => current.copyWith(grayscale: value),
                      )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterSlider extends StatelessWidget {
  const _FilterSlider({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final double value;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(label)),
            Text(
              value.round().toString(),
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ],
        ),
        Slider(
          value: value,
          min: 0,
          max: 100,
          divisions: 100,
          label: value.round().toString(),
          onChanged: enabled ? onChanged : null,
        ),
      ],
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

Future<ImagePreviewSelection?> showEnhancedImagePreview(
  BuildContext context, {
  required ImageEnhancementPreview preview,
}) {
  final scanService = locator<DocumentScanService>();
  final presetCache = Map<EnhancementPreset, String>.of(preview.presetPaths);
  final customCache = <String, String>{};

  return EnhancedImagePreviewSheet.show(
    context,
    preview: preview,
    onEnsurePreset: (preset) => scanService.ensurePresetPath(
      originalPath: preview.originalPath,
      preset: preset,
      cache: presetCache,
    ),
    onEnsureCustom: (settings) => scanService.ensureCustomPath(
      originalPath: preview.originalPath,
      settings: settings,
      cache: customCache,
    ),
  );
}
