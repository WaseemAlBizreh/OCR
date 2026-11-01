import 'dart:io';

import 'package:flutter/material.dart';
import 'package:idlens/src/api/civil_registry_result.dart';
import 'package:idlens/src/api/id_card_result.dart';
import 'package:idlens/src/api/passport_result.dart';
import 'package:idlens/src/api/scan_exception.dart';
import 'package:idlens/src/api/scan_options.dart';
import 'package:idlens/src/domain/document_kind.dart';
import 'package:idlens/src/presentation/pages/identity_flow_page.dart';
import 'package:idlens/src/scan_runner.dart';

/// Scans identity documents on the device. Nothing is uploaded.
///
/// There are two ways in, for each document:
///
/// * `scan...(context)` opens the built-in pages (tips, camera, preview) on the
///   app's `Navigator` and returns the result.
/// * `process...(files)` reads image files you already have and shows no UI.
///
/// A result is returned whenever at least one image was captured, even if
/// reading failed, so the images can always be uploaded; check `status` and
/// `issues` to decide how far to trust the fields.
class IdLens {
  /// Creates a scanner. It holds no state: every instance shares the loaded
  /// models.
  const IdLens();

  /// Opens the capture flow for a Sudan ID card (front, then back).
  ///
  /// Returns null when the user leaves before capturing anything. Throws
  /// [ScanException] when nothing could be captured because camera access was
  /// denied or the camera failed. Otherwise returns a result, whatever its
  /// `status`.
  Future<IdCardResult?> scanIdCard(
    BuildContext context, {
    IdCardScanOptions options = const IdCardScanOptions(),
  }) async =>
      await _flow(context, DocumentKind.sudanId, options) as IdCardResult?;

  /// Opens the capture flow for the data page of a passport from any country.
  ///
  /// Returns and throws as [scanIdCard] does.
  Future<PassportResult?> scanPassport(
    BuildContext context, {
    PassportScanOptions options = const PassportScanOptions(),
  }) async =>
      await _flow(context, DocumentKind.passport, options) as PassportResult?;

  /// Opens the capture flow for a civil registry certificate (A4).
  ///
  /// Returns and throws as [scanIdCard] does.
  Future<CivilRegistryResult?> scanCivilRegistry(
    BuildContext context, {
    CivilRegistryScanOptions options = const CivilRegistryScanOptions(),
  }) async =>
      await _flow(context, DocumentKind.civilRegistryCertificate, options)
          as CivilRegistryResult?;

  /// Reads the [front] and [back] photos of an ID card, without any UI.
  ///
  /// The files are used as given and are never deleted by `dispose()`. Throws
  /// [ScanException] with `imageUnreadable` when a file is missing; any other
  /// problem is reported on the result.
  Future<IdCardResult> processIdCard({
    required File front,
    required File back,
    IdCardScanOptions options = const IdCardScanOptions(),
  }) async {
    await _requireReadable([front, back]);
    return ScanRunner().idCard({
      DocumentSide.front: front.path,
      DocumentSide.back: back.path,
    });
  }

  /// Reads the [dataPage] photo of a passport, without any UI. Files and
  /// errors are handled as in [processIdCard].
  Future<PassportResult> processPassport({
    required File dataPage,
    PassportScanOptions options = const PassportScanOptions(),
  }) async {
    await _requireReadable([dataPage]);
    return ScanRunner().passport(dataPage.path);
  }

  /// Reads the [page] photo of a civil registry certificate, without any UI.
  /// Files and errors are handled as in [processIdCard].
  Future<CivilRegistryResult> processCivilRegistry({
    required File page,
    CivilRegistryScanOptions options = const CivilRegistryScanOptions(),
  }) async {
    await _requireReadable([page]);
    return ScanRunner().civilRegistry(page.path);
  }

  Future<Object?> _flow(
    BuildContext context,
    DocumentKind kind,
    ScanOptions options,
  ) async {
    final exit = await Navigator.of(context).push<ScanFlowExit>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => IdentityFlowPage(kind: kind, options: options),
      ),
    );
    if (exit == null) return null;
    final failure = exit.failure;
    if (exit.outcome == null && failure != null) throw failure;
    return exit.outcome;
  }

  Future<void> _requireReadable(List<File> files) async {
    for (final file in files) {
      if (!await file.exists()) {
        throw ScanException(
          ScanFailureReason.imageUnreadable,
          'No such file: ${file.path}',
        );
      }
    }
  }
}
