#!/bin/bash
# =============================================================================
# Download Whisper GGML model for AI Translator
#
# Default: ggml-base.bin (148MB, multilingual, 74 languages)
# Alternative: ggml-small.bin (466MB, better accuracy)
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MODEL_DIR="$PROJECT_DIR/assets/models/whisper"

# Model selection (override with: WHISPER_MODEL=small bash scripts/download_whisper_model.sh)
MODEL_NAME="${WHISPER_MODEL:-base}"

BASE_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main"
MODEL_FILE="ggml-${MODEL_NAME}.bin"

mkdir -p "$MODEL_DIR"

echo "=== Whisper Model Download ==="
echo "Model: $MODEL_FILE"
echo "Target: $MODEL_DIR/"
echo ""

DEST="$MODEL_DIR/$MODEL_FILE"

if [ -f "$DEST" ]; then
    SIZE=$(stat -f%z "$DEST" 2>/dev/null || stat --printf="%s" "$DEST" 2>/dev/null)
    echo "✓ Already exists: $MODEL_FILE ($SIZE bytes)"
else
    echo "↓ Downloading $MODEL_FILE ..."
    curl -L --progress-bar \
        --output "$DEST" \
        "$BASE_URL/$MODEL_FILE"
    SIZE=$(stat -f%z "$DEST" 2>/dev/null || stat --printf="%s" "$DEST" 2>/dev/null)
    echo "✓ Downloaded: $MODEL_FILE ($SIZE bytes)"
fi

echo ""
echo "=== Done ==="
echo "Model saved to: $MODEL_DIR/$MODEL_FILE"
echo ""
echo "Available models (set WHISPER_MODEL env var):"
echo "  tiny   ~  75 MB  (fastest, lowest accuracy)"
echo "  base   ~ 148 MB  (recommended for mobile)"
echo "  small  ~ 466 MB  (better accuracy)"
echo "  medium ~ 1.5 GB  (high accuracy)"
