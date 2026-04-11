# AI Translator

Real-time conversation translation app — offline translation powered by on-device AI models.

实时对话翻译应用 —— 基于端侧 AI 模型的离线翻译工具。

## Features

- **Offline Translation** — All AI inference runs locally on device, no internet required after model download
- **Voice & Text Input** — Tap the mic to speak or type text directly
- **Auto Language Detection** — Automatically detects input language and translates to the target
- **9 Languages** — Chinese, English, Japanese, Korean, French, German, Russian, Spanish, Italian
- **Translation History** — All translations saved and browsable in history view
- **Text-to-Speech** — Listen to pronunciation of both source and translated text
- **Copy to Clipboard** — One-tap copy for original or translated text

## Tech Stack

| Component | Technology | Details |
|---|---|---|
| Framework | [Flutter](https://flutter.dev) 3.x | Cross-platform (iOS & Android) |
| ASR | [whisper.cpp](https://github.com/ggerganov/whisper.cpp) | On-device speech recognition via dart:ffi |
| Translation | [NLLB-200-distilled-600M](https://huggingface.co/facebook/nllb-200-distilled-600M) | Meta's multilingual translation via CTranslate2 + dart:ffi |
| Language Detection | [fastText](https://fasttext.cc/) | lid.176.bin model via dart:ffi |
| TTS | System TTS | flutter_tts, uses device built-in TTS engine |
| State Management | [Riverpod](https://riverpod.dev/) | flutter_riverpod with StateNotifier |
| Model Download | [HuggingFace](https://huggingface.co/) | On-demand model download via dio |

## Supported Languages

🇨🇳 中文 · 🇺🇸 English · 🇯🇵 日本語 · 🇰🇷 한국어 · 🇫🇷 Français · 🇩🇪 Deutsch · 🇷🇺 Русский · 🇪🇸 Español · 🇮🇹 Italiano

## Requirements

- Flutter SDK >= 3.5.0
- Dart SDK >= 3.2.0
- **iOS**: Xcode 15+, iOS 15.0+
- **Android**: minSdkVersion 24, NDK installed
- CMake >= 3.18 (for native library compilation)

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
│   ├── services/                          # Business services
│   │   ├── asr_service.dart               # Speech recognition
│   │   ├── translation_service.dart       # Translation
│   │   ├── language_detect_service.dart   # Language detection
│   │   ├── audio_service.dart             # Audio recording
│   │   └── tts_service.dart               # Text-to-speech
│   ├── native/                            # FFI bindings
│   │   ├── whisper_bindings.dart
│   │   ├── nllb_bindings.dart
│   │   └── fasttext_bindings.dart
│   └── utils/
│       └── language_codes.dart            # Language code mappings
├── native/                                # C/C++ bridge code
│   ├── CMakeLists.txt
│   └── bridge/
│       ├── whisper_bridge.{h,c}
│       ├── nllb_bridge.{h,c}
│       └── fasttext_bridge.{h,c}
├── assets/models/                         # Model files directory
├── android/                               # Android platform
├── ios/                                   # iOS platform
└── pubspec.yaml
```

## Getting Started

### 1. Clone & Install Dependencies

```bash
git clone https://github.com/user/AITranslator.git
cd AITranslator
flutter pub get
```

### 2. Run

```bash
# iOS Simulator
flutter run

# Android device
flutter run -d <device_id>
```

### 3. First Use

The app launches into the main translation screen. AI models need to be downloaded on first use via the model manager (top-right download icon):

| Model | Size | Purpose |
|---|---|---|
| Whisper Small | ~466 MB | Speech recognition |
| NLLB-200-distilled-600M | ~600 MB | Machine translation |
| fastText lid.176.bin | ~131 MB | Language detection |

> **Note**: ASR, translation, and language detection currently run in stub mode. Native model integration is the next development milestone.

## Usage

1. **Text input**: Type in the text field, press Done to translate
2. **Voice input**: Tap the mic button to record, tap anywhere to stop — translation appears automatically
3. **Language selection**: Tap the language pills at the bottom to change source/target languages
4. **History**: Tap the history icon (top-left) to view all past translations
5. **TTS**: After translation completes, tap the speaker icon to hear pronunciation
6. **Copy**: Tap the copy icon to copy text to clipboard

## Roadmap

- [ ] Integrate whisper.cpp native library (replace ASR stub)
- [ ] Integrate CTranslate2 + NLLB native library (replace translation stub)
- [ ] Integrate fastText native library (replace language detection stub)
- [ ] HuggingFace model download integration
- [ ] Streaming translation display
- [ ] Android real device testing
- [ ] Dark mode support

## License

MIT License — see [LICENSE](LICENSE) for details.
