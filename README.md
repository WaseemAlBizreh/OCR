# idlens

On-device identity document scanner for Flutter. Capture and read **Sudan ID
cards**, **passports from any country** and **civil registry certificates**,
validate the MRZ check digits, and get back a typed result **together with the
document images**, ready to upload.

Everything runs on the phone (PaddleOCR on ONNX Runtime, ML Kit and OpenCV).
**Nothing is sent to any server.**

## Features

- Three scans: ID card, passport and civil registry certificate.
- Two ways to use each: our camera pages, or your own camera / gallery by
  passing image files.
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

### Platform setup

**Android**: nothing to add.

**iOS**: add a usage description to `ios/Runner/Info.plist`. This is the only
required setup step: Apple reads this key from the app's own `Info.plist`, so a
package cannot supply it.

```xml
<key>NSCameraUsageDescription</key>
<string>The camera is used to scan identity documents.</string>
```

If it is missing, the three `scan...` methods throw a `ScanException` with
`reason: missingSetup` that names the key, instead of the app being closed by iOS
when the camera opens.

**Build machine: CMake**: OpenCV is compiled from source when your app is
built, which needs CMake. Android builds use the CMake from the Android SDK.
**iOS builds need CMake installed on the Mac** (`brew install cmake`); without it
the build stops with `Failed to find cmake version: latest`.

**App size**: idlens uses only the `core`, `imgproc` and `imgcodecs` parts of
OpenCV, which is what `opencv_dart` builds by default, so nothing needs to be
configured in your app and the large OpenCV modules (`dnn`, `video`, `calib3d`,
...) are never compiled in. The bundled OCR models add about 12 MB.

The example app builds with iOS 16.0 and the Flutter default Android `minSdk`.
The iOS simulator on Apple Silicon may not run ML Kit; test on a real device.

## Example

[`example/lib/main.dart`](example/lib/main.dart) is a complete app that calls
every API below, with the options as switches and the result shown as JSON.
Read it for the code; this page explains what each API does.

## The APIs

Everything starts from `IdLens`, a stateless class (`const IdLens()`). There are
six methods: for each document, one that **opens our screens** (`scan...`) and
one that **reads files you already have** (`process...`).

| Document | With our screens | From files, no UI | Result type |
|---|---|---|---|
| Sudan ID card | `scanIdCard` | `processIdCard` | `IdCardResult` |
| Passport (any country) | `scanPassport` | `processPassport` | `PassportResult` |
| Civil registry certificate (A4) | `scanCivilRegistry` | `processCivilRegistry` | `CivilRegistryResult` |

### `scanIdCard(BuildContext context, {IdCardScanOptions options})`

Opens the full capture flow on your app's `Navigator`: an optional page of photo
tips, the camera for the **front**, the camera for the **back**, a preview where
the user can retake either side, then the scan. The back holds the MRZ.

- **Returns** `Future<IdCardResult?>`: `null` only if the user leaves before
  capturing anything. Otherwise a result, whatever its `status`.
- **Throws** `ScanException` only when no image could be captured: camera
  permission denied, camera failure, or the iOS usage description missing.
- If the user presses back after capturing some pages, you get an `incomplete`
  result holding those images.
- Before reading, a blurry, dark or cut-off photo is reported to the user, who
  can retake or **Use anyway**.

### `scanPassport(BuildContext context, {PassportScanOptions options})`

The same flow for one page: the **data page** (the page with the photo and the
two MRZ lines). Works for passports from any country. Returns
`Future<PassportResult?>` and throws like `scanIdCard`.

### `scanCivilRegistry(BuildContext context, {CivilRegistryScanOptions options})`

The same flow for one **A4 certificate page**. The camera straightens the page
to a flat sheet when it can find its four corners. There is no MRZ on this
document. Returns `Future<CivilRegistryResult?>` and throws like `scanIdCard`.

### `processIdCard({required File front, required File back, IdCardScanOptions options})`

Reads two photos you already have: no screens, no camera, no `BuildContext`. Use
it with your own camera, a gallery picker, or images that came from a server.

- **Returns** `Future<IdCardResult>`, never null.
- **Throws** `ScanException` with `reason: imageUnreadable` if a file does not
  exist. Every other problem is reported on the result.
- Your files are used as given and are **never deleted** by `dispose()`.
- Photo quality advice still applies: the cropped card should fill the image,
  with the MRZ sharp and fully visible.

### `processPassport({required File dataPage, PassportScanOptions options})`

Same as `processIdCard`, for the passport data page. Returns
`Future<PassportResult>`.

### `processCivilRegistry({required File page, CivilRegistryScanOptions options})`

Same as `processIdCard`, for the certificate page. Returns
`Future<CivilRegistryResult>`.

### Options

Each method takes an options object (`IdCardScanOptions`, `PassportScanOptions`,
`CivilRegistryScanOptions`), all const and all optional.

| Option | Default | Effect |
|---|---|---|
| `showTips` | `true` | Show the page of photo tips before the camera. When `false` the camera opens straight away. `scan...` only. |
| `requireValidMrz` | `false` | The flow only offers **Retake** while the MRZ is missing or its check digits fail. When `false` the user can continue anyway and you decide what to do with the `issues`. `scan...` only; not available on the certificate, which has no MRZ. |

## Results

`IdCardResult`, `PassportResult` and `CivilRegistryResult` all extend
`ScanOutcome`, so the same members work on every result.

| Member | Meaning |
|---|---|
| `status` | `verified`, `needsReview`, `failed` or `incomplete` |
| `issues` | Typed reasons the scan cannot be fully trusted (`ScanIssue`) |
| `warnings` | English detail for logs, such as which value disagrees with the MRZ |
| `images` | The captured pages (`ScannedImage`: `side`, `file`, `bytes()`); `imageFor(side)` finds one |
| `mrz` | The MRZ with per-field `checks` (ID card and passport) |
| `fields` / `toJson()` | The raw field map / everything as JSON (image paths, not image content) |
| `diagnostics` | Debug data such as raw OCR text and timing; not a stable API |
| `dispose()` | Deletes the temporary image files idlens created |

**A result is returned whenever at least one image was captured.** `null` is
returned only when the user leaves before capturing anything, and
`ScanException` is thrown only when no image could be captured (camera
permission denied, camera failure, missing iOS setup, or a file passed to
`process...` that does not exist). Read problems are never exceptions: they show
up as `status` and `issues`, and the images are still there to upload.

### Fields

All fields are nullable: a value that could not be read is `null`. Dates are
`DateTime`s. Where a value exists in both the MRZ and the printed text, the MRZ
value is used when its own check digit passed, and a printed value that
disagrees is reported in `warnings`.

**`IdCardResult`** and **`PassportResult`** (both extend `IdentityDocumentResult`):
`documentNumber`, `nationalNumber`, `arabicName`, `englishName`, `surname`,
`givenNames`, `dateOfBirth`, `sex`, `nationality`, `issuingCountry`, `issueDate`,
`expiryDate`, `placeOfBirth`, `placeOfIssue`, and `isExpired` (true, false, or
null when there is no expiry date).

- `IdCardResult` adds `profession`, `address`, `bloodType`, `phone`.
- `PassportResult` adds `nationalityText`, `nationalityTextArabic`,
  `issuingCountryName`, `placeOfBirthArabic`, `placeOfIssueArabic`.

**`CivilRegistryResult`**: `registryOffice`, `issueDate`, `nationalNumber`,
`name`, `placeOfBirth`, `dateOfBirth`, `maritalStatus`, `gender`,
`nationalityType`, `profession`, `workAddress`, `motherName`, and `confidence`
(0 to 1 per field).

### `ScanStatus`

| Value | Meaning |
|---|---|
| `verified` | No issues or warnings; for ID cards and passports all MRZ check digits passed. |
| `needsReview` | Fields were read but something is off (blurry photo, failed check digit, printed value disagreeing with the MRZ). |
| `failed` | Wrong document, not in the frame, no MRZ found, or a processing error. Images are still returned. |
| `incomplete` | The user left before every page was captured; nothing was read. |

A civil registry certificate has no MRZ: for it `verified` only means the photo
was fine and every expected field was read.

### `ScanIssue`

| Value | Meaning |
|---|---|
| `mrzNotFound` | No MRZ could be read. |
| `wrongDocument` | An MRZ of another document type was found. |
| `documentNotInFrame` | The document is missing, too far, or cut off. |
| `imageNotClear` | Too dark, blurry or glare. |
| `mrzCheckDigitsFailed` | MRZ read, but a check digit failed (`mrz.checks` says which). |
| `processingFailed` | An unexpected error while reading; images are still returned. |

### `ScanException`

| `reason` | When |
|---|---|
| `permissionDenied` | The user did not allow camera access and nothing was captured. |
| `cameraUnavailable` | No usable camera, or it failed to start, and nothing was captured. |
| `missingSetup` | iOS only: `NSCameraUsageDescription` is missing from `Info.plist`. |
| `imageUnreadable` | A file passed to a `process...` method does not exist. |

## Accuracy

Accuracy has so far been checked on very few real documents. Test with your own
before relying on the results, and treat `status != verified` as a prompt to
review.

## Privacy and licenses

All processing is on-device and idlens makes no network calls. It stores the
photos only in the app's temporary folder until you call `dispose()` or the OS
clears it.

idlens is MIT licensed. The bundled OCR models are PaddleOCR weights
(Apache-2.0) converted to ONNX; their sources and hashes are in
`assets/models/paddle/README.md`. ML Kit and OpenCV carry their own licenses.

## More

- [How it works](doc/how_it_works.md)
- [Changelog](CHANGELOG.md)
