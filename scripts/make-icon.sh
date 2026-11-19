#!/usr/bin/env bash
# 生成 App 图标。可选配色：night（默认，黑底）、sky（蓝）、warm（暖橙）
#   ./scripts/make-icon.sh [night|sky|warm]
set -euo pipefail
cd "$(dirname "$0")/.."
VARIANT=${1:-night}
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
swift scripts/IconRenderer.swift "$VARIANT" "$TMP/icon.png" >/dev/null
mkdir -p "$TMP/AppIcon.iconset"
for s in 16 32 128 256 512; do
  magick "$TMP/icon.png" -resize ${s}x${s} "$TMP/AppIcon.iconset/icon_${s}x${s}.png"
  magick "$TMP/icon.png" -resize $((s*2))x$((s*2)) "$TMP/AppIcon.iconset/icon_${s}x${s}@2x.png"
done
iconutil -c icns "$TMP/AppIcon.iconset" -o KeyPop/Resources/AppIcon.icns
cp "$TMP/icon.png" scripts/icon-preview.png
echo "✓ AppIcon.icns ($VARIANT)"
