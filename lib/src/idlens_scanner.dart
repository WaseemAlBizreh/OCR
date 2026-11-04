import 'dart:io';

import 'package:flutter/material.dart';
import 'package:idlens/src/api/civil_registry_result.dart';
import 'package:idlens/src/api/document_photo.dart';
import 'package:idlens/src/api/id_card_result.dart';
import 'package:idlens/src/api/passport_result.dart';
import 'package:idlens/src/api/scan_exception.dart';
import 'package:idlens/src/api/scan_options.dart';
import 'package:idlens/src/domain/document_kind.dart';
import 'package:idlens/src/platform_setup.dart';
import 'package:idlens/src/presentation/pages/identity_flow_page.dart';
import 'package:idlens/src/scan_runner.dart';

/// Scans identity documents on the device. Nothing is uploaded.
///
/// There are three ways in, depending on where the photos come from:
///
/// * **No camera of your own:** `scan...(context)` opens the built-in pages
///   (tips, camera, preview) on the app's `Navigator` and returns the result.
///   Its pages are in English.
/// * **Your own camera:** draw the box from [DocumentGuide.forPreview] on your
///   camera screen, then pass each raw photo to `process...` as
///   [DocumentPhoto.camera] with that box. idlens crops it the way its own
///   camera does, so the checks judge the same photo whichever way you scan.
/// * **Photos that already exist** (from a server or the gallery, or a `scan...`
///   result read again): pass them to `process...` as [DocumentPhoto.file].
///
/// A result is returned whenever at least one image was captured, even if
/// reading failed, so the images can always be uploaded; check `status` and
/// `issue` to decide how far to trust the fields.
class IdLens {
  /// Creates a scanner. It holds no state: every instance shares the loaded
  /// models.
  const IdLens();

  /// Opens the capture flow for a Sudan ID card (front, then back).
  ///
  /// Returns null when the user leaves before capturing anything. Throws
  /// [ScanException] when nothing could be captured because camera access was
  /// denied, the camera failed, or the iOS app lacks its camera usage
  /// description. Otherwise returns a result, whatever its
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
  /// Each photo is a [DocumentPhoto]: [DocumentPhoto.camera] for a raw photo
  /// from your own camera, which idlens crops first, or [DocumentPhoto.file]
  /// for a finished one, which is read as it is. The two can be mixed.
  ///
  /// Your files are never changed or deleted. For a camera photo, the result's
  /// `images` hold the cropped photos: temporary files that its `dispose()`
  /// deletes, so upload them first. For a file photo, the image is your own
  /// file and `dispose()` leaves it alone.
  ///
  /// Throws [ScanException] with `imageUnreadable` when a file is missing; any
  /// other problem, including a file that isn't an image, is reported on the
  /// result.
  ///
  /// [timeout] limits how long cropping and reading may take; null (the
  /// default) means no limit. When it passes, the result is `failed` with
  /// `ScanIssue.timedOut` and still has the images, and the work left is
  /// skipped. A step already running inside the text reader finishes in the
  /// background first.
  Future<IdCardResult> processIdCard({
    required DocumentPhoto front,
    required DocumentPhoto back,
    Duration? timeout,
  }) async {
    _requirePositive(timeout);
    await _requireReadable([front.file, back.file]);
    return ScanRunner().idCardFromPhotos({
      DocumentSide.front: front,
      DocumentSide.back: back,
    }, timeout: timeout);
  }

  /// Reads the [dataPage] photo of a passport, without any UI. Photos, files,
  /// errors and [timeout] are handled as in [processIdCard].
  Future<PassportResult> processPassport({
    required DocumentPhoto dataPage,
    Duration? timeout,
  }) async {
    _requirePositive(timeout);
    await _requireReadable([dataPage.file]);
    return ScanRunner().passportFromPhoto(dataPage, timeout: timeout);
  }

  /// Reads the [page] photo of a civil registry certificate, without any UI.
  /// Photos, files, errors and [timeout] are handled as in [processIdCard].
  ///
  /// A tilted or distant page is straightened to a flat A4 sheet before it is
  /// read; a photo with no clear page outline is read as it is. Only a
  /// temporary copy is straightened: the image on the result is the photo as
  /// given (cropped, for a camera photo).
  Future<CivilRegistryResult> processCivilRegistry({
    required DocumentPhoto page,
    Duration? timeout,
  }) async {
    _requirePositive(timeout);
    await _requireReadable([page.file]);
    return ScanRunner().civilRegistryFromPhoto(page, timeout: timeout);
  }

  Future<Object?> _flow(
    BuildContext context,
    DocumentKind kind,
    ScanOptions options,
  ) async {
    _requirePositive(options.timeout);
    final navigator = Navigator.of(context);
    if (await PlatformSetup.iosCameraUsageMissing()) {
      throw const ScanException(
        ScanFailureReason.missingSetup,
        'Add NSCameraUsageDescription to ios/Runner/Info.plist: iOS closes an '
        'app that opens the camera without it.',
      );
    }
    final exit = await navigator.push<ScanFlowExit>(
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

  static void _requirePositive(Duration? timeout) {
    if (timeout != null && timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'must be positive');
    }
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
