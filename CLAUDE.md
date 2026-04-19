# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Common Development Commands

```bash
# Install dependencies
flutter pub get

# iOS setup (one-time)
cd ios && pod install && cd ..

# Run on iOS Simulator
flutter run

# Run on Android device
flutter run -d <device_id>

# Run tests
flutter test

# Download AI models (optional - app prompts on first use)
bash scripts/download_nllb_model.sh
bash scripts/download_whisper_model.sh

# Push pre-downloaded models to iOS Simulator (faster iteration)
bash scripts/push_models_to_sim.sh
```

## Architecture Overview

This is a Flutter cross-platform app for real-time offline translation using on-device AI models. The app uses three main AI components:

### Translation Pipeline (Key)

**Translation Scheduling Strategy** (`ConversationNotifier` in `lib/features/conversation/providers/conversation_provider.dart`):

1. **Debounce** - Text input: UI 400ms + provider 600ms. Voice input: No debounce (controlled by page layer).
2. **Generation + StopGeneration** - On new request:
   - Increment `_translateGeneration` to invalidate old results
   - Call `_translationService.stopGeneration()` to **immediately interrupt** ongoing LLM inference
   - Immediately start new translation without waiting
3. **Text Deduplication** - Same text not translated twice
4. **LLM Busy Queue** - If stopGeneration hasn't fully released yet, cache to `_pendingText`, process via `_drainPending()`
5. **Keep Last Translation** - UI continues showing old translation during new inference to avoid flicker

### AI Components

| Component | Technology | Model | Runtime |
|---|---|---|---|
| Translation | HY-MT1.5-1.8B via llama.cpp (`flutter_llama`) | GGUF (~2GB) | Stream generation, interruptible |
| ASR | SenseVoice via sherpa-onnx | ONNX int8 (~200MB) | Non-autoregressive, <500ms per segment |
| Language Detection | fastText via dart:ffi | lid.176.ftz (~917KB) | <1ms inference |

### State Management

Uses **Riverpod** (`flutter_riverpod`) with `StateNotifier` pattern. Key providers:
- `conversationProvider` - Main translation state and scheduling
- `translationServiceProvider` - HY-MT translation wrapper
- `asrServiceProvider` - SenseVoice ASR wrapper
- `languageDetectServiceProvider` - fastText language detection

### Native Integration

- **whisper.cpp**: Built via CMake in `native/` with bridge code in `native/bridge/whisper_bridge.{h,c}`. Includes stub mode when not built.
- **fastText**: Built via CMake with `native/bridge/fasttext_bridge.{h,cpp}`. Model bundled in `assets/models/lid.176.ftz`.
- **NLLB/CTranslate2**: Legacy bridge (being replaced by HY-MT).

### Known Workarounds

**flutter_llama EventChannel Race Condition** (`lib/services/hymt_translator.dart`):
- `FlutterLlama.generateStream()` has a bug where it calls MethodChannel before subscribing to EventChannel, causing native eventSink to be null.
- Workaround: Directly use underlying `MethodChannel('flutter_llama')` and `EventChannel('flutter_llama/stream')`, subscribe first, then invoke.

**flutter_llama endOfStream Residual**:
- After `stopGeneration()`, native side sends `endOfStream` via `mainHandler.post()`, which may be captured by next `receiveBroadcastStream`'s `onDone`.
- Workaround: Use MethodChannel's result callback to determine completion, not `onDone`. Add 50ms delay before new inference to flush residual events.

### Model Locations

- **fastText**: Bundled in `assets/models/lid.176.ftz`, auto-copied to Documents on first launch
- **SenseVoice**: Downloaded to `Documents/models/sensevoice/` (model.int8.onnx, tokens.txt)
- **HY-MT**: Downloaded to `Documents/models/hymt/` (GGUF file)

### Language Detection Strategy

**Primary**: fastText (`lid.176.ftz`) - confidence threshold 0.5

**Fallback**: Unicode-based heuristic when fastText confidence < 0.5

**CJK Disambiguation**: When fastText returns `ja`:
- Check for hiragana/katakana presence
- If only CJK ideographs present, correct to `zh` (known lid.176.ftz issue)
- If CJK >> kana (ratio > 4:1) and kana ≤ 1, correct to `zh`

## Supported Languages

Chinese (zh), English (en), Japanese (ja), Korean (ko), French (fr), German (de), Spanish (es), Italian (it), Thai (th), Vietnamese (vi), plus others via HY-MT.

Language codes are ISO 639-1 two-letter codes internally.
