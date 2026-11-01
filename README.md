# idlens

[![pub package](https://img.shields.io/pub/v/idlens.svg)](https://pub.dev/packages/idlens)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![platforms](https://img.shields.io/badge/platforms-Android%20%7C%20iOS-lightgrey)

**Scan identity documents on the phone, with no server.** idlens captures and
reads Sudan ID cards, passports from any country and civil registry
certificates. It checks the MRZ, returns the data as typed fields, and always
gives you the document photos back, ready to upload.

Everything runs on the device. No image or text ever leaves the phone.

## Highlights

- **Three documents:** Sudan ID card (front and back), passport data page (any
  country) and civil registry certificate (A4).
- **Two ways to use it:** open the built-in camera screens, or pass in photos
  you already have from your own camera, the gallery or a server.
- **Images always returned:** even when reading fails, you get the pictures, so
  your app can still upload them for manual review.
- **Trustworthy MRZ:** ICAO 9303 check digits are validated, and look-alike
  characters (O and 0, I and 1, S and 5, B and 8) are repaired automatically.
- **Clear results:** typed fields with real dates, a simple status, and a list
  of reasons when something looks wrong.
- **Helpful camera flow:** photo tips, front and back capture, a preview with
  retake, and a warning when a photo is blurry, dark or cut off.
- **Private by design:** OCR runs on the device with PaddleOCR, ML Kit and
  OpenCV. No network calls.

## Installation

Add the package to your app and fetch it:

```
flutter pub add idlens
flutter pub get
```

Or add it to pubspec.yaml yourself and run flutter pub get:

```yaml
dependencies:
  idlens: ^0.1.0
```

Then import it:

```dart
import 'package:idlens/idlens.dart';
```

## Platform setup

### Android

Nothing to add.

### iOS

Add a camera description to ios/Runner/Info.plist. This is the only required
step. Apple reads this key from your app, so a package cannot add it for you.

```xml
<key>NSCameraUsageDescription</key>
<string>The camera is used to scan identity documents.</string>
```

If the key is missing, the scan methods throw a ScanException with the reason
missingSetup that names the key, instead of iOS closing your app when the camera
opens.

### Build requirements

- **CMake:** OpenCV is compiled when your app is built. Android uses the CMake
  from the Android SDK. For iOS builds, install CMake on your Mac
  (brew install cmake). Without it the build stops with "Failed to find cmake
  version: latest".
- **App size:** idlens uses only the core, imgproc and imgcodecs parts of
  OpenCV, so the large modules are never compiled in. The bundled OCR models add
  about 12 MB.
- **Devices:** the example builds for iOS 16.0 and the Flutter default Android
  minimum. The iOS simulator on Apple Silicon may not run ML Kit, so test on a
  real device.

## Quick look

Everything starts from one stateless class, `IdLens`. It has six methods: for
each document, one that opens the built-in screens (`scan...`) and one that
reads image files you already have (`process...`).

| Document | Built-in screens | From image files | Result |
|---|---|---|---|
| Sudan ID card | `scanIdCard` | `processIdCard` | `IdCardResult` |
| Passport, any country | `scanPassport` | `processPassport` | `PassportResult` |
| Civil registry certificate | `scanCivilRegistry` | `processCivilRegistry` | `CivilRegistryResult` |

```dart
import 'package:idlens/idlens.dart';

final result = await const IdLens().scanIdCard(context);

if (result != null) {
  print(result.status);        // ScanStatus.verified
  print(result.englishName);   // the name read from the card
  print(result.dateOfBirth);   // a real DateTime
}
```

A complete app that uses every method, with the options as switches, is in
[example/lib/main.dart](example/lib/main.dart).

## The APIs

### `scanIdCard`

```dart
Future<IdCardResult?> scanIdCard(
  BuildContext context, {
  IdCardScanOptions options = const IdCardScanOptions(),
})
```

Opens the full capture flow on your app's navigator: an optional page of photo
tips, the camera for the front, the camera for the back, a preview where the
user can retake either side, and then the scan. The back of the card holds the
MRZ.

- **Returns** an `IdCardResult`, or `null` only if the user leaves before
  capturing anything.
- **Throws** a `ScanException` only when no image could be captured, for
  example camera permission denied, a camera failure, or the iOS setup missing.
- If the user goes back after capturing some pages, you get a result with the
  status `incomplete` that holds those images.
- A blurry, dark or cut-off photo is shown to the user before reading, and they
  can retake it or choose Use anyway.

### `scanPassport`

```dart
Future<PassportResult?> scanPassport(
  BuildContext context, {
  PassportScanOptions options = const PassportScanOptions(),
})
```

The same flow for a single page: the data page with the photo and the two MRZ
lines. It works for passports from any country. Returns `null` if the user
leaves before capturing, and throws like `scanIdCard`.

### `scanCivilRegistry`

```dart
Future<CivilRegistryResult?> scanCivilRegistry(
  BuildContext context, {
  CivilRegistryScanOptions options = const CivilRegistryScanOptions(),
})
```

The same flow for one A4 certificate page. The camera straightens the page into
a flat sheet when it can find the four corners. This document has no MRZ.
Returns `null` if the user leaves before capturing, and throws like
`scanIdCard`.

### `processIdCard`

```dart
Future<IdCardResult> processIdCard({
  required File front,
  required File back,
  IdCardScanOptions options = const IdCardScanOptions(),
})
```

Reads two photos you already have. There are no screens, no camera and no
`BuildContext`, so it suits your own camera, a gallery picker or images that
came from a server.

- **Returns** an `IdCardResult`. Never `null`.
- **Throws** a `ScanException` with the reason `imageUnreadable` if a file does
  not exist. Every other problem is reported on the result.
- Your files are used as given and are never deleted by `dispose()`.
- For the best result, crop the card to fill the image, with the MRZ sharp and
  fully visible.

### `processPassport`

```dart
Future<PassportResult> processPassport({
  required File dataPage,
  PassportScanOptions options = const PassportScanOptions(),
})
```

Same as `processIdCard`, for the passport data page.

### `processCivilRegistry`

```dart
Future<CivilRegistryResult> processCivilRegistry({
  required File page,
  CivilRegistryScanOptions options = const CivilRegistryScanOptions(),
})
```

Same as `processIdCard`, for the certificate page.

### Using your own photos

```dart
final result = await const IdLens().processPassport(
  dataPage: File(pickedImage.path),
);

if (result.status != ScanStatus.verified) {
  // Show result.issues to the user, or send result.images for manual review.
}
result.dispose();
```

## Options

Each method takes an optional options object: `IdCardScanOptions`,
`PassportScanOptions` or `CivilRegistryScanOptions`.

```dart
await const IdLens().scanIdCard(
  context,
  options: const IdCardScanOptions(showTips: false, requireValidMrz: true),
);
```

| Option | Default | What it does |
|---|---|---|
| `showTips` | `true` | Shows the page of photo tips before the camera. When `false`, the camera opens straight away. Only for the `scan...` methods. |
| `requireValidMrz` | `false` | While the MRZ is missing or its check digits fail, the user can only retake. When `false`, the user can continue and you decide what to do with the issues. Only for the `scan...` methods, and not available for the certificate, which has no MRZ. |

## Results

`IdCardResult`, `PassportResult` and `CivilRegistryResult` all extend
`ScanOutcome`, so the same members are on every result.

| Member | Meaning |
|---|---|
| `status` | `verified`, `needsReview`, `failed` or `incomplete` |
| `issues` | The reasons the scan cannot be fully trusted (`ScanIssue`) |
| `warnings` | English detail for your logs, such as which value disagrees with the MRZ |
| `images` | The captured pages (`ScannedImage`: `side`, `file`, `bytes()`). `imageFor(side)` finds one. |
| `mrz` | The MRZ with a result for every check digit in `checks` (ID card and passport) |
| `fields` / `toJson()` | The raw field map, and everything as JSON (image paths, not image content) |
| `diagnostics` | Debug data such as raw OCR text and timing. Not a stable API. |
| `dispose()` | Deletes the temporary image files that idlens created |

**You get a result whenever at least one image was captured.** A scan returns
`null` only when the user leaves before capturing anything, and a
`ScanException` is thrown only when no image could be captured. Problems with
reading are never exceptions. They appear as `status` and `issues`, and the
images are still there to upload.

### Fields

Every field is nullable: a value that could not be read is `null`. Dates are
real `DateTime` values. When a value appears in both the MRZ and the printed
text, the MRZ value is used if its own check digit passed, and a printed value
that disagrees is reported in `warnings`.

**`IdCardResult` and `PassportResult`:** `documentNumber`, `nationalNumber`,
`arabicName`, `englishName`, `surname`, `givenNames`, `dateOfBirth`, `sex`,
`nationality`, `issuingCountry`, `issueDate`, `expiryDate`, `placeOfBirth`,
`placeOfIssue`, and `isExpired` (`true`, `false`, or `null` when there is no
expiry date).

- `IdCardResult` adds `profession`, `address`, `bloodType` and `phone`.
- `PassportResult` adds `nationalityText`, `nationalityTextArabic`,
  `issuingCountryName`, `placeOfBirthArabic` and `placeOfIssueArabic`.

**`CivilRegistryResult`:** `registryOffice`, `issueDate`, `nationalNumber`,
`name`, `placeOfBirth`, `dateOfBirth`, `maritalStatus`, `gender`,
`nationalityType`, `profession`, `workAddress`, `motherName`, and `confidence`
(0 to 1 for each field).

### `ScanStatus`

| Value | Meaning |
|---|---|
| `verified` | No issues or warnings. For ID cards and passports, every MRZ check digit passed. |
| `needsReview` | Fields were read, but something is off: a blurry photo, a failed check digit, or a printed value that disagrees with the MRZ. |
| `failed` | Wrong document, document not in the frame, no MRZ found, or a processing error. The images are still returned. |
| `incomplete` | The user left before every page was captured. Nothing was read. |

A civil registry certificate has no MRZ, so for it `verified` only means the
photo was good and every expected field was read.

### `ScanIssue`

| Value | Meaning |
|---|---|
| `mrzNotFound` | No MRZ could be read. |
| `wrongDocument` | An MRZ of a different document type was found. |
| `documentNotInFrame` | The document is missing, too far away or cut off. |
| `imageNotClear` | The photo is too dark, blurry or has glare. |
| `mrzCheckDigitsFailed` | The MRZ was read, but a check digit failed. `mrz.checks` says which. |
| `processingFailed` | An unexpected error while reading. The images are still returned. |

### `ScanException`

```dart
try {
  final result = await const IdLens().scanPassport(context);
} on ScanException catch (e) {
  print(e.reason); // ScanFailureReason.permissionDenied, ...
}
```

| `reason` | When |
|---|---|
| `permissionDenied` | The user did not allow camera access and nothing was captured. |
| `cameraUnavailable` | There is no usable camera, or it failed to start, and nothing was captured. |
| `missingSetup` | iOS only: `NSCameraUsageDescription` is missing from `Info.plist`. |
| `imageUnreadable` | A file passed to a `process...` method does not exist. |

## Accuracy

Accuracy has so far been checked on only a small number of real documents. Test
with your own documents before relying on the results, and treat any status
other than verified as a prompt for review.

## Privacy and licenses

All processing is on the device and idlens makes no network calls. Photos are
kept only in the app's temporary folder until you call dispose or the system
clears it.

idlens is released under the MIT license. The bundled OCR models are PaddleOCR
weights (Apache-2.0) converted to ONNX. Their sources and hashes are listed in
assets/models/paddle/README.md. ML Kit and OpenCV have their own licenses.

## More

- [How it works](doc/how_it_works.md)
- [Changelog](CHANGELOG.md)
- [Report an issue](https://github.com/WaseemAlBizreh/OCR/issues)
