# idlens

[![pub package](https://img.shields.io/pub/v/idlens.svg)](https://pub.dev/packages/idlens)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/WaseemAlBizreh/OCR/blob/HEAD/LICENSE)
![platforms](https://img.shields.io/badge/platforms-Android%20%7C%20iOS-lightgrey)

**Scan identity documents on the phone, with no server.** idlens captures and
reads Sudan ID cards, passports from any country and civil registry
certificates. It checks the MRZ, returns the data as typed fields, and always
gives you the document photos back, ready to upload.

Everything runs on the device. No image or text ever leaves the phone.

## Contents

- [Start here: which way should I use?](#start-here-which-way-should-i-use)
- [Installation](#installation) and [platform setup](#platform-setup)
- [Way 1: `scan...`, everything ready-made](#way-1-scan-everything-ready-made)
- [Way 2: `process...`, you bring the photos](#way-2-process-you-bring-the-photos)
  - [2a. Your own camera screen](#2a-your-own-camera-screen)
  - [2b. Photos that already exist](#2b-photos-that-already-exist)
- [Options](#options)
- [API reference](#api-reference): every public type
- [Time limit](#time-limit)
- [Reading the result](#results)
- [Questions and answers](#questions-and-answers)

## Highlights

- **Three documents:** Sudan ID card (front and back), passport data page (any
  country) and civil registry certificate (A4).
- **Two ways in:** let idlens run the whole flow with one call, or keep your own
  screens and let idlens read your photos.
- **Images always returned:** even when reading fails, you get the pictures, so
  your app can still upload them for manual review.
- **Trustworthy MRZ:** ICAO 9303 check digits are validated, and look-alike
  characters (O and 0, I and 1, S and 5, B and 8) are repaired automatically.
- **Clear results:** typed fields with real dates, a simple status, the reason
  when a photo or document has a problem, and the fields the user should check.
- **Framing checks that work:** blurry, dark, far away or cut-off photos are
  caught before they cost the user a wrong value.
- **Private by design:** OCR runs on the device with PaddleOCR, ML Kit and
  OpenCV. No network calls.

## Start here: which way should I use?

idlens has two ways in. The only question is **who owns the camera screen**.

| | **Way 1: `scan...`** | **Way 2: `process...`** |
|---|---|---|
| In one line | idlens opens its own screens and returns the result | You take the photos, idlens reads them |
| You write | One call | A camera screen, or a picker (see 2a and 2b) |
| Your design and language | idlens' screens, in English | Yours, in any language |
| Tips, camera, preview, retake | Built in | Yours |
| Framing checks (blurry, far, cut off) | Full | Full with your own camera (2a). For finished photos (2b) it depends on the photo |
| Best for | A quick start, prototypes, internal tools | Production apps with their own look, and any app that isn't English-only |

**The same passport, both ways:**

```dart
// Way 1: idlens opens its own screens.
final result = await const IdLens().scanPassport(context);

// Way 2: you take the photo, idlens crops it and reads it.
final result = await const IdLens().processPassport(
  dataPage: DocumentPhoto.camera(photo, box: guide.box, previewSize: cameraArea),
);
```

Both return the same kind of result (a `PassportResult` with a `status`, an
`issue`, the `fieldsToCheck` and the images). Way 1 returns `null` if the user
leaves before capturing anything. Full examples, with error handling, are in
[Way 1](#way-1-scan-everything-ready-made) and [Way 2](#way-2-process-you-bring-the-photos).

**The short answer:**

1. **Your app has no camera screen yet, and English screens are fine?** Use
   `scan...`. It is the fastest way to a working scan, and you can move to your
   own screens later without losing anything.
2. **Your app has its own camera, design or language?** Use `process...` with
   your own camera (2a). This is the best choice for a production app: your UI,
   idlens' reader, the same checks.
3. **You didn't take the photo** (gallery, server, a scan you want to read
   again)? Use `process...` with finished photos (2b).

### Real cases

| The situation | Use | Why |
|---|---|---|
| "I need a working demo for tomorrow." | `scanIdCard(context)` | One line, no screens to build |
| An internal back-office tool, English only | `scan...` | Tips, retake and preview already built |
| A dealer or onboarding app with its own brand, in Arabic | `process...` + [your own camera](#2a-your-own-camera-screen) | Your screens and language, idlens' checks |
| An app where users upload a picture from the gallery | `process...` + [`DocumentPhoto.file`](#2b-photos-that-already-exist) | idlens has no camera to open |
| A backend job that reads documents already stored | `process...` + `DocumentPhoto.file` | No UI at all |
| The reader failed to start, and the user taps "Try again" | `process...` + `DocumentPhoto.file` on the saved images | The photos are fine: read the same files again |

## Installation

Add the package to your app and fetch it:

```
flutter pub add idlens
flutter pub get
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
opens. If you use `process...` with your own camera, your app opens the camera
itself and needs this key too.

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

A small app that runs `scan...` and reads the saved photos with `process...` is
in [example/lib/main.dart](https://github.com/WaseemAlBizreh/OCR/blob/HEAD/example/lib/main.dart).

---

## Way 1: `scan...`, everything ready-made

`scan...` opens idlens' own pages on your app's navigator: an optional page of
photo tips, the camera for each page, a preview where the user can retake, and
the scan itself. When it finishes, you get the result.

| Document | Method | Result |
|---|---|---|
| Sudan ID card (front, then back) | `scanIdCard` | `IdCardResult` |
| Passport, any country | `scanPassport` | `PassportResult` |
| Civil registry certificate (A4) | `scanCivilRegistry` | `CivilRegistryResult` |

```dart
Future<IdCardResult?> scanIdCard(
  BuildContext context, {
  IdCardScanOptions options = const IdCardScanOptions(),
})
```

### Example: a "Scan ID" button

```dart
import 'package:flutter/material.dart';
import 'package:idlens/idlens.dart';

class ScanIdButton extends StatelessWidget {
  const ScanIdButton({super.key});

  Future<void> _scan(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await const IdLens().scanIdCard(context);
      if (result == null) return; // The user left before capturing anything.

      switch (result.status) {
        case ScanStatus.failed:
          // Ask for a retake. result.issue says why.
          messenger.showSnackBar(
            SnackBar(content: Text('Please retake: ${result.issue?.name}')),
          );
        case ScanStatus.incomplete:
          // The user left halfway: some pages were captured, nothing was read.
          break;
        case ScanStatus.needsReview:
        case ScanStatus.verified:
          // Fill your form. Highlight result.fieldsToCheck when it isn't empty.
          print('${result.arabicName} · ${result.nationalNumber}');
      }

      // Upload result.images here, then free the temporary files.
      await result.dispose();
    } on ScanException catch (e) {
      // No image could be captured at all (camera denied or unavailable).
      messenger.showSnackBar(SnackBar(content: Text('Camera: ${e.reason.name}')));
    }
  }

  @override
  Widget build(BuildContext context) => FilledButton.icon(
    onPressed: () => _scan(context),
    icon: const Icon(Icons.badge_outlined),
    label: const Text('Scan ID'),
  );
}
```

- **Returns** a result, or `null` only if the user leaves before capturing
  anything.
- **Throws** a `ScanException` only when no image could be captured, for
  example camera permission denied, a camera failure, or the iOS setup missing.
- If the user goes back after capturing some pages, you get a result with the
  status `incomplete` that holds those images.
- A blurry, dark or cut-off photo is shown to the user before reading, and they
  can retake it or choose Use anyway.
- If the text reader can't start on the phone, the user is told their photos
  are fine and can choose Try again, which reads the same photos again.
- The pages are in English on every phone, and `scan...` has no other camera
  options. When you need your own screens or language, use Way 2.

The same flow exists for the other documents: `scanPassport` (one page: the data
page with the photo and the two MRZ lines) and `scanCivilRegistry` (one A4
page, straightened into a flat sheet for reading when its four corners are
found; this document has no MRZ). Both return `null` if the user leaves before
capturing, and throw like `scanIdCard`.

## Way 2: `process...`, you bring the photos

`process...` reads photos and shows no UI: no screens, no `BuildContext`, no
camera of its own. You give it a `DocumentPhoto` for each page, and
that object says how idlens should treat the photo.

| Document | Method | Result |
|---|---|---|
| Sudan ID card | `processIdCard(front:, back:)` | `IdCardResult` |
| Passport, any country | `processPassport(dataPage:)` | `PassportResult` |
| Civil registry certificate | `processCivilRegistry(page:)` | `CivilRegistryResult` |

```dart
Future<IdCardResult> processIdCard({
  required DocumentPhoto front,
  required DocumentPhoto back,
  Duration? timeout,
})
```

There are two kinds of `DocumentPhoto`. **Pick by who took the photo:**

| Form | The file is | idlens | Use it when |
|---|---|---|---|
| `DocumentPhoto.camera(file, box:, previewSize:)` | The raw photo your own camera took | Crops it around `box`, then reads it | **Your own camera took the photo** |
| `DocumentPhoto.file(file)` | A finished photo | Reads it as it is | You didn't take it with a camera screen you control |

You can mix the two in one call. **Why two forms?** idlens' framing checks (is
the document cut off? too far?) were tuned on photos with a thin strip of
background around the document. If your own camera cuts the photo some other
way, the same card can look cut off, or a far one can look fine, and nothing
tells you. With `DocumentPhoto.camera` you hand over the raw photo and the box
the user fitted the document into, and idlens makes the crop itself, so it is
the same photo `scan...` would give.

- **Returns** a result. Never `null`.
- **Throws** a `ScanException` with the reason `imageUnreadable` if a file does
  not exist. Every other problem, including a file that isn't an image, is
  reported on the result.
- Your files are never changed or deleted. For a `.camera` photo, the result's
  `images` are the **cropped** photos: temporary files that `dispose()`
  deletes, so upload them first. For a `.file` photo, the image is your own file
  and `dispose()` leaves it alone.
- `processPassport` and `processCivilRegistry` work the same way. A tilted or
  distant certificate is straightened to a flat copy for reading; the image on
  the result is the photo as given.

### 2a. Your own camera screen

This is the best choice for a production app. You keep your design, your
language and your flow, and idlens gives you two things:

1. **`DocumentGuide.forPreview(...)`** tells you where to draw the box (and, for
   an ID back or a passport, the MRZ guide). They are the numbers idlens' own
   camera uses, so you never copy them by hand.
2. **`DocumentPhoto.camera(...)`** lets `process...` crop your raw photo around
   that box.

```dart
final guide = DocumentGuide.forPreview(
  kind: DocumentKind.sudanId,
  side: DocumentSide.back,
  previewSize: cameraArea, // the area the camera image fills on screen
);
// guide.box       -> draw this over your camera
// guide.mrzGuide  -> draw this too, when it isn't null (label it "MRZ")
```

#### Example: a passport camera page

A complete camera screen with the `camera` package (run `flutter pub add camera`
in your app; idlens doesn't re-export it). The layout puts the camera
image in an `AspectRatio`, so `previewSize` is exactly the size of what the user
sees. Everything on screen (title, button, language) is yours.

```dart
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:idlens/idlens.dart';

class PassportCameraPage extends StatefulWidget {
  const PassportCameraPage({super.key});

  @override
  State<PassportCameraPage> createState() => _PassportCameraPageState();
}

class _PassportCameraPageState extends State<PassportCameraPage> {
  CameraController? _camera;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final cameras = await availableCameras();
    final controller = CameraController(
      cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.back),
      ResolutionPreset.veryHigh, // high, but not the maximum
      enableAudio: false,
    );
    await controller.initialize();
    await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
    if (!mounted) return controller.dispose();
    setState(() => _camera = controller);
  }

  @override
  void dispose() {
    _camera?.dispose();
    super.dispose();
  }

  Future<void> _capture(DocumentGuide guide, Size previewSize) async {
    setState(() => _busy = true);
    final shot = await _camera!.takePicture();

    // The raw photo goes in with the box. idlens crops and reads.
    final result = await const IdLens().processPassport(
      dataPage: DocumentPhoto.camera(
        File(shot.path),
        box: guide.box,
        previewSize: previewSize,
      ),
      timeout: const Duration(seconds: 30),
    );

    if (mounted) Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: camera == null
            ? const Center(child: CircularProgressIndicator())
            : Center(
                child: AspectRatio(
                  // The sensor reports landscape, so invert its ratio.
                  aspectRatio: 1 / camera.value.aspectRatio,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final previewSize = constraints.biggest;
                      final guide = DocumentGuide.forPreview(
                        kind: DocumentKind.passport,
                        side: DocumentSide.dataPage,
                        previewSize: previewSize,
                      );
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          CameraPreview(camera),
                          CustomPaint(painter: _GuidePainter(guide)),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 16,
                            child: Center(
                              child: FloatingActionButton(
                                onPressed: _busy
                                    ? null
                                    : () => _capture(guide, previewSize),
                                child: _busy
                                    ? const CircularProgressIndicator()
                                    : const Icon(Icons.camera_alt),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
      ),
    );
  }
}

/// Dims everything outside the box, draws its border and the MRZ guide.
class _GuidePainter extends CustomPainter {
  _GuidePainter(this.guide);

  final DocumentGuide guide;

  @override
  void paint(Canvas canvas, Size size) {
    final box = RRect.fromRectAndRadius(guide.box, const Radius.circular(12));
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        Path()..addRRect(box),
      ),
      Paint()..color = Colors.black54,
    );
    canvas.drawRRect(
      box,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    final mrz = guide.mrzGuide;
    if (mrz != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(mrz, const Radius.circular(6)),
        Paint()
          ..color = Colors.amberAccent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(_GuidePainter old) => old.guide.box != guide.box;
}
```

Open it from anywhere, and handle the result as in [Reading the result](#results):

```dart
final result = await Navigator.of(context).push<PassportResult>(
  MaterialPageRoute(builder: (_) => const PassportCameraPage()),
);
```

#### For an ID card: two photos, one call

Capture the front, then the back, and keep both until you read. Draw the guide
with `side: DocumentSide.front` and then `side: DocumentSide.back` (only the back
has an MRZ guide):

```dart
final front = DocumentPhoto.camera(frontShot, box: frontGuide.box, previewSize: area);
final back = DocumentPhoto.camera(backShot, box: backGuide.box, previewSize: area);

final result = await const IdLens().processIdCard(front: front, back: back);

// Upload result.images (the cropped photos), then:
await result.dispose();
```

A certificate is the same with `kind: DocumentKind.civilRegistryCertificate`,
`side: DocumentSide.page` and `processCivilRegistry(page: ...)`.

#### Rules that keep the results good

- **Draw the box from `DocumentGuide`.** It is 86% of the width, in the
  document's shape, and centred, which leaves room for the strip of background.
  A bigger box has no room for it, so the strip is cut at the screen's edge and
  `diagnostics['photoCrop']` says `marginClipped: true`. `maxHeight` makes the
  box smaller when your own buttons need room.
- **`previewSize` is the area the camera image fills on screen**, in the same
  logical pixels as `box`. A camera image shown full screen and cropped to fit
  is fine: the photo is mapped onto it, even when the photo has another shape.
  An image shown whole, with bars around it, needs the image's own size.
- **Use a high but not maximum resolution** (idlens' camera uses
  `ResolutionPreset.veryHigh`), lock the capture to portrait, and let the camera
  focus on the box before the shot.
- **Show your own review screen** if you like. The photo you have is the raw
  camera photo: show it with the box drawn over it, or keep your own thumbnail.
- **Upload `result.images`** before `dispose()`: for a camera photo they are the
  cropped PNG files, and `dispose()` deletes them.
- **Handle camera permission yourself.** Your app opens the camera, so it
  catches a `CameraException` and sends the user to settings. (`scan...` does
  this for you.)

### 2b. Photos that already exist

`DocumentPhoto.file` is for photos you didn't take with a camera screen you
control: a picture from the gallery, an image from your server, or the images of
a `scan...` result that you want to read again. idlens reads the file as it is.

```dart
final result = await const IdLens().processPassport(
  dataPage: DocumentPhoto.file(File(pickedImage.path)),
);

if (result.issue == ScanIssue.readerUnavailable) {
  // The photos are fine: offer to read the same files again.
} else if (result.status == ScanStatus.failed) {
  // Ask for a retake: result.issue says why.
} else {
  // Fill your form, and highlight result.fieldsToCheck.
}
result.dispose(); // leaves your own file alone
```

**Reading a `scan...` result again** (for example after `timedOut`): those
images are already cut, so they go in as `.file`:

```dart
final again = await const IdLens().processIdCard(
  front: DocumentPhoto.file(result.imageFor(DocumentSide.front)!.file),
  back: DocumentPhoto.file(result.imageFor(DocumentSide.back)!.file),
);
```

Keep a thin strip of background around the document (about 6% of its size): a
photo cropped exactly to the document can only be checked from its text, which
is less reliable. Don't use `.file` for a photo your own camera just took: use
`.camera`, so idlens can crop it the way its checks expect.

---

## Options

Each `scan...` method takes an optional options object: `IdCardScanOptions`,
`PassportScanOptions` or `CivilRegistryScanOptions`. The `process...` methods
take no options object: they never open a screen, and take their own `timeout`.

```dart
await const IdLens().scanIdCard(
  context,
  options: const IdCardScanOptions(showTips: false, requireValidMrz: true),
);
```

| Option | Default | What it does |
|---|---|---|
| `showTips` | `true` | Shows the page of photo tips before the camera. When `false`, the camera opens straight away. |
| `timeout` | `null` | How long reading may take. When it passes, the user is offered "Try again". `null` means no limit. The `process...` methods take their own `timeout` (see [Time limit](#time-limit)). |
| `requireValidMrz` | `false` | While the MRZ is missing, of the wrong document or its check digits fail, the user can only retake. When `false`, the user can continue and you decide what to do with the result. Not available for the certificate, which has no MRZ. |

## API reference

Everything below comes from `package:idlens/idlens.dart`. Nothing else is public.

### At a glance

| Type | What it is | Details |
|---|---|---|
| `IdLens` | The entry point. Six methods, no state | [`IdLens`](#idlens-the-entry-point) |
| `DocumentPhoto` | One photo for `process...`: `.camera` or `.file` | [`DocumentPhoto`](#documentphoto) |
| `DocumentGuide` | The box and MRZ guide to draw on your own camera | [`DocumentGuide`](#documentguide) |
| `IdCardScanOptions`, `PassportScanOptions`, `CivilRegistryScanOptions` (base: `ScanOptions`) | Options for the `scan...` methods | [Options](#options) |
| `IdCardResult`, `PassportResult`, `CivilRegistryResult` (base: `ScanOutcome`) | What a scan returns | [Results](#results) |
| `ScanStatus` | `verified`, `needsReview`, `failed`, `incomplete` | [`ScanStatus`](#scanstatus) |
| `ScanIssue` | Why a photo or document has a problem | [`ScanIssue`](#scanissue) |
| `ScannedImage` | One captured page: `side`, `file`, `bytes()` | [`ScannedImage`](#scannedimage) |
| `MrzData`, `MrzFormat` | The machine-readable zone and its check digits | [`MrzData`](#mrzdata) |
| `DocumentKind`, `DocumentSide` | Which document, and which page of it | [Documents and pages](#documents-and-pages) |
| `ScanException`, `ScanFailureReason` | Thrown when there is no image to return | [`ScanException`](#scanexception) |

### `IdLens`: the entry point

`const IdLens()` holds no state: every instance shares the loaded models, so
create it wherever you like.

| Method | Opens screens | Input | Returns |
|---|---|---|---|
| `scanIdCard(context, {options})` | Yes | none (idlens captures front, then back) | `Future<IdCardResult?>` |
| `scanPassport(context, {options})` | Yes | none (idlens captures the data page) | `Future<PassportResult?>` |
| `scanCivilRegistry(context, {options})` | Yes | none (idlens captures the page) | `Future<CivilRegistryResult?>` |
| `processIdCard({front, back, timeout})` | No | two `DocumentPhoto` | `Future<IdCardResult>` |
| `processPassport({dataPage, timeout})` | No | one `DocumentPhoto` | `Future<PassportResult>` |
| `processCivilRegistry({page, timeout})` | No | one `DocumentPhoto` | `Future<CivilRegistryResult>` |

```dart
// Way 1: idlens opens its own screens.
Future<IdCardResult?> scanIdCard(BuildContext context, {IdCardScanOptions options});
Future<PassportResult?> scanPassport(BuildContext context, {PassportScanOptions options});
Future<CivilRegistryResult?> scanCivilRegistry(BuildContext context, {CivilRegistryScanOptions options});

// Way 2: you bring the photos.
Future<IdCardResult> processIdCard({required DocumentPhoto front, required DocumentPhoto back, Duration? timeout});
Future<PassportResult> processPassport({required DocumentPhoto dataPage, Duration? timeout});
Future<CivilRegistryResult> processCivilRegistry({required DocumentPhoto page, Duration? timeout});
```

| | `scan...` | `process...` |
|---|---|---|
| Returns `null` | Only when the user leaves before capturing anything | Never |
| Throws `ScanException` | `permissionDenied`, `cameraUnavailable`, `missingSetup`, only when no image could be captured | `imageUnreadable`, when a photo's file doesn't exist |
| Time limit | `timeout` in the options | `timeout` parameter |
| Options object | Yes | No |

### `DocumentPhoto`

One photo handed to a `process...` method.

| Member | Meaning |
|---|---|
| `DocumentPhoto.camera(File file, {required Rect box, required Size previewSize})` | A raw photo from your own camera. idlens crops it around `box`, then reads it. Throws `ArgumentError` when `previewSize` or `box` is empty, or `box` reaches outside `previewSize`. |
| `DocumentPhoto.file(File file)` | A finished photo, read as it is. |
| `file` | The photo file. Never changed or deleted by idlens. |

See [Way 2](#way-2-process-you-bring-the-photos) for when to use which.

### `DocumentGuide`

Where to draw the document box on your own camera screen.

```dart
DocumentGuide.forPreview({
  required DocumentKind kind,
  required DocumentSide side,
  required Size previewSize,
  double? maxHeight,
})
```

| Member | Meaning |
|---|---|
| `box` | The document box, in the same logical pixels as `previewSize`: 86% of the width, in the document's shape, centred. |
| `mrzGuide` | The strip along the bottom of `box` where the MRZ lines should sit. `null` for a page with no MRZ (an ID front, a certificate). |
| `previewSize` (argument) | The area the camera image fills on screen. |
| `maxHeight` (argument) | Limits the box's height when your buttons need room. The box then shrinks and keeps its shape. |

`forPreview` throws `ArgumentError` when `previewSize` is empty, `maxHeight` is
not positive, or `side` is not a page of `kind`.

### `ScannedImage`

| Member | Meaning |
|---|---|
| `side` | Which page (`DocumentSide`) |
| `file` | The image file (JPEG or PNG) |
| `isTemporary` | `true` when idlens made the file. `dispose()` deletes only those |
| `bytes()` | The file's content, for uploads that need bytes |
| `toJson()` | `{side, path}` |

### `MrzData`

`result.mrz` for an ID card or passport, when the MRZ was found.

| Member | Meaning |
|---|---|
| `format` | `MrzFormat.td1` (ID card, 3 lines of 30) or `MrzFormat.td3` (passport, 2 lines of 44) |
| `lines` | The MRZ lines as read, after repair |
| `documentCode`, `issuingCountry`, `documentNumber`, `nationality`, `sex` | The MRZ fields |
| `surname`, `givenNames`, `fullName` | The name |
| `dateOfBirth`, `expiryDate` | `yyyy-MM-dd`, or the raw `yyMMdd` when the digits aren't a real date |
| `optionalData` | The optional data field |
| `checks` | A `Map<String, bool>`: the result of each check digit (`documentNumber`, `dateOfBirth`, `expiryDate`, `composite`, and `personalNumber` for a passport) |
| `isValid`, `passedChecks` | Whether every check digit passed, and how many did |
| `cutOff` | `true` when the photo cut part of the MRZ off |
| `toJson()` | All of the above as JSON |

### Documents and pages

| `DocumentKind` | Pages (`DocumentSide`) |
|---|---|
| `sudanId` | `front`, `back` (the back holds the MRZ) |
| `passport` | `dataPage` |
| `civilRegistryCertificate` | `page` |

You pass these to `DocumentGuide.forPreview`, and read them from `issueSides`,
`images` and `documentKind` on a result.

### Result classes

`IdCardResult`, `PassportResult` and `CivilRegistryResult` share the members of
`ScanOutcome` (`status`, `issue`, `issueSides`, `fieldsToCheck`, `images`, `mrz`,
`fields`, `diagnostics`, `documentKind`, `scannedAt`, `isVerified`,
`imageFor(side)`, `toJson()`, `dispose()`). The table and the full list of
fields are in [Results](#results).

## Time limit

Every method can stop a read that takes too long. Pass `timeout` to a
`process...` method, or in the options of a `scan...` method. With no
`timeout` (the default), a read has no limit.

```dart
final result = await const IdLens().processIdCard(
  front: front, // a DocumentPhoto
  back: back,
  timeout: const Duration(seconds: 30),
);

if (result.issue == ScanIssue.timedOut) {
  // Reading took too long. The photos are fine: show a message and offer to
  // read them again, or let the user type the details.
}
```

- The limit covers cropping a camera photo as well as reading it.
- When the time passes, the result comes back straight away: `failed`, with
  `ScanIssue.timedOut` and the images. Nothing is thrown.
- The steps left are skipped. A step already running inside the text reader
  can't be interrupted, so it finishes in the background first.
- idlens doesn't choose a value. Reading is slower on low-end phones, so a
  limit that's too short makes every scan fail there. Start generous, log
  `diagnostics['scanMs']` (how long each read took) and lower it from what you
  see.

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
    // For ScanIssue.readerUnavailable and ScanIssue.timedOut the photos are
    // fine: offer to read the same files again instead.
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
| `failed` | Wrong document, not in the frame, the text reader couldn't start, reading took longer than `timeout`, or processing failed. Also when nothing identifying was read: no MRZ on an ID card or passport, or none of a certificate's required fields. | Always set |
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
| `timedOut` | Reading took longer than the `timeout` you passed. The photos are fine: offer to read them again. | ✓ | ✓ | ✓ | `failed` |
| `imageNotClear` | The photo is too dark, blurry or has glare. Also given when the document is in the frame but its MRZ couldn't be read, or a certificate has none of its required fields. | ✓ | ✓ | ✓ | `needsReview`, or `failed` when nothing identifying was read |

An ID card has two photos, so `issue` is the more serious of the two:
`wrongDocument`, then `readerUnavailable`, then `timedOut`, then
`processingFailed`, then
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
| No issue, `processingFailed`, `readerUnavailable` or `timedOut` | Empty: no photo is to blame |

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
| `cameraUnavailable` | `scan...` | The camera failed to start, or there's no usable camera, and the user left without capturing anything. | Suggest closing other apps that use the camera, or offer to pick a photo and use `process...` with `DocumentPhoto.file`. |
| `missingSetup` | `scan...` | iOS only: `NSCameraUsageDescription` is missing from `Info.plist`. It's thrown before any screen opens. | Fix the app's setup. This is a developer error, not something to show users. |
| `imageUnreadable` | `process...` | A photo's file doesn't exist. | Check the file path. A file that exists but isn't a readable image doesn't throw: it gives a `failed` result. |

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

## Questions and answers

**Should I use `scan...` or `process...`?**
Start with `scan...` if English screens are fine: it is one call. Use
`process...` with your own camera when you need your own design or language.
You can switch later: both give the same result type and the same checks.

**A card I placed well is called "cut off". Why?**
The check expects a thin strip of background around the document. If your own
camera cropped the photo exactly to the card, the strip is missing. Pass the raw
photo as `DocumentPhoto.camera` with the box from `DocumentGuide`, and idlens
makes the strip itself. Don't loosen anything to compensate: the same limits
catch real cut-off documents.

**Should I crop the photo myself before calling `process...`?**
No. For a camera photo, give idlens the raw photo and the box. A photo you cut
yourself reaches idlens as a `DocumentPhoto.file`, and idlens can't know how it
was cut.

**Why is my box smaller than my screen?**
It is 86% of the width on purpose, so there is room for the strip of
background around it. Use the box from `DocumentGuide` rather than your own.

**Can I show my own text, colours and language?**
Yes, with `process...` and your own camera screen: everything on screen is
yours. `scan...` is English only and has no styling options.

**Where are my images after a scan?**
In `result.images`. For `scan...` and for `DocumentPhoto.camera` they are
temporary files that idlens made: upload them, then call `dispose()`, which
deletes them. A `DocumentPhoto.file` image is your own file, and `dispose()`
never deletes it.

**Reading failed. Do I still get the photos?**
Yes. A result is returned whenever at least one image exists, with `status`,
`issue` and `fieldsToCheck` explaining what happened. Only a missing camera or
a missing file throws a `ScanException`.

**Reading takes long on some phones.**
Pass a `timeout` (see [Time limit](#time-limit)) and log
`diagnostics['scanMs']`. When it passes you get `ScanIssue.timedOut`, and the
photos are fine: offer to read them again.

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

- [How it works](https://github.com/WaseemAlBizreh/OCR/blob/HEAD/doc/how_it_works.md): the steps from a photo to a result, in detail
- [Changelog](https://pub.dev/packages/idlens/changelog)
- [Example app](https://github.com/WaseemAlBizreh/OCR/blob/HEAD/example/lib/main.dart)
- [Report an issue](https://github.com/WaseemAlBizreh/OCR/issues)
