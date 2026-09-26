#!/usr/bin/env bash
# 画面の文字(Zen Maru Gothic。SIL Open Font License)を取ってくる。取ってあるものは取り直さない。
# ライセンスの文書(OFL.txt)も一緒にアプリに入れる。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Resources/Fonts
BASE=https://github.com/google/fonts/raw/main/ofl/zenmarugothic
for f in ZenMaruGothic-Regular.ttf ZenMaruGothic-Medium.ttf ZenMaruGothic-Bold.ttf OFL.txt; do
  out="Resources/Fonts/$f"
  if [ -s "$out" ]; then continue; fi
  curl -fsSL --retry 3 -o "$out.part" "$BASE/$f"
  mv "$out.part" "$out"
done
ls -l Resources/Fonts
