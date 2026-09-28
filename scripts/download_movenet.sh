#!/usr/bin/env bash
# Place your MoveNet Thunder .tflite in VisionCPRCoach/Resources/movenet_thunder.tflite
# Official TF Hub (int8): https://tfhub.dev/google/lite-model/movenet/singlepose/thunder/tflite/int8/4?lite-format=tflite
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/VisionCPRCoach/Resources/movenet_thunder.tflite"

if [ -f "$ROOT/movenet_thunder.tflite" ]; then
  cp "$ROOT/movenet_thunder.tflite" "$OUT"
  echo "Copied project-root movenet_thunder.tflite → Resources/"
elif [ ! -f "$OUT" ]; then
  echo "Downloading MoveNet Thunder int8/4 from TF Hub → $OUT"
  curl -L -A "Mozilla/5.0" -o "$OUT" \
    "https://tfhub.dev/google/lite-model/movenet/singlepose/thunder/tflite/int8/4?lite-format=tflite"
fi

if file "$OUT" | grep -qi 'HTML'; then
  echo "Error: not a valid TFLite file." >&2
  exit 1
fi

ls -lh "$OUT"
echo "Done. Thunder expects 256×256 input (auto-detected at runtime)."
