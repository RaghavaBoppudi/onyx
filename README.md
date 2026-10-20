# Onyx

A camera app for iPhone with one opinionated look. There are no sliders and no filters to pick: the app captures RAW where the sensor allows it, develops it with its own tone curve and colour response, and saves a HEIC to Photos.

Requires iOS 26 and Xcode 26 (Liquid Glass UI).

## What it does

- **One look, four modes.** Default, Mono, Double (a true two-frame double exposure, held at −1 EV) and Double Mono.
- **Dual capture.** Rear and front cameras at once, as picture-in-picture or split, on devices that support multi-cam.
- **Lens switching.** The lens picker is derived from the virtual device's constituents, so it adapts to the hardware.
- **Front camera.** Center Stage ultra-wide with a 3:4 dynamic aspect ratio.
- **Hardware shutter.** Volume buttons and Camera Control via `AVCaptureEventInteraction`.
- **Location is opt-in** and only tags photos you take.

## How a photo is made

1. Capture: Bayer RAW when the lens supports it, otherwise the ISP's HEVC output.
2. Decode: `CIRAWFilter` with Apple's tone mapping, noise reduction and sharpening switched off.
3. Look: a monotone cubic tone curve plus per-channel response, sampled into a 64-point lookup table and applied with `CIColorCurves`; then saturation. Mono uses a luma matrix, and Double Mono adds a Metal colour kernel that mimics a blue filter.
4. Save: HEIC, sRGB, quality 0.92, with EXIF carried over from the capture, written through `PHAssetCreationRequest`.

## Architecture

```
Onyx/
├─ App/          OnyxApp, LaunchGate (splash + permissions), RootView
├─ Camera/
│  ├─ Engine/    CaptureEngine, DualCaptureEngine, RawPipeline, CameraEventMonitor
│  ├─ Model/     Lens, CaptureMode
│  ├─ Orientation/
│  ├─ Output/    PhotoLibrary, LocationProvider
│  ├─ Preview/
│  └─ Render/    LookRenderer, LookProfile, PhotoMetadata, Kernels.metal
├─ State/        CameraModel, DevelopQueue, Permissions, AppSettings
├─ Design/       tokens: accent, metrics, glyph rotation
├─ Feedback/     haptic events
├─ Support/      logging, background time
└─ UI/           ViewfinderScreen and its controls
```

- **Concurrency.** `CaptureEngine` and `DualCaptureEngine` are actors running on dedicated serial `DispatchSerialQueue` executors, so AVFoundation calls stay on the session queue. Photo-delegate state is guarded by `Mutex`. `LookRenderer` is an actor with one shared `CIContext`.
- **Backpressure.** `DevelopQueue` allows three photos in flight and holds a background task for each, so leaving the app mid-save does not lose a shot.
- **Resilience.** `CameraEventMonitor` turns session interruptions, runtime errors and thermal pressure into events. The model pauses the shutter during an interruption, restarts the session after a runtime error, and leaves dual capture when the device runs hot.
- **Privacy.** Everything runs on the device. There is no network code, no analytics and no tracking. Camera and Photos are required; Location is optional.

## Testing

`OnyxTests` uses Swift Testing: curve maths, layout geometry, orientation mapping, event decoding and end-to-end renders of the look (mono really is mono, metadata survives). Run them with ⌘U or `xcodebuild test`.

## Known gaps

- `CameraModel` still carries several parallel state flags. An explicit state machine behind a `CameraService` protocol would make it unit-testable without a camera.
- Strings are marked for localisation but there is no String Catalog yet.
- Photos access is read/write so the thumbnail can show your latest shot; add-only would be enough to save.
