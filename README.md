# AI Translator

Real-time conversation translation app — offline translation powered by on-device AI models.

实时对话翻译应用 —— 基于端侧 AI 模型的离线翻译工具。

## Features

- **Fully Offline Translation** — All AI inference runs locally on device, no internet required after model download
- **Streaming Voice Input** — 3-second segment-based ASR with real-time transcription via whisper.cpp
- **Real-time Text Translation** — Type or speak, translation appears automatically with 400ms debounce
- **Auto Language Detection** — fastText detects input language; direction locked on first detection per session
- **Background Translation** — NLLB runs in a dedicated Dart Isolate, keeping UI smooth during inference
- **Translation Deduplication** — Generation counter prevents stale/duplicate translation requests
- **11 Languages** — Chinese, English, Japanese, Korean, French, German, Russian, Spanish, Italian, Thai, Vietnamese
- **Swipeable History** — View and swipe-to-delete past translations
- **Text-to-Speech** — Listen to pronunciation of both source and translated text
- **Copy to Clipboard** — One-tap copy for original or translated text

## Tech Stack

| Component | Technology | Details |
|---|---|---|
| Framework | [Flutter](https://flutter.dev) 3.41.6 | Cross-platform (iOS & Android) |
| ASR | [whisper.cpp](https://github.com/ggerganov/whisper.cpp) 1.8.4 | On-device speech recognition via dart:ffi, 3s segment streaming |
| Translation | [NLLB-200-distilled-600M](https://huggingface.co/Xenova/nllb-200-distilled-600M) | ONNX int8 quantized (~870MB), via background Isolate + onnxruntime |
| Language Detection | [fastText](https://fasttext.cc/) lid.176.ftz | ~917KB bundled model, < 1ms inference via dart:ffi |
| TTS | System TTS | flutter_tts, uses device built-in TTS engine |
| State Management | [Riverpod](https://riverpod.dev/) | flutter_riverpod with StateNotifier |
| Model Download | [HuggingFace](https://huggingface.co/) | On-demand model download via dio with progress UI |

## Architecture

```
+------------------------------------------------------------------+
|                      Flutter App (Dart)                           |
|                                                                   |
|  +----------------+  +-------------------+  +-----------------+  |
|  |ConversationPage|  |ModelDownloadTrigger|  |ConvModePage     |  |
|  | (recording UI, |  | (auto-prompt)     |  | (swipe history) |  |
|  |  pulse anim)   |  +---------+---------+  +-----------------+  |
|  +-------+--------+            |                                  |
|          |                     |                                  |
|  +-------v---------------------v----------------------------+    |
|  |         ConversationProvider (Riverpod)                   |    |
|  |  - _translateGeneration (cancellation counter)            |    |
|  |  - _lockedDirection (first-detection lock)                |    |
|  |  - _lastTranslatingText (deduplication)                   |    |
|  +-------+--------------+--------------+--------------------+    |
|          |              |              |                          |
|  +-------v------+ +----v---------+ +--v-----------------+       |
|  |LanguageDetect | | Translation  | |  ASR Service       |       |
|  |  Service      | |  Service     | |  (whisper.cpp)     |       |
|  |  (fastText)   | |  |           | |  segment-based     |       |
|  +--------------+  |  v           | +--------------------+       |
|                    | Translation  |                               |
|                    |  Isolate (bg)|                               |
|                    +------+-------+                               |
|                           |                                       |
|                    +------v--------------+                        |
|                    | NllbOnnxTranslator   |                        |
|                    | (ONNX Runtime)       |                        |
|                    +---------------------+                        |
+-------------------------------------------------------------------+
```

## Supported Languages

| Flag | Language | NLLB Code | Whisper Code |
|---|---|---|---|
| :cn: | Chinese | zho_Hans | zh |
| :us: | English | eng_Latn | en |
| :jp: | Japanese | jpn_Jpan | ja |
| :kr: | Korean | kor_Hang | ko |
| :fr: | French | fra_Latn | fr |
| :de: | German | deu_Latn | de |
| :ru: | Russian | rus_Cyrl | ru |
| :es: | Spanish | spa_Latn | es |
| :it: | Italian | ita_Latn | it |
| :thailand: | Thai | tha_Thai | th |
| :vietnam: | Vietnamese | vie_Latn | vi |

## Requirements

- Flutter SDK >= 3.5.0, Dart SDK >= 3.2.0
- CMake >= 3.18 (for native library compilation)
- **iOS**: Xcode 15+, iOS 15.0+, CocoaPods
- **Android**: Android Studio, minSdkVersion 24 (Android 7.0+), NDK, CMake via SDK Manager

## Getting Started

### 1. Clone & Install Dependencies

```bash
git clone https://github.com/simondrow/aiTranslator.git
cd AITranslator
flutter pub get
```

### 2. Download AI Models

Models are **not** included in the repository (~1GB total). Download before first use:

```bash
# NLLB translation model (~870MB)
bash scripts/download_nllb_model.sh

# Whisper ASR model (~148MB, base model)
bash scripts/download_whisper_model.sh
```

> **HuggingFace Mirror**: If HuggingFace is inaccessible in your region, replace `https://huggingface.co` with `https://hf-mirror.com` in the download scripts.

Alternatively, skip this step — the app will prompt model download on first use (requires internet).

| Model | File | Size | Source |
|---|---|---|---|
| NLLB Encoder | `encoder_model_quantized.onnx` | 419 MB | Xenova/nllb-200-distilled-600M |
| NLLB Decoder | `decoder_model_merged_quantized.onnx` | 476 MB | Xenova/nllb-200-distilled-600M |
| NLLB Tokenizer | `tokenizer.json` | 17 MB | Xenova/nllb-200-distilled-600M |
| Whisper Base | `ggml-base.bin` | 148 MB | ggerganov/whisper.cpp |
| fastText LID | `lid.176.ftz` | 917 KB | Bundled in assets |

---

## iOS Simulator Testing

### Quick Start

```bash
# 1. Install dependencies
flutter pub get
cd ios && pod install && cd ..

# 2. Run on iOS Simulator
flutter run
```

### Push Models to Simulator (Skip In-App Download)

For faster development iteration, push pre-downloaded models directly into the Simulator's app container:

```bash
# Download models first (one-time)
bash scripts/download_nllb_model.sh
bash scripts/download_whisper_model.sh

# Install app on simulator
flutter run --no-pub

# Push models to simulator's Documents directory
bash scripts/push_models_to_sim.sh

# Hot restart (press R) - models will be detected immediately
```

### iOS Development Workflow

```bash
# One-time setup
bash scripts/download_nllb_model.sh        # Download NLLB (~870MB)
bash scripts/download_whisper_model.sh      # Download Whisper (~148MB)
flutter pub get && cd ios && pod install && cd ..
flutter run --no-pub                        # Install app (~15MB)
bash scripts/push_models_to_sim.sh          # Push models to simulator

# Daily iteration
flutter run --no-pub                        # Fast rebuild, models persist in sim
# Press R for hot restart, r for hot reload
```

### iOS Notes

- Native libraries (whisper.cpp, fastText) are built via CocoaPods using the `native/` CMakeLists
- The fastText model (`lid.176.ftz`, 917KB) is bundled in `assets/models/` and auto-copied to Documents on first launch
- NLLB and Whisper models are stored in `Documents/models/` and persist across app reinstalls on Simulator

---

## Android Real Device Testing

### Prerequisites

1. **Android Studio** installed with:
   - Android SDK (API 24+)
   - NDK (via SDK Manager -> SDK Tools -> NDK)
   - CMake (via SDK Manager -> SDK Tools -> CMake)

2. **Device Setup**:
   - Enable **Developer Options** (tap Build Number 7 times in Settings -> About Phone)
   - Enable **USB Debugging** in Developer Options
   - Connect phone via USB, accept the debugging prompt on device

### Quick Start

```bash
# 1. Verify device is connected
flutter devices

# 2. Clean build (recommended for first Android build)
flutter clean
flutter pub get

# 3. Run on Android device
flutter run -d <device_id>
```

> **First build takes 5-10 minutes** — CMake compiles whisper.cpp and fastText native libraries for Android ABIs (arm64-v8a, armeabi-v7a, x86_64).

### Model Loading on Android

There are two options for getting models onto the device:

#### Option A: In-App Download (Recommended)

Simply launch the app. On first interaction (text input, mic tap, or language switch), the app will prompt to download models from HuggingFace. Progress is shown in-app.

> **Note**: Requires ~1GB of free storage and a network connection. If HuggingFace is inaccessible, see the mirror note above.

#### Option B: ADB Push (Faster for Development)

Push pre-downloaded models directly to the device:

```bash
# Download models to project dir (if not already done)
bash scripts/download_nllb_model.sh
bash scripts/download_whisper_model.sh

# Create target directories on device
adb shell run-as com.ai.translator mkdir -p /data/data/com.ai.translator/app_flutter/models/nllb-onnx
adb shell run-as com.ai.translator mkdir -p /data/data/com.ai.translator/app_flutter/models/whisper

# Push NLLB models (via /data/local/tmp as intermediate)
adb push assets/models/nllb-onnx/encoder_model_quantized.onnx /data/local/tmp/encoder.onnx
adb shell run-as com.ai.translator cp /data/local/tmp/encoder.onnx /data/data/com.ai.translator/app_flutter/models/nllb-onnx/encoder_model_quantized.onnx

adb push assets/models/nllb-onnx/decoder_model_merged_quantized.onnx /data/local/tmp/decoder.onnx
adb shell run-as com.ai.translator cp /data/local/tmp/decoder.onnx /data/data/com.ai.translator/app_flutter/models/nllb-onnx/decoder_model_merged_quantized.onnx

adb push assets/models/nllb-onnx/tokenizer.json /data/local/tmp/tokenizer.json
adb shell run-as com.ai.translator cp /data/local/tmp/tokenizer.json /data/data/com.ai.translator/app_flutter/models/nllb-onnx/tokenizer.json

# Push Whisper model
adb push assets/models/whisper/ggml-base.bin /data/local/tmp/whisper.bin
adb shell run-as com.ai.translator cp /data/local/tmp/whisper.bin /data/data/com.ai.translator/app_flutter/models/whisper/ggml-base.bin

# Clean up tmp files
adb shell rm /data/local/tmp/encoder.onnx /data/local/tmp/decoder.onnx /data/local/tmp/tokenizer.json /data/local/tmp/whisper.bin
```

Then hot restart the app (`R`).

### Android Permissions

The following permissions are configured in `AndroidManifest.xml`:

| Permission | Purpose |
|---|---|
| `INTERNET` | Download models from HuggingFace |
| `RECORD_AUDIO` | Microphone access for voice input |
| `READ_EXTERNAL_STORAGE` | File access (Android 9 and below) |
| `WRITE_EXTERNAL_STORAGE` | File access (Android 9 and below) |
| `FOREGROUND_SERVICE` | Background recording support |

> The app also sets `requestLegacyExternalStorage="true"` for Android 10 compatibility and `usesCleartextTraffic="true"` for HTTP mirror support.

### Android Troubleshooting

| Problem | Solution |
|---|---|
| `flutter devices` shows no device | Check USB cable, enable USB Debugging, accept prompt on phone |
| Gradle build fails | Run `cd android && ./gradlew clean && cd ..` then retry |
| CMake not found | Android Studio -> SDK Manager -> SDK Tools -> install CMake |
| NDK not found | Android Studio -> SDK Manager -> SDK Tools -> install NDK |
| `minSdkVersion` error | Already set to 24 in `android/app/build.gradle` |
| Model download fails | Check network; try HuggingFace mirror (`hf-mirror.com`) |
| App crashes on model load | Check logcat: `adb logcat -s flutter` for path/permission errors |
| Recording permission denied | Ensure `RECORD_AUDIO` permission is granted in system settings |

### Android Development Workflow

```bash
# One-time setup
flutter clean && flutter pub get
flutter run -d <device_id>           # First build: 5-10 min (CMake)
# App prompts model download on first use

# Daily iteration
flutter run -d <device_id>           # Incremental build: ~30s
# Press R for hot restart, r for hot reload
# Models persist in app data across rebuilds
```

---

## AI Models

| Model | Size | Bundled | Purpose | Runtime |
|---|---|---|---|---|
| fastText lid.176.ftz | 917 KB | Yes | Language detection | dart:ffi, < 1ms |
| NLLB-200 ONNX (int8) | 870 MB | Download | Machine translation | Background Isolate, 3-70s |
| Whisper Base (GGML) | 148 MB | Download | Speech recognition | dart:ffi, ~3s per segment |

## Project Structure

```
AITranslator/
+-- lib/
|   +-- main.dart                          # App entry point
|   +-- app/
|   |   +-- theme.dart                     # Theme & color definitions
|   |   +-- router.dart                    # Route configuration
|   +-- features/
|   |   +-- conversation/                  # Core translation feature
|   |   |   +-- models/message.dart        # Message model
|   |   |   +-- providers/                 # Riverpod state management
|   |   |   |   +-- conversation_provider.dart  # Translation logic, cancellation
|   |   |   +-- pages/
|   |   |   |   +-- conversation_page.dart      # Main page (recording UI, pulse anim)
|   |   |   |   +-- conversation_mode_page.dart # History (swipe-to-delete)
|   |   |   +-- widgets/
|   |   |       +-- language_bar.dart      # Language selector bar
|   |   |       +-- language_selector.dart # Language picker sheet
|   |   +-- model_manager/                # Model download management
|   |       +-- models/model_info.dart
|   |       +-- providers/
|   |       +-- pages/
|   +-- services/
|   |   +-- nllb_onnx_translator.dart      # NLLB ONNX encoder-decoder inference
|   |   +-- translation_isolate.dart       # Background Isolate for NLLB
|   |   +-- translation_service.dart       # Translation service wrapper
|   |   +-- model_download_trigger.dart    # On-demand download dialog
|   |   +-- language_detect_service.dart   # Language detection (fastText FFI)
|   |   +-- asr_service.dart               # Whisper ASR (segment-based streaming)
|   |   +-- audio_service.dart             # Audio recording + rotateRecording()
|   |   +-- tts_service.dart               # Text-to-speech
|   +-- native/                            # dart:ffi bindings
|   |   +-- fasttext_bindings.dart
|   |   +-- nllb_bindings.dart
|   |   +-- whisper_bindings.dart
|   +-- utils/
|       +-- language_codes.dart            # 11 languages + family grouping
+-- native/                                # C/C++ bridge code
|   +-- CMakeLists.txt                     # Top-level CMake (whisper + fastText + nllb)
|   +-- bridge/
|   |   +-- whisper_bridge.{h,c}
|   |   +-- nllb_bridge.{h,cpp}
|   |   +-- fasttext_bridge.{h,cpp}
|   +-- third_party/
|       +-- whisper.cpp/                   # whisper.cpp v1.8.4
|       +-- fastText/                      # Facebook fastText v0.9.2
+-- scripts/
|   +-- download_nllb_model.sh             # Download NLLB ONNX models
|   +-- download_whisper_model.sh          # Download Whisper GGML model
|   +-- push_models_to_sim.sh             # Push models to iOS Simulator
+-- assets/models/
|   +-- lid.176.ftz                        # fastText model (bundled, 917KB)
|   +-- nllb-onnx/                         # NLLB ONNX models (gitignored)
|   +-- whisper/                           # Whisper GGML model (gitignored)
+-- ios/
+-- android/
|   +-- app/src/main/AndroidManifest.xml   # Permissions: INTERNET, RECORD_AUDIO, etc.
+-- pubspec.yaml
```

## Usage

1. **Text input**: Type in the text field - translation appears in real-time after 400ms debounce
2. **Voice input**: Long-press the mic button to record (pulse animation), release or tap to stop
3. **Streaming ASR**: During recording, speech is transcribed in 3-second segments in real-time
4. **Auto-translate**: Language is auto-detected on first input; direction is locked for the session
5. **Complete input**: Press Done to commit the bilingual message with TTS controls
6. **Language switch**: Tap language pills at the bottom; switching clears current translation state
7. **History**: Tap the history icon to view past translations; swipe left to delete
8. **TTS**: Tap the speaker icon to hear pronunciation
9. **Copy**: Tap the copy icon to copy text to clipboard

## Known Limitations

- **NLLB translation speed**: Without KV cache, long text takes 10-70s. Short text (~10 tokens) takes ~3-10s.
- **NLLB short-text hallucination**: The distilled-600M model occasionally produces profanity on very short inputs (known model issue).
- **No KV cache yet**: Decoder recomputes all attention from scratch each step (O(N^2)). KV cache optimization would provide 3-6x speedup.

## Roadmap

- [x] fastText native language detection (dart:ffi)
- [x] NLLB-200 ONNX translation (encoder-decoder, int8 quantized)
- [x] On-demand model download with progress dialog
- [x] Streaming segment-based ASR via whisper.cpp
- [x] Background Isolate for NLLB (UI non-blocking)
- [x] Translation request deduplication & cancellation
- [x] Language detection direction locking
- [x] 11 language support (zh/en/ja/ko/fr/de/ru/es/it/th/vi)
- [x] Swipeable translation history
- [x] iOS Simulator testing complete
- [x] Android permissions & manifest configuration
- [ ] Android real device testing
- [ ] KV Cache for NLLB decoder (3-6x speedup)
- [ ] Explore smaller models (Opus-MT ~150MB/pair)
- [ ] Dark mode support

## License

MIT License - see [LICENSE](LICENSE) for details.

> **Note**: The NLLB-200 model is licensed under CC-BY-NC 4.0 (non-commercial use only).
