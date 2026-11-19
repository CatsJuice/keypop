#!/usr/bin/env bash
# 生成 Xcode 工程并构建 Release 版，产物在 build/KeyPop.app
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate --quiet
xcodebuild -project KeyPop.xcodeproj -scheme KeyPop -configuration Release -derivedDataPath build/DerivedData \
  -quiet build
rm -rf build/KeyPop.app
cp -R build/DerivedData/Build/Products/Release/KeyPop.app build/KeyPop.app
echo "✓ build/KeyPop.app"
[[ "${1:-}" == "--open" ]] && open build/KeyPop.app || true
