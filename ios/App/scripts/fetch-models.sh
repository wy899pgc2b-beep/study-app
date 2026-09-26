#!/usr/bin/env bash
# MediaPipe のモデルを取ってくる(試作品の vision.js と同じもの)。取ってあるものは取り直さない。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Resources/Models
BASE=https://storage.googleapis.com/mediapipe-models
fetch() {
  local out="Resources/Models/$2"
  if [ -s "$out" ]; then return; fi
  curl -fsSL --retry 3 -o "$out.part" "$BASE/$1"
  mv "$out.part" "$out"
}
fetch face_landmarker/face_landmarker/float16/1/face_landmarker.task face_landmarker.task
fetch hand_landmarker/hand_landmarker/float16/1/hand_landmarker.task hand_landmarker.task
fetch pose_landmarker/pose_landmarker_lite/float16/1/pose_landmarker_lite.task pose_landmarker_lite.task
fetch image_segmenter/selfie_multiclass_256x256/float32/1/selfie_multiclass_256x256.tflite selfie_multiclass_256x256.tflite
ls -l Resources/Models
