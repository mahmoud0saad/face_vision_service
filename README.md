# face_vision_service

Portable Flutter package for face analysis: detection, age/gender classification, eye open/closed state, and **stable face IDs** across multiple images. All heavy OpenCV work runs in a **background isolate** so your app UI stays responsive.

Requires Flutter SDK — add as a dependency to your Flutter app.

## Features

- Face detection (YuNet, `FaceDetectorYN`)
- Age and gender classification (GoogleNet ONNX models)
- Per-eye state: `open`, `closed`, or `unknown` (Laplacian sharpness heuristic)
- **Stable `id` per face** within a session (IoU tracking between `analyze` calls)
- JPEG preview in each result (for UI display)
- Request/response isolate API: start once, analyze many images without reloading models
- **Live camera stream**: periodic auto-capture + analysis via `FaceVisionLiveSession`

## Requirements

### Flutter SDK

- Flutter SDK (package depends on `flutter` for bundled asset loading)
- SDK `^3.9.0`
- Dependency: `opencv_dart` 1.2.4 (native OpenCV must be available on the target platform)

### Bundled model files

Three pretrained ONNX models ship with the package under `lib/assets/models/` (~48 MB total). On first `start()`, they are loaded from package assets and copied to a temp cache directory so OpenCV can load them from disk. No asset or path configuration is needed in your app.

### Startup time and UI

`start()` is intentionally slow on first launch. Expect roughly:

| Phase | First launch | Later launches |
|-------|--------------|----------------|
| Copy ~48 MB models to cache | 3–20 s (skipped when cache exists) | Skipped |
| Spawn worker + load 3 DNN models | 10–60 s depending on device | Same each session |

**Always show a loading screen** while `await client.start()` runs. The UI may still feel sluggish on low-RAM devices during DNN load because CPU and memory spike system-wide — this is normal.

Use `onStartupProgress` to drive a progress indicator:

```dart
await client.start(
  onStartupProgress: (stage, progress) {
    // stage: 'spawning_isolate' | 'copying_models' | 'loading_dnn'
    // progress: 0.0–1.0 during copying_models, null otherwise
    print('$stage ${progress ?? ''}');
  },
);
```

Call `start()` once at app launch (not before every frame). Subsequent `analyze()` calls are fast.

| File | Role |
|------|------|
| `face_detection_yunet_2023mar.onnx` | YuNet face detector (~0.2 MB) |
| `age_googlenet.onnx` | Age classifier, GoogleNet (~24 MB) |
| `gender_googlenet.onnx` | Gender classifier, GoogleNet (~24 MB) |

Models are declared in the package `pubspec.yaml` and loaded automatically on `start()`.

## Installation

### Git dependency (recommended)

Add to your app's `pubspec.yaml`:

```yaml
dependencies:
  face_vision_service:
    git:
      url: https://github.com/mahmoud0saad/face_vision_service.git
      ref: v0.1.0
```

Then run:

```bash
flutter pub get
```

Pin `ref` to a tag (e.g. `v0.1.0`), a branch (e.g. `main`), or a commit SHA.

### Path dependency (local dev)

```yaml
dependencies:
  face_vision_service:
    path: D:/StudioProjects/StudioProjects/face_vision_service
```

Or a sibling folder relative to your app:

```yaml
dependencies:
  face_vision_service:
    path: ../face_vision_service
```

### Copy into your project

Copy this entire folder (including `lib/assets/models/`), add a `path:` dependency as above, and run `flutter pub get`.

## Quick start

```dart
import 'package:face_vision_service/face_vision_service.dart';

Future<void> run() async {
  final client = FaceVisionServiceClient();

  // 1) Start once — spawn isolate + load bundled models (slow)
  await client.start();

  // 2) Analyze images — fast, same isolate, no reload
  final result = await client.analyze(RawImage(
    bgrBytes: myBgrBuffer, // length = width * height * 3
    width: 640,
    height: 480,
  ));

  for (final face in result.faces) {
    print('#${face.id} ${face.genderLabel} ${face.ageLabel} '
        'eyes L:${face.leftEyeState} R:${face.rightEyeState}');
  }

  // 3) Optional: clear ID tracking (IDs restart from 1)
  await client.resetTracker();

  // 4) Stop when done — shutdown isolate
  await client.dispose();
}
```

### Recommended lifecycle

| Step | Call | Cost |
|------|------|------|
| Once at session start | `start()` | Slow (isolate + model load) |
| Per image | `analyze(rawImage)` | Fast |
| New identity session | `resetTracker()` | Instant |
| End session | `dispose()` | Releases isolate |

Do **not** call `start()` before every image — that reloads everything.

## Live camera stream

Use [`FaceVisionLiveSession`](lib/src/live/face_vision_live_session.dart) to open the camera, run internal confirmation sampling, and emit **confirmed** face results on a user-defined interval.

```dart
import 'package:face_vision_service/face_vision_service.dart';

Future<void> runLive() async {
  final session = FaceVisionLiveSession();

  await session.start(
    intervalSeconds: 3.0,
    confirmSamplingIntervalSeconds: 0.1,
    includePreviewJpeg: false, // skip JPEG encode for better performance
    onStartupProgress: (stage, progress) => print('$stage $progress'),
  );

  final subscription = session.results.listen(
    (result) {
      print('${result.faces.length} faces at ${result.width}x${result.height}');
      for (final face in result.faces) {
        print('#${face.id} ${face.genderLabel} ${face.ageLabel}');
      }
    },
    onError: (e, st) => print('Analysis error: $e'),
  );

  // ... run while needed ...

  await subscription.cancel();
  await session.stop(); // closes camera and results stream
  await session.dispose(); // also shuts down vision isolate
}
```

## Live preview widget (Flutter, optional feature)

This is an **opt-in, additive feature** that does not change the `results`
analysis behavior described above. When enabled, the session also taps each
internally grabbed raw BGR frame onto `session.previewFrames` for a live feed.
The package ships a drop-in widget, [`FaceVisionLivePreview`](lib/src/widgets/face_vision_live_preview.dart),
that renders this feed and draws the detected face boxes/labels on top:

```dart
import 'package:flutter/material.dart';
import 'package:face_vision_service/face_vision_service.dart';

// Start the session with the preview feature enabled.
await session.start(intervalSeconds: 0.5, enablePreview: true);

Widget build(BuildContext context) {
  return FaceVisionLivePreview(
    session: session,
    showLabels: true,            // draw "#id Gender Age" above each box
    boxColor: Colors.greenAccent,
    fit: BoxFit.contain,         // or BoxFit.cover / BoxFit.fill
    // labelBuilder: (face) => '#${face.id} ${face.genderLabel}',
  );
}
```

The widget subscribes to `previewFrames` + `results` itself, decodes frames to
images on the fly (dropping frames while a decode is in flight), and
re-subscribes automatically across `start()`/`stop()` cycles.

### Enabling / disabling the preview

The preview feed is **off by default**. Enable it at `start()` or toggle it at
runtime:

```dart
await session.start(intervalSeconds: 0.5, enablePreview: true); // on at start
session.setPreviewEnabled(false);          // turn it on/off at runtime
final on = session.previewEnabled;         // current state
```

When disabled, `results` (face analysis) keeps flowing unchanged; only
`previewFrames` emission is paused.

| Parameter | Description |
|-----------|-------------|
| `intervalSeconds` | How often **confirmed** results are emitted on `results` (minimum `0.5`) |
| `confirmSamplingIntervalSeconds` | Extra pause after each internal analyze completes (default `0.1`, minimum `0.0` for max throughput) |
| `deviceIndex` | Camera device index (default `0`) |
| `enablePreview` | Opt-in live preview (default `false`); when `true`, emits raw frames on `previewFrames`; can be toggled later via `setPreviewEnabled()` |
| `includePreviewJpeg` | When `false` (default for live), skips JPEG encoding in results |
| `onStartupProgress` | Same as `FaceVisionServiceClient.start()` |

**Behavior:**

- Internal sampling runs continuously between emissions to confirm gender and age (not limited to one image per `intervalSeconds`).
- Stream events fire every `intervalSeconds`; each event includes only faces where **both** gender and age are confirmed for that ID.
- If a face is not confirmed before an emission tick, it is **omitted** from that event (`faces` may be empty).
- Empty camera frames are skipped during internal sampling.
- Only one analyze runs at a time.
- Face IDs and locked labels stay stable across stream events within one session.
- To change intervals, call `stop()` then `start()` with new values.

**Internal check timing (typical):**

| Component | Typical range |
|-----------|----------------|
| Camera grab | ~20–50 ms |
| DNN pipeline (1 face) | ~50–250 ms |
| **Total per internal check** | **~80–300 ms** |

Effective gap between internal checks: `analyzeDuration + confirmSamplingIntervalSeconds`. Use `confirmSamplingIntervalSeconds: 0.0` for the fastest confirmation on capable hardware.

## Public API

Export entry: `package:face_vision_service/face_vision_service.dart`

### `FaceVisionServiceClient`

| Method / property | Description |
|-------------------|-------------|
| `bool isRunning` | `true` after `start`, until `dispose` |
| `Future<void> start({VisionDetectionConfig? detectionConfig, StartupProgressCallback? onStartupProgress})` | Spawn worker isolate and load bundled DNN models |
| `Future<FaceAnalysisResult> analyze(RawImage image, {bool includePreviewJpeg = true})` | Detect + classify one BGR frame |
| `Future<void> resetTracker()` | Clear face ID tracks (session reset) |
| `Future<void> dispose()` | Send shutdown, kill isolate |

### Input: `RawImage`

- `bgrBytes`: raw BGR pixels, row-major, `width * height * 3` bytes
- `width`, `height`: image dimensions in pixels

### Output: `FaceAnalysisResult`

| Field | Type | Description |
|-------|------|-------------|
| `width`, `height` | `int` | Input image size |
| `faces` | `List<DetectedFace>` | All detected faces |
| `previewJpeg` | `Uint8List?` | JPEG of the analyzed frame (quality 80); omitted when `includePreviewJpeg: false` |

### `FaceVisionLiveSession`

| Method / property | Description |
|-------------------|-------------|
| `Stream<FaceAnalysisResult> results` | Confirmed-face events on the emission interval (available after `start()`) |
| `bool isRunning` | `true` while camera capture loop is active |
| `FaceVisionServiceClient client` | Underlying vision client |
| `Future<void> start({required double intervalSeconds, double confirmSamplingIntervalSeconds, ...})` | Start vision service, open camera, begin internal sampling and periodic emission |
| `Future<void> stop()` | Stop capture, close camera, close results stream |
| `Future<void> dispose()` | `stop()` plus dispose vision client when session created it |

### `DetectedFace`

| Field | Type | Description |
|-------|------|-------------|
| `id` | `int` | Stable within tracker session (see below) |
| `x`, `y`, `width`, `height` | `int` | Bounding box in pixel coordinates |
| `genderLabel` | `String` | `"M"` or `"F"` (smoothed across frames), or `""` when gender inference was skipped (e.g. face below `minGenderFacePx`) |
| `ageLabel` | `String` | e.g. `"25-35"` when confirmed; `""` before confirmation |
| `detectionScore` | `double` | Face detector confidence |
| `leftEyeState`, `rightEyeState` | `String` | `"open"`, `"closed"`, or `"unknown"` |
| `maleProbability` | `double` | Smoothed `P(male)` in `[0,1]`; `0` when gender inference was skipped |
| `genderConfidence` | `double` | Confidence of `genderLabel` (`max(p, 1-p)`); `0` when skipped |

### `FaceTracker` (exported, optional)

Pure-Dart tracker used inside the isolate. You normally do not instantiate it in the app; use `resetTracker()` on the client instead. Exported for testing or custom pipelines.

---

## How it works inside

### High-level architecture

```mermaid
flowchart TB
  subgraph mainIsolate [Main isolate - your app]
    Client[FaceVisionServiceClient]
  end

  subgraph workerIsolate [Worker isolate]
    Entry[serviceIsolateEntry]
    Vision[OpenCvVisionDatasource]
    Tracker[FaceTracker]
    Entry --> Vision
    Vision --> Tracker
  end

  Client -->|"SendPort messages"| Entry
  Entry -->|"result / ready / error"| Client
```

1. **Main isolate** owns `FaceVisionServiceClient` and your UI / camera.
2. **Worker isolate** owns OpenCV `Net` objects, inference, and `FaceTracker` state.
3. Images and results cross the boundary as maps + `Uint8List` (no shared memory).

### Isolate protocol

Messages are `Map` with `cmd` (main → worker) or `type` (worker → main).

| Direction | Command / type | Payload | Meaning |
|-----------|----------------|---------|---------|
| → worker | `init` | `modelBytes` | Read bundled assets on main isolate, write to cache in worker, then load |
| → worker | `init` | — | Fallback: copy bundled models from package URI in worker, then load |
| ← main | `progress` | `stage`, `progress` | Startup progress (`copying_models`, `loading_dnn`) |
| ← main | `ready` | — | Models loaded |
| → worker | `analyze` | `bgrBytes`, `width`, `height`, `includePreviewJpeg` (optional, default `true`) | Run pipeline on one frame |
| ← main | `result` | `data` (FaceAnalysisResult map) | Success |
| → worker | `resetTracker` | — | Clear track list |
| ← main | `ok` | — | Tracker reset |
| → worker | `shutdown` | — | Exit isolate |
| ← main | `stopped` | — | Worker exited |
| ← main | `error` | `message` | Failure on init or analyze |

Handshake: worker sends its `SendPort` first; client then sends `init`.

### Analyze pipeline (per image)

Inside the worker ([`service_isolate_entry.dart`](lib/src/isolate/service_isolate_entry.dart)):

```
RawImage (BGR bytes)
    → cv.Mat
    → OpenCvVisionDatasource.detectAndClassify()
         → YuNet face detection (optional downscale to processMaxWidth, default 960)
         → drop faces below minClassifyFacePx / minClassifyFaceArea (original-frame px)
         → per face: age on a padded square 224×224 crop of the ORIGINAL frame,
           gender on a dedicated crop (configurable margin → optional eye-landmark
           alignment → lighting preprocessing) with a softmax confidence,
           eye Laplacian/EAR heuristic
    → FaceTracker.assign()  → stable ids + per-track gender probability smoothing
    → optional JPEG encode preview (when includePreviewJpeg is true)
    → FaceAnalysisResult → SendPort
```

### Vision stack ([`opencv_vision_datasource.dart`](lib/src/datasources/opencv_vision_datasource.dart))

| Step | Model / method |
|------|----------------|
| Detect faces | YuNet `FaceDetectorYN` (input size set per frame); score threshold `0.5`, work frame downscaled to `processMaxWidth` (960) for better small/distant-face recall |
| Reject tiny faces | Faces below `minClassifyFacePx` (32 px) or `minClassifyFaceArea` (32×32) in **original** frame coordinates are dropped before classification |
| Age | GoogleNet ONNX net on a **padded, square** 224×224 crop taken from the **original** (full-resolution) frame via `squareFaceCropRect` (`kAgeGenderCropPadFraction` = 0.4), RGB input (BGR frame swapped via `swapRB`), mean (104, 117, 123) in R,G,B order |
| Gender | Same GoogleNet net, but on a **dedicated** crop driven by [`GenderPipelineConfig`](lib/src/entities/gender_pipeline_config.dart): configurable margin → optional eye-landmark alignment → lighting preprocessing (gamma / CLAHE / auto-contrast). Skipped below `minGenderFacePx` (80). Softmax `P(male)` is smoothed across frames into a concrete `M`/`F`; the smoothed confidence is exposed on the face as advisory metadata. See [Gender classification accuracy pipeline](#gender-classification-accuracy-pipeline) |
| Age ranges | 8 Adience buckets remapped to custom ranges (`0-10 … 50-70`) via [`vision_constants.dart`](lib/src/vision_constants.dart) `kAgeCustomRanges` |
| Eyes | [`eye_state_analyzer.dart`](lib/src/datasources/eye_state_analyzer.dart) — ROI above face, Laplacian std-dev vs threshold |

Tunable constants live in [`vision_constants.dart`](lib/src/vision_constants.dart) (confidence threshold, processing width, min classify size/area, age/gender crop padding, max faces, eye threshold, etc.). Detection-time values are also overridable per session via [`VisionDetectionConfig`](lib/src/entities/vision_detection_config.dart).

### Stable face IDs and label locking ([`face_tracker.dart`](lib/src/tracking/face_tracker.dart))

Tracker state lives **only in the worker isolate** for the lifetime of `start()` … `dispose()`.

1. Each detection gets a temporary box + attributes (`id = 0`).
2. `FaceTracker.assign()` matches boxes to previous tracks using **IoU** (default threshold `0.3`).
3. Matched face → **reuse** the same `id`.
4. Unmatched detection → new `id` (incrementing from 1).
5. Tracks missed for 15 consecutive analyzes are dropped (default `maxMissedFrames`).
6. `resetTracker()` clears all tracks; next IDs start at 1.

**Age** locks after `kLabelConfirmFrames` consecutive agreeing analyze results for the same track. Until locked, `ageLabel` is `""`; after lock it stays fixed for that ID until `resetTracker()`.

**Gender** is *not* hard-locked. Instead, each track keeps a short ring buffer (`smoothingWindow`, default `7`) of the model's per-frame `P(male)` and reports the averaged result (always a concrete `M`/`F`) every analyze, so the displayed value adapts but does not flicker. The averaged confidence (`max(p, 1-p)`) is surfaced on the face as `genderConfidence` for optional downstream filtering. The history lives on the track, so it is discarded automatically when the face disappears (after `maxMissedFrames`) — a re-appearing face starts a fresh history. See [Gender classification accuracy pipeline](#gender-classification-accuracy-pipeline).

Eye states (`leftEyeState`, `rightEyeState`) update every analyze.

Same person in a similar position across two `analyze` calls → same `id`. IDs are **not** persisted across `dispose()` or app restarts.

### Gender classification accuracy pipeline

The gender path is enhanced **without retraining or replacing the model**. Every enhancement targets either *input quality* (so the network sees crops closer to its training distribution) or *output stability* (so a single noisy frame cannot flip the label). All knobs live in a single object, [`GenderPipelineConfig`](lib/src/entities/gender_pipeline_config.dart), nested in [`VisionDetectionConfig`](lib/src/entities/vision_detection_config.dart) as `.gender`, and each is independently toggleable for A/B testing.

```mermaid
flowchart TD
    Detect["YuNet detect (box + 5 landmarks)"] --> Gate{"w/h >= minGenderFacePx?"}
    Gate -->|no| Skip["genderLabel = '' (inference skipped)"]
    Gate -->|yes| Crop["square crop, faceMarginFraction margin"]
    Crop --> Align{"alignmentEnabled & eyes valid?"}
    Align -->|yes| Warp["deskew via eye landmarks (warpAffine)"]
    Align -->|no| Pre
    Warp --> Pre["preprocess: gamma -> CLAHE -> autoContrast"]
    Pre --> Infer["genderNet.forward() -> softmax P(male)"]
    Infer --> Smooth["per-track ring buffer (smoothingWindow) -> avg"]
    Smooth --> Label["M / F (avg >= 0.5 ? M : F)"]
    Label --> Conf["genderConfidence = max(avg, 1-avg) as metadata"]
```

#### Why each enhancement

| Enhancement | Config field(s) | Reasoning |
|-------------|-----------------|-----------|
| **Configurable face margin** | `faceMarginFraction` (0.2) | The Adience/Levi-Hassner gender model was trained on face crops with surrounding context. A tight detector box omits hair/jaw cues; expanding 15–25% per side (clamped to frame bounds) restores them. Kept separate from the age crop so age behavior is unchanged. |
| **Lighting preprocessing** | `preprocessEnabled`, `gammaEnabled`, `gamma`, `gammaDarkThreshold`, `claheEnabled`, `claheClipLimit`, `claheTileGrid`, `autoContrastEnabled` | Difficult lighting is a top cause of misclassification. Gamma (applied only when crop mean-luma < `gammaDarkThreshold`) brightens under-exposed faces; CLAHE on the luma channel restores local contrast without blowing out highlights; optional auto-contrast stretches the dynamic range. Applied **only to the small crop** to stay cheap. |
| **Optional alignment** | `alignmentEnabled` | YuNet already emits 5 landmarks; using the two eyes to deskew in-plane roll matches the upright training faces. Modular and off by default (a no-op when landmarks are missing or roll is negligible). |
| **Temporal smoothing** | `smoothingWindow` (7) | A single frame can be noisy. Averaging `P(male)` over the last N frames per tracked face (probability averaging is preferred over majority voting because it preserves confidence) yields a stable label. History is per-track and discarded on disappearance. |
| **Confidence threshold** | `confidenceThreshold` (0.65) | Advisory only: the pipeline always emits a concrete `M`/`F`, and the smoothed confidence is surfaced as `genderConfidence` so consumers can apply their own low-confidence filtering if desired. |
| **Minimum face size** | `minGenderFacePx` (80) | Crops below ~80 px lack the detail for reliable gender; below this, gender inference is skipped entirely (the face still gets age/eye-state). |

#### Configuration example

```dart
const config = VisionDetectionConfig(
  gender: GenderPipelineConfig(
    faceMarginFraction: 0.2,
    preprocessEnabled: true,
    gammaEnabled: true,
    gamma: 1.2,
    claheEnabled: true,
    claheClipLimit: 2.0,
    claheTileGrid: 8,
    autoContrastEnabled: false,
    confidenceThreshold: 0.65,
    minGenderFacePx: 80,
    smoothingWindow: 7,
    alignmentEnabled: false,
  ),
);
await client.start(detectionConfig: config);
```

For A/B testing, flip a single flag (e.g. `claheEnabled: false`) and compare; each stage is isolated so differences are attributable.

#### Performance and measured impact

Preprocessing runs on the 224×224 crop only, the gamma LUT and CLAHE instance are cached/reused across frames, and intermediate `Mat`s are disposed eagerly, so steady-state allocation is bounded. Per-step latency is measured by [`test/gender_preprocess_benchmark_test.dart`](test/gender_preprocess_benchmark_test.dart) (tagged `opencv`; it runs where the OpenCV native library is available and skips otherwise). Run and record results with:

```bash
flutter test test/gender_preprocess_benchmark_test.dart
```

Record observed numbers here for your target device:

| Step | Added latency (ms / face) | Notes |
|------|---------------------------|-------|
| Gamma (LUT) | _TBD_ | only when crop is dark |
| CLAHE | _TBD_ | luma channel only |
| Auto-contrast | _TBD_ | off by default |
| Alignment | _TBD_ | off by default |

| Configuration | Gender accuracy | Notes |
|---------------|-----------------|-------|
| Baseline (preprocessing off, no smoothing) | _TBD_ | reference |
| + margin + CLAHE + gamma | _TBD_ | input-quality only |
| + smoothing + confidence threshold | _TBD_ | full pipeline |

### Package layout

```
face_vision_service/
├── pubspec.yaml
├── README.md
└── lib/
    ├── assets/models/                # bundled OpenCV models
    ├── face_vision_service.dart      # public exports
    └── src/
        ├── bundled_models.dart
        ├── vision_constants.dart
        ├── entities/
        │   ├── model_paths.dart
        │   ├── raw_image.dart
        │   ├── detected_face.dart
        │   ├── gender_pipeline_config.dart   # single gender-accuracy config object
        │   ├── vision_detection_config.dart
        │   └── face_analysis_result.dart
        ├── datasources/
        │   ├── opencv_vision_datasource.dart
        │   ├── face_preprocessor.dart        # gamma / CLAHE / auto-contrast
        │   ├── face_aligner.dart             # optional eye-landmark alignment
        │   ├── face_box_geometry.dart        # margin / square crop helpers
        │   └── eye_state_analyzer.dart
        ├── tracking/
        │   └── face_tracker.dart
        ├── live/
        │   └── face_vision_live_session.dart
        └── isolate/
            ├── service_client.dart       # main-isolate API
            └── service_isolate_entry.dart  # worker entry (top-level)
```

## Integration example (Flutter app)

The reference app [`face_vision`](../face_vision-master/) wraps this package:

- **Client**: [`lib/main.dart`](../face_vision-master/lib/main.dart) constructs `FaceVisionServiceClient()` and wires it through the repository layer
- **Adapter**: [`lib/data/repositories/face_analysis_repository_impl.dart`](../face_vision-master/lib/data/repositories/face_analysis_repository_impl.dart) maps service types to domain entities
- **Live capture**: camera stays open on the UI isolate; every 2s sends `RawImage` to `analyze()` while the service isolate keeps running

```dart
// App-side pattern (simplified)
await repository.startService();  // once
final frame = await camera.grab(); // repeated, camera already open
final detected = await repository.analyze(frame);
await repository.stopService();
```

## Limitations

- **One analyze at a time** per client instance (single `_analyzeCompleter`). Overlapping `analyze()` calls are not queued; wait for the previous future or skip ticks in your loop.
- **BGR only** input; no automatic RGBA/JPEG decode in the package.
- **Session-scoped IDs** only (IoU on boxes, not face embeddings).
- **Platform**: depends on `opencv_dart` native bindings (desktop/mobile support follows that package).
## License

MIT — see [LICENSE](LICENSE).
