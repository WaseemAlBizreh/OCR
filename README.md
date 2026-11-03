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
- **Clear results:** typed fields with real dates, a simple status, the reason
  when a photo or document has a problem, and the fields the user should check.
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
- If the text reader can't start on the phone, the user is told their photos
  are fine and can choose Try again, which reads the same photos again.

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
- For the best result, crop the card to fill most of the image, with the MRZ
  sharp and fully visible. Keep a thin strip of background (about 6% of the
  card's size) on every side: that's how idlens tells a cut-off card from a
  well-placed one. A photo cropped exactly to the card edges can only be
  checked from its text, which is less reliable. The same applies to
  `processPassport` and `processCivilRegistry`.

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

if (result.issue == ScanIssue.readerUnavailable) {
  // The photos are fine: offer to read the same files again.
} else if (result.status == ScanStatus.failed) {
  // Ask for a retake: result.issue says why.
} else {
  // Fill your form, and highlight result.fieldsToCheck.
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
| `requireValidMrz` | `false` | While the MRZ is missing, of the wrong document or its check digits fail, the user can only retake. When `false`, the user can continue and you decide what to do with the result. Only for the `scan...` methods, and not available for the certificate, which has no MRZ. |

## Results

`IdCardResult`, `PassportResult` and `CivilRegistryResult` all extend
`ScanOutcome`, so the same members are on every result.

| Member | Meaning |
|---|---|
| `status` | `verified`, `needsReview`, `failed` or `incomplete` |
| `issue` | What is wrong with the photo or the document (`ScanIssue`), or `null` |
| `issueSides` | The pages to retake because of `issue` (`DocumentSide`), such as only the back of an ID card |
| `fieldsToCheck` | Keys in `fields` the user should look at |
| `images` | The captured pages (`ScannedImage`: `side`, `file`, `bytes()`). `imageFor(side)` finds one. |
| `mrz` | The MRZ with a result for every check digit in `checks` (ID card and passport) |
| `fields` / `toJson()` | The raw field map, and everything as JSON (image paths, not image content) |
| `diagnostics` | Debug data such as raw OCR text, English `warnings` for logs, and timing. Not a stable API. |
| `dispose()` | Deletes the temporary image files that idlens created |

**You get a result whenever at least one image was captured.** A scan returns
`null` only when the user leaves before capturing anything, and a
`ScanException` is thrown only when no image could be captured. Problems with
reading are never exceptions. They appear as `status`, `issue` and
`fieldsToCheck`, and the images are still there to upload.

### Handling a result

Your app only has to answer two questions: does the user need to retake, and
which fields should they look at? `status` answers the first, and
`fieldsToCheck` the second.

```dart
switch (result.status) {
  case ScanStatus.failed:
    // Ask for a retake. result.issue says why, so you can word the message.
    // For ScanIssue.readerUnavailable the photos are fine: offer to read the
    // same files again instead.
  case ScanStatus.incomplete:
    // The user left before every page was captured. Resume or start again.
  case ScanStatus.needsReview:
    // Show the form and highlight result.fieldsToCheck. If result.issue is
    // ScanIssue.imageNotClear, you can also suggest a retake.
  case ScanStatus.verified:
    // Show the form. Nothing needs checking.
}
```

For a field in `fieldsToCheck`, the value tells you why it's there:

- **The value is `null`:** a required field wasn't read. Ask the user to type it.
- **The value is set:** it was read, but it may be wrong. Ask the user to check it.

### `ScanStatus`

| Value | When | `issue` |
|---|---|---|
| `verified` | No issue, and `fieldsToCheck` is empty. For ID cards and passports, every MRZ check digit passed and the printed values agree with the MRZ. | `null` |
| `needsReview` | The photo isn't clear, or at least one field is in `fieldsToCheck`. | `imageNotClear` or `null` |
| `failed` | Wrong document, not in the frame, the text reader couldn't start, or processing failed. Also when nothing identifying was read: no MRZ on an ID card or passport, or none of a certificate's required fields. | Always set |
| `incomplete` | The user left before every page was captured. Nothing was read. | `null` |

A civil registry certificate has no MRZ, so for it `verified` only means the
photo was good, the required fields were read and the dates agree. It doesn't
prove the values are correct.

### `ScanIssue`

An issue is about the photo or the document as a whole. A doubt about a single
value is never an issue: that field goes in `fieldsToCheck` instead.

| Value | Meaning | ID card | Passport | Certificate | Status |
|---|---|---|---|---|---|
| `wrongDocument` | An MRZ of a different document type was found. | ✓ | ✓ | – | `failed` |
| `documentNotInFrame` | The document is missing, too far away or cut off. | ✓ | ✓ | ✓ | `failed` |
| `processingFailed` | An unexpected error while reading. The images are still returned. | ✓ | ✓ | ✓ | `failed` |
| `readerUnavailable` | idlens couldn't start its text reader on this phone, for example with too little free storage. The photos are fine: offer to read the same files again rather than a retake. The next read loads the reader again. | ✓ | ✓ | ✓ | `failed` |
| `imageNotClear` | The photo is too dark, blurry or has glare. Also given when the document is in the frame but its MRZ couldn't be read, or a certificate has none of its required fields. | ✓ | ✓ | ✓ | `needsReview`, or `failed` when nothing identifying was read |

An ID card has two photos, so `issue` is the more serious of the two:
`wrongDocument`, then `readerUnavailable`, then `processingFailed`, then
`documentNotInFrame`, then `imageNotClear`.

`issueSides` says which photos to retake, so the user doesn't have to retake a
good one:

| Case | `issueSides` |
|---|---|
| The ID back is blurry, the front is fine | `[back]` |
| The ID front is cut off, the back is fine | `[front]` |
| Both ID photos have a problem | `[front, back]`, even when the problems differ |
| No MRZ was found and no photo check failed | The MRZ page (`back`, `dataPage`), or the certificate `page` |
| `wrongDocument` | Every page |
| A passport or certificate photo problem | Its only page |
| No issue, `processingFailed` or `readerUnavailable` | Empty: no photo is to blame |

```dart
for (final side in result.issueSides) {
  // Reopen your camera for this side only.
}
```

### `fieldsToCheck`

A field is listed in these cases:

| Case | Value | ID card | Passport | Certificate |
|---|---|---|---|---|
| A required field wasn't read | `null` | `arabicName`, `nationalNumber` | – | `nationalNumber`, `name`, `dateOfBirth` |
| The printed value differs from the MRZ | The MRZ value | `dateOfBirth`, `expiryDate` | `dateOfBirth`, `expiryDate`, `nationalNumber` | – |
| An MRZ check digit failed | As read | The fields it covers | The fields it covers | – |
| The dates can't be right | Kept as read | `issueDate` on or after `expiryDate` | `issueDate` on or after `expiryDate` | `dateOfBirth` and `issueDate`, when the birth isn't before the issue |
| A date isn't a real calendar date | The text as read | ✓ | ✓ | ✓ |

The check digits cover these fields: `documentNumber`, `dateOfBirth`,
`expiryDate`, and on a passport the personal number (`nationalNumber`). When
only the composite digit fails, `documentNumber`, `dateOfBirth` and
`expiryDate` are all listed.

**These cases are never listed.** The field is `null` and the status doesn't
change:

- An optional field that wasn't read, such as a passport's `placeOfBirth`,
  `issueDate` or `placeOfIssue`, or a certificate's `motherName`. A passport
  has no required fields, because the MRZ carries the identity.
- An ID card `phone` that doesn't have exactly 10 digits.

### Fields

Every field is nullable: a value that couldn't be read is `null`. Dates are
real `DateTime` values, and a date that isn't a real calendar date is `null`
(and listed in `fieldsToCheck`). When a value appears in both the MRZ and the
printed text, the MRZ value is used if its own check digit passed.

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
`nationalityType`, `profession`, `workAddress` and `motherName`.

An expired document isn't an issue. Use `isExpired` if your app has a rule for
it.

### `ScanException`

A `ScanException` means idlens has no image to give you, so there is no result
to return. It's never thrown for a problem with reading: once an image exists,
every problem, including a text reader that can't start
(`ScanIssue.readerUnavailable`), is reported on the result.

| `reason` | Thrown by | When | What your app can do |
|---|---|---|---|
| `permissionDenied` | `scan...` | The user didn't allow camera access, then left the scan screens without capturing anything. | Explain why the camera is needed, and link to the app settings. |
| `cameraUnavailable` | `scan...` | The camera failed to start, or there's no usable camera, and the user left without capturing anything. | Suggest closing other apps that use the camera, or offer to pick a photo and use `process...`. |
| `missingSetup` | `scan...` | iOS only: `NSCameraUsageDescription` is missing from `Info.plist`. It's thrown before any screen opens. | Fix the app's setup. This is a developer error, not something to show users. |
| `imageUnreadable` | `process...` | A file you passed doesn't exist. | Check the file path. A file that exists but isn't a readable image doesn't throw: it gives a `failed` result. |

While the scan screens are open, a camera problem doesn't end the flow: the
user sees what went wrong and can try again. The exception is thrown only if
they leave with nothing captured. If they leave after capturing some pages, you
get a result with the status `incomplete` instead.

```dart
try {
  final result = await const IdLens().scanPassport(context);
  if (result == null) return; // The user left before capturing anything.
  // Handle the result.
} on ScanException catch (e) {
  switch (e.reason) {
    case ScanFailureReason.permissionDenied:
      // Ask for camera access.
    case ScanFailureReason.cameraUnavailable:
      // Suggest trying again, or picking a photo instead.
    case ScanFailureReason.missingSetup:
    case ScanFailureReason.imageUnreadable:
      // A setup or code error: log e.message.
  }
}
```

`message` holds English detail for your logs, such as the camera error code or
the missing file path. Don't show it to users; word your own message from
`reason`.

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
