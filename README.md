# idlens

On-device identity document scanner for Flutter. Capture and read **Sudan ID
cards**, **passports from any country** and **civil registry certificates**,
validate the MRZ check digits, and get back a typed result **together with the
document images**, ready to upload.

Everything runs on the phone (PaddleOCR on ONNX Runtime, ML Kit and OpenCV).
**Nothing is sent to any server.**

## Features

- Three scans: `scanIdCard`, `scanPassport`, `scanCivilRegistry`.
- Use our camera pages, replace the flow with your own camera by passing
  image files to the `process*` methods, or both.
- Always get the images back, even when reading fails: ignore the `issues` and
  upload the pictures if that is what your app needs.
- MRZ read with ICAO 9303 check-digit validation and automatic repair of
  look-alike characters (`O`/`0`, `I`/`1`, `S`/`5`, `B`/`8`).
- Typed fields (real `DateTime`s, nullable when not read) and `toJson()`.

## Install

```yaml
dependencies:
  idlens:
    git:
      url: https://github.com/WaseemAlBizreh/OCR.git
      ref: v0.1.0
```

Once published on pub.dev: `flutter pub add idlens`.

### Platform setup (required)

**Android**: add the camera permission to `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.CAMERA" />
```

**iOS**: add a usage description to `ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>The camera is used to scan identity documents.</string>
```

**App size**: idlens uses only the `core`, `imgproc` and `imgcodecs` parts of
OpenCV, which is what `opencv_dart` builds by default, so nothing needs to be
configured in your app and the large OpenCV modules (`dnn`, `video`, `calib3d`,
...) are never compiled in. The bundled OCR models add about 12 MB.

The example app builds with iOS 16.0 and the Flutter default Android `minSdk`.
The iOS simulator on Apple Silicon may not run ML Kit; test on a real device.

## Quick start

### 1. Built-in flow

```dart
import 'package:idlens/idlens.dart';

const idLens = IdLens();

try {
  final result = await idLens.scanIdCard(context);
  if (result == null) return; // the user left before capturing anything

  upload(result.images); // always available
  if (result.status == ScanStatus.verified) {
    print(result.englishName);   // "AHMED MOHAMED ALI"
    print(result.dateOfBirth);   // DateTime
    print(result.expiryDate);
  } else {
    print(result.issues);        // e.g. [ScanIssue.imageNotClear]
  }
} on ScanException catch (e) {
  // Nothing could be captured: e.reason is permissionDenied or cameraUnavailable.
}
```

`scanPassport(context)` and `scanCivilRegistry(context)` work the same way and
return a `PassportResult` / `CivilRegistryResult`.

### 2. Your own camera or gallery, no UI

```dart
final result = await idLens.processIdCard(
  front: File(frontPath),
  back: File(backPath),
);
```

`processPassport(dataPage: ...)` and `processCivilRegistry(page: ...)` are the
same idea. Your files are used as given and are never deleted by idlens.

### 3. Options

```dart
await idLens.scanPassport(
  context,
  options: const PassportScanOptions(
    showTips: false,        // open the camera straight away
    requireValidMrz: true,  // the user can only retake until the MRZ checks pass
  ),
);
```

| Option | Default | Effect |
|---|---|---|
| `showTips` | `true` | Show the page of photo tips before the camera. Built-in flow only. |
| `requireValidMrz` | `false` | Built-in flow only offers Retake while the MRZ is missing or its check digits fail. Off: the user can continue anyway and you decide what to do. |

## Results

`IdCardResult`, `PassportResult` and `CivilRegistryResult` all extend
`ScanOutcome`:

| Member | Meaning |
|---|---|
| `status` | `verified`, `needsReview`, `failed` or `incomplete` |
| `issues` | Typed reasons the scan cannot be fully trusted (`ScanIssue`) |
| `warnings` | English detail for logs, such as which value disagrees with the MRZ |
| `images` | The captured pages (`ScannedImage`: `side`, `file`, `bytes()`) |
| `mrz` | The MRZ with per-field `checks` (ID card and passport) |
| `fields` / `toJson()` | The raw field map / everything as JSON |
| `dispose()` | Deletes the temporary image files idlens created |

**A result is returned whenever at least one image was captured.** `null` is
returned only when the user leaves before capturing anything, and
`ScanException` is thrown only when no image could be captured (camera
permission denied, camera failure, or a file passed to `process*` that does not
exist). Read problems are never exceptions: they show up as `status` and
`issues`.

| `ScanStatus` | Meaning |
|---|---|
| `verified` | No issues or warnings; for ID cards and passports all MRZ check digits passed. |
| `needsReview` | Fields were read but something is off (blurry photo, failed check digit, printed value disagreeing with the MRZ). |
| `failed` | Wrong document, not in the frame, no MRZ found, or a processing error. Images are still returned. |
| `incomplete` | The user left before every page was captured; nothing was read. |

| `ScanIssue` | Meaning |
|---|---|
| `mrzNotFound` | No MRZ could be read. |
| `wrongDocument` | An MRZ of another document type was found. |
| `documentNotInFrame` | The document is missing, too far, or cut off. |
| `imageNotClear` | Too dark, blurry or glare. |
| `mrzCheckDigitsFailed` | MRZ read, but a check digit failed (`mrz.checks` says which). |
| `processingFailed` | An unexpected error while reading; images are still returned. |

A civil registry certificate has no MRZ: for it `verified` only means the photo
was fine and every expected field was read.

## Documents

| Document | Method | Pages | Notes |
|---|---|---|---|
| Sudan ID card | `scanIdCard` | front, back | TD1 MRZ on the back |
| Passport | `scanPassport` | data page | Any country, TD3 MRZ |
| Civil registry certificate | `scanCivilRegistry` | one A4 page | Sudan certificate, no MRZ |

Accuracy has so far been checked on very few real documents. Test with your
own before relying on the results, and treat `status != verified` as a prompt
to review.

## Privacy and licenses

All processing is on-device and idlens makes no network calls. It stores the
photos only in the app's temporary folder until you call `dispose()` or the OS
clears it.

idlens is MIT licensed. The bundled OCR models are PaddleOCR weights
(Apache-2.0) converted to ONNX; their sources and hashes are in
`assets/models/paddle/README.md`. ML Kit and OpenCV carry their own licenses.

## More

- [How it works](doc/how_it_works.md)
- [Example app](example/): a demo of the three scans
- [Changelog](CHANGELOG.md)
