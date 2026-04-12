#!/usr/bin/env bash
# Push NLLB ONNX models to iOS Simulator app Documents
# Usage: bash scripts/push_models_to_sim.sh
set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
MODEL_SRC="$SCRIPT_DIR/../assets/models/nllb-onnx"

if [ ! -f "$MODEL_SRC/encoder_model_quantized.onnx" ]; then
  echo "ERROR: models missing. Run scripts/download_nllb_model.sh first"
  exit 1
fi

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

DEST="$APP_CONTAINER/Documents/models/nllb-onnx"
mkdir -p "$DEST"
echo "Source: $MODEL_SRC"
echo "Target: $DEST"

for f in encoder_model_quantized.onnx decoder_model_merged_quantized.onnx tokenizer.json; do
  if [ -f "$DEST/$f" ]; then
    S1=$(stat -f%z "$MODEL_SRC/$f"); S2=$(stat -f%z "$DEST/$f")
    if [ "$S1" = "$S2" ]; then echo "  SKIP $f"; continue; fi
  fi
  echo "  COPY $f ..."
  cp "$MODEL_SRC/$f" "$DEST/$f"
done

echo "Done! Restart app to skip download."
