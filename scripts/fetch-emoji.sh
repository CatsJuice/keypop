#!/usr/bin/env bash
# 下载 scripts/emoji.txt 列出的 Fluent Emoji（矢量 SVG），并渲染成高分辨率 PNG 放进 App 资源。
# 依赖：gh（登录过的 GitHub CLI）、rsvg-convert（brew install librsvg）
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=KeyPop/Resources/Emoji
SIZE=${SIZE:-640}
mkdir -p "$OUT"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

gh api 'repos/microsoft/fluentui-emoji/git/trees/main?recursive=1' \
  --jq '.tree[] | select(.path|test("/Color/[^/]*\\.svg$")) | .path' > "$TMP/tree.txt"

fail=0
while IFS='|' read -r slug name; do
  [[ -z "$slug" || "$slug" == \#* ]] && continue
  [[ -f "$OUT/$slug.png" ]] && continue
  path=$(grep -m1 -F "assets/$name/Color/" "$TMP/tree.txt" || true)
  if [[ -z "$path" ]]; then echo "✗ $slug ($name) 不存在"; fail=1; continue; fi
  url="https://raw.githubusercontent.com/microsoft/fluentui-emoji/main/$(printf '%s' "$path" | sed 's/ /%20/g')"
  curl -fsSL "$url" -o "$TMP/$slug.svg"
  rsvg-convert -w "$SIZE" -h "$SIZE" -a "$TMP/$slug.svg" -o "$OUT/$slug.png"
  echo "✓ $slug"
done < scripts/emoji.txt
exit $fail
