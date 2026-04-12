# AI Translator

Real-time conversation translation app — offline translation powered by on-device AI models.

实时对话翻译应用 —— 基于端侧 AI 模型的离线翻译工具。

## Features

- **Offline Translation** — All AI inference runs locally on device, no internet required after model download
- **Voice & Text Input** — Tap the mic to speak or type text directly
- **Auto Language Detection** — Automatically detects input language via fastText and translates to the target
- **Language Family Grouping** — Unrecognized languages are grouped by family (CJK / European) to determine translation direction
- **9 Languages** — Chinese, English, Japanese, Korean, French, German, Russian, Spanish, Italian
- **Translation History** — All translations saved and browsable in history view
- **Text-to-Speech** — Listen to pronunciation of both source and translated text
- **Copy to Clipboard** — One-tap copy for original or translated text

## Tech Stack

| Component | Technology | Details |
|---|---|---|
| Framework | [Flutter](https://flutter.dev) 3.x | Cross-platform (iOS & Android) |
| ASR | [whisper.cpp](https://github.com/ggerganov/whisper.cpp) | On-device speech recognition via dart:ffi (stub) |
| Translation | [NLLB-200-distilled-600M](https://huggingface.co/Xenova/nllb-200-distilled-600M) | ONNX int8 quantized (~870MB), via [onnxruntime](https://pub.dev/packages/onnxruntime) Flutter plugin |
| Language Detection | [fastText](https://fasttext.cc/) | lid.176.ftz model (~917KB, bundled in app) via dart:ffi |
| TTS | System TTS | flutter_tts, uses device built-in TTS engine |
| State Management | [Riverpod](https://riverpod.dev/) | flutter_riverpod with StateNotifier |
| Model Download | [HuggingFace](https://huggingface.co/) | On-demand model download via dio |

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Flutter App (Dart)                        │
│                                                             │
│  ┌──────────────┐  ┌──────────────────┐  ┌──────────────┐  │
│  │ ConversationPage│  │ModelDownloadTrigger│  │  HistoryPage │  │
│  └──────┬───────┘  └────────┬─────────┘  └──────────────┘  │
│         │                   │                               │
│  ┌──────▼───────────────────▼──────────────────────────┐    │
│  │            ConversationProvider (Riverpod)           │    │
│  │  _detectDirection() → language family grouping       │    │
│  └──────┬──────────────┬──────────────┬────────────┘    │
│         │              │              │                  │
│  ┌──────▼──────┐ ┌─────▼──────┐ ┌────▼─────────────┐   │
│  │LanguageDetect│ │Translation │ │  ASR Service     │   │
│  │  Service     | │  Service   │ │  (whisper stub)  │   │
│  │  (fastText)  │ │  (NLLB)    │ └──────────────────┘   │
│  └──────┬──────┘ └─────┬──────┘                         │
│         │              │                                │
│  ┌──────▼──────┐ ┌─────▼──────────────┐                │
│  │FastTextBindings│ │NllbOnnxTranslator │                │
│  │  (dart:ffi) | │ (onnxruntime plugin)│                │
│  └──────┬──────┘ └─────┬──────────────┘                │
│         │              │                                │
└─────────┼──────────────┼────────────────────────────────┘
          │              │
   ┌──────▼──────┐ ┌─────▼──────────────────────────────┐
   │ libfasttext  │ │  ONNX Runtime (C++ via Flutter FFI) │
   │ (C++ native) │ │  encoder_model_quantized.onnx       │
   └─────────────┘ │  decoder_model_merged_quantized.onnx │
                   │  tokenizer.json (BPE 256K vocab)     │
                   └──────────────────────────────────────┘
```

## Supported Languages

🇨🇳 中文 · 🇺🇸 English · 🇯🇵 日本語 · 🇰🇷 한국어 · 🇫🇷 Français · 🇩🇪 Deutsch · 🇷🇺 Русский · 🇪���� Español · 🇮���� Italiano

## Requirements

- Flutter SDK >= 3.5.0
- Dart SDK >= 3.2.0
- **iOS**: Xcode 15+, iOS 15.0+
- **Android**: minSdkVersion 24, NDK installed
- CMake >= 3.18 (for native library compilation)

## Getting Started

### 1. Clone & Install Dependencies

```bash
git clone https://github.com/user/AITranslator.git
cd AITranslator
flutter pub get
```

### 2. Download NLLB Translation Model

The NLLB ONNX model files (~870MB) are **not** included in the git repository. Download them before first use:

```bash
bash scripts/download_nllb_model.sh
```

This downloads from HuggingFace to `assets/models/nllb-onnx/`:

| File | Size | Source |
|---|---|---|
| `encoder_model_quantized.onnx` | 400 MB | Xenova/nllb-200-distilled-600M |
| `decoder_model_merged_quantized.onnx` | 453 MB | Xenova/nllb-200-distilled-600M |
| `tokenizer.json` | 17 MB | Xenova/nllb-200-distilled-600M p
�223 3. Run the App

```bash
# iOS Simulator
flutter run

# Android device
flutter run -d <device_id>
```

### 4. Push Models to Simulator (Debug)

After installing the app on the iOS Simulator, push the downloaded models directly into the app's Documents folder — this avoids the in-app download:

```bash
bash scripts/push_models_to_sim.sh
```

Then hot restart (`R`) the app. The translation engine will auto-detect the models and initialize immediately.

> **Note**: If you skip this step, the app will prompt you to download the models on first user interaction (first text input, mic tap, or language switch).

### Full Debug Workflow

```bash
# One-time setup
bash scripts/download_nllb_model.sh      # Download models to project dir
flutter run --no-pub                      # Install app (~15MB)
bash scripts/push_models_to_sim.sh        # Push models to simulator

# Daily development
flutter run --no-pub                      # Fast install, models already in sim
# Press R for hot restart
```

## AI Models

| Model | Size | Bundled | Purpose | Status |
|---|---|---|---|---|
| fastText lid.176.ftz | 917 KB | ✅ Yes | Language detection | Native FFI inference |
| NLLB-200 ONNX (int8) | 870 MB | ❌ On-demand | Machine translation | ONNX Runtime Dart |
| Whisper Small | 466 MB | ❌ On-demand | Speech recognition | Stub (not yet integrated) |

## Project Structure

```
AITranslator/
├── lib/
│   ├── main.dart                          # App entry point
│   ├── app/
│   │   ├── theme.dart                     # Theme & color definitions
│   │   └── router.dart                    # Route configuration
│   ├── features/
│   │   ├── conversation/                  # Translation feature
│   │   │   ├── models/message.dart        # Message model
│   │   │   ├── providers/                 # Riverpod state management
│   │   │   ├── pages/
│   │   │   │   ├── conversation_page.dart # Main translation page
│   │   │   │   └── conversation_mode_page.dart # History page
│   │   │   └── widgets/
│   │   │       ├── language_bar.dart      # Language selector bar
│   │   │       └── language_selector.dart # Language picker sheet
│   │   └── model_manager/                # Model download management
│   │       ├── models/model_info.dart
│   │       ├── providers/
│   │       └── pages/
│   ├── services/
│   │   ├── nllb_onnx_translator.dart      # NLLB ONNX inference (encoder-decoder)
│   │   ├── translation_service.dart       # Translation service wrapper
│   │   ├── model_download_trigger.dart    # On-demand download dialog
│   │   ├── language_detect_service.dart   # Language detection (fastText FFI)
│   │   ├── asr_service.dart               # Speech recognition (stub)
│   │   ├── audio_service.dart             # Audio recording
│   │   └── tts_service.dart               # Text-to-speech
│   ├── native/                            # dart:ffi bindings
│   │   ├── fasttext_bindings.dart
│   │   ├── nllb_bindings.dart             # Legacy FFI bindings (unused)
│   │   └── whisper_bindings.dart
│   └── utils/
│       └── language_codes.dart            # Language codes + family grouping
├── native/                                # C/C++ bridge code
│   ├── CMakeLists.txt
│   ├── AiNllb.podspec
│   ├── bridge/
│   │   ├── whisper_bridge.{h,c}
│   │   ├── nllb_bridge.{h,cpp}
│   │   └── fasttext_bridge.{h,cpp}
│   └── third_party/
│       └── fastText/                      # Facebook fastText source (v0.9.2)
├── scripts/
│   ├── download_nllb_model.sh             # Download NLLB ONNX models
│   └── push_models_to_sim.sh              # Push models to iOS Simulator
├── assets/models/
│   ├── lid.176.ftz                        # fastText model (bundled, 917KB)
│   └── nllb-onnx/                         # NLLB ONNX models (gitignored)
│       ├── encoder_model_quantized.onnx
│       ├── decoder_model_merged_quantized.onnx
│       └── tokenizer.json
├── ios/
├── android/
└── pubspec.yaml
```

## Usage

1. **Text input**: Type in the text field — translation appears in real-time after 400ms debounce
2. **Complete input**: Press Done or tap outside the text field to enter the bilingual display with TTS
3. **Voice input**: Tap the mic button to record, tap anywhere to stop
4. **Language selection**: Tap the language pills at the bottom to change source/target languages
5. **History**: Tap the history icon (top-left) to view all past translations
6. **TTS**: After translation, tap the speaker icon to hear pronunciation
7. **Copy**: Tap the copy icon to copy text to clipboard

## Roadmap

- [x] Integrate fastText native library (language detection via dart:ffi)
- [x] Integrate NLLB-200 ONNX translation (encoder-decoder, int8 quantized)
- [x] On-demand model download with progress dialog
- [x] Language family grouping (CJK / European)
- [x] Input blur auto-commit (bilingual display + TTS)
- [ ] Enable KV Cache for decoder (3-5x speedup)
- [ ] Integrate whisper.cpp native library (replace ASR stub)
- [ ] Android real device testing
- [ ] Explore smaller models (Opus-MT ~150MB/pair)
- [ ] Dark mode support

## License

MIT License — see [LICENSE](LICENSE) for details.

> **Note**: The NLLB-200 model is licensed under CC-BY-NC 4.0 (non-commercial use only).
