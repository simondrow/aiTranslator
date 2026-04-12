#!/usr/bin/env bash
# Download NLLB-200-distilled-600M ONNX quantized model files
set -e
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
MODEL_DIR="$SCRIPT_DIR/../assets/models/nllb-onnx"
HF_BASE="https://huggingface.co/Xenova/nllb-200-distilled-600M/resolve/main"
mkdir -p "$MODEL_DIR"

echo "NLLB-200 ONNX Model Downloader"
echo "Target: $MODEL_DIR"

FILES=(
  "onnx/encoder_model_quantized.onnx:encoder_model_quantized.onnx:419"
  "onnx/decoder_model_merged_quantized.onnx:decoder_model_merged_quantized.onnx:476"
  "tokenizer.json:tokenizer.json:17"
)

for entry in "${FILES[@]}"; do
  IFS=':' read -r remote local size <<< "$entry"
  if [ -f "$MODEL_DIR/$local" ]; then
    echo "OK $local exists"
  else
    echo "Downloading $local (~${size} MB)..."
    curl -L --progress-bar "$HF_BASE/$remote" -o "$MODEL_DIR/$local"
  fi
done

echo "Done"
ls -lh "$MODEL_DIR"
