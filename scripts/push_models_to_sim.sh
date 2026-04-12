#!/usr/bin/env bash
# Push NLLB ONNX + Whisper models to iOS Simulator app Documents
# Usage: bash scripts/push_models_to_sim.sh
set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
NLLB_SRC="$SCRIPT_DIR/../assets/models/nllb-onnx"
WHISPER_SRC="$SCRIPT_DIR/../assets/models/whisper"

APP_ID="com.aistudio.aiTranslator"
BOOTED_SIM=$(xcrun simctl list devices booted -j | python3 -c "
import sys, json
data = json.load(sys.stdin)
for rt, devs in data.get('devices', {}).items():
    for d in devs:
        if d.get('state') == 'Booted':
            print(d['udid']); break
" 2>/dev/null | head -1)

if [ -z "$BOOTED_SIM" ]; then echo "No booted simulator"; exit 1; fi
echo "Sim: $BOOTED_SIM"

APP_CONTAINER=$(xcrun simctl get_app_container "$BOOTED_SIM" "$APP_ID" data 2>/dev/null || echo "")
if [ -z "$APP_CONTAINER" ]; then echo "App not installed. Run flutter run first"; exit 1; fi

echo "App container: $APP_CONTAINER"

# ---- NLLB ONNX models ----
if [ -f "$NLLB_SRC/encoder_model_quantized.onnx" ]; then
  DEST="$APP_CONTAINER/Documents/models/nllb-onnx"
  mkdir -p "$DEST"
  echo ""
  echo "=== NLLB ONNX Models ==="
  echo "Source: $NLLB_SRC"
  echo "Target: $DEST"

  for f in encoder_model_quantized.onnx decoder_model_merged_quantized.onnx tokenizer.json; do
    if [ -f "$DEST/$f" ]; then
      S1=$(stat -f%z "$NLLB_SRC/$f"); S2=$(stat -f%z "$DEST/$f")
      if [ "$S1" = "$S2" ]; then echo "  SKIP $f"; continue; fi
    fi
    echo "  COPY $f ..."
    cp "$NLLB_SRC/$f" "$DEST/$f"
  done
else
  echo "NLLB models not found — run: bash scripts/download_nllb_model.sh"
fi

# ---- Whisper model ----
WHISPER_MODEL=$(ls "$WHISPER_SRC"/ggml-*.bin 2>/dev/null | head -1)
if [ -n "$WHISPER_MODEL" ]; then
  DEST="$APP_CONTAINER/Documents/models/whisper"
  mkdir -p "$DEST"
  echo ""
  echo "=== Whisper Model ==="
  echo "Source: $WHISPER_SRC"
  echo "Target: $DEST"

  for f in "$WHISPER_SRC"/ggml-*.bin; do
    fname=$(basename "$f")
    if [ -f "$DEST/$fname" ]; then
      S1=$(stat -f%z "$f"); S2=$(stat -f%z "$DEST/$fname")
      if [ "$S1" = "$S2" ]; then echo "  SKIP $fname"; continue; fi
    fi
    echo "  COPY $fname ..."
    cp "$f" "$DEST/$fname"
  done
else
  echo "Whisper model not found — run: bash scripts/download_whisper_model.sh"
fi

echo ""
echo "Done! Restart app (press R) to pick up the models."
