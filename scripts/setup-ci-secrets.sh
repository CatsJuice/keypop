#!/usr/bin/env bash
# 一次性把发布需要的密钥配置成 GitHub 仓库 Secrets（数据直接从本机传给 GitHub，不落盘、不打印）。
#
# 运行前准备：
#   1. 在「钥匙串访问」里找到 “Developer ID Application: …” 证书（展开能看到私钥），
#      右键 → 导出 → 存成 .p12，设一个密码
#   2. 准备好 App Store Connect API 密钥的 Issuer ID（App Store Connect → 用户和访问 → 集成 页面顶部）
#
#   ./scripts/setup-ci-secrets.sh
set -euo pipefail
cd "$(dirname "$0")/.."
REPO=CatsJuice/keypop
export LC_ALL=en_US.UTF-8

gh auth status >/dev/null 2>&1 || { echo "先 gh auth login" >&2; exit 1; }
secret() { gh secret set "$1" --repo "$REPO" >/dev/null && echo "  ✓ $1"; }

echo "【1/3】Developer ID 证书"
read -r -p "  导出的 .p12 文件路径（可直接把文件拖进来）: " P12
P12=${P12//\\ / }; P12=${P12%\'}; P12=${P12#\'}; P12=${P12%% }
[[ -f "$P12" ]] || { echo "  找不到文件：$P12" >&2; exit 1; }
read -r -s -p "  .p12 的密码: " P12_PASS; echo
# 校验密码对不对、里面是不是 Developer ID Application 证书
TMPKC=$(mktemp -u /tmp/keypop-check.XXXXXX).keychain-db
security create-keychain -p tmp "$TMPKC" >/dev/null
trap 'security delete-keychain "$TMPKC" 2>/dev/null || true' EXIT
security import "$P12" -k "$TMPKC" -P "$P12_PASS" >/dev/null || { echo "  密码不对或文件损坏" >&2; exit 1; }
NAME=$(security find-certificate -a "$TMPKC" | grep -o '"Developer ID Application: [^"]*"' | head -1 || true)
[[ -n "$NAME" ]] || { echo "  .p12 里没有 Developer ID Application 证书" >&2; exit 1; }
echo "  证书：$NAME"
base64 -i "$P12" | secret DEVELOPER_ID_P12_BASE64
printf '%s' "$P12_PASS" | secret DEVELOPER_ID_P12_PASSWORD

echo "【2/3】App Store Connect API 密钥（公证用）"
KEY=$(ls ~/.appstoreconnect/private_keys/AuthKey_*.p8 2>/dev/null | head -1 || true)
if [[ -z "$KEY" ]]; then
  read -r -p "  .p8 文件路径: " KEY
fi
[[ -f "$KEY" ]] || { echo "  找不到 .p8 文件" >&2; exit 1; }
KID=$(basename "$KEY" .p8); KID=${KID#AuthKey_}
echo "  密钥文件：$KEY"
echo "  Key ID：$KID"
read -r -p "  Issuer ID: " ISSUER
echo "  验证中…"
xcrun notarytool history --key "$KEY" --key-id "$KID" --issuer "$ISSUER" >/dev/null || { echo "  验证失败，检查 Issuer ID" >&2; exit 1; }
printf '%s' "$KID" | secret ASC_KEY_ID
printf '%s' "$ISSUER" | secret ASC_ISSUER_ID
base64 -i "$KEY" | secret ASC_KEY_P8_BASE64

echo "【3/3】Sparkle 更新签名私钥（从钥匙串账户 keypop 导出）"
BIN=build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin
if [[ ! -x $BIN/generate_keys ]]; then
  xcodegen generate --quiet
  xcodebuild -resolvePackageDependencies -project KeyPop.xcodeproj -scheme KeyPop -derivedDataPath build/DerivedData >/dev/null
fi
SPK=$(mktemp /tmp/keypop-sparkle.XXXXXX)
trap 'rm -f "$SPK"; security delete-keychain "$TMPKC" 2>/dev/null || true' EXIT
rm -f "$SPK"
"$BIN/generate_keys" --account keypop -x "$SPK" >/dev/null
secret SPARKLE_PRIVATE_KEY < "$SPK"
rm -f "$SPK"

echo
echo "全部配置好了。发布新版本：GitHub → Actions → Release → Run workflow"
echo "或命令行：gh workflow run release.yml --repo $REPO -f version=1.0.0 -f notes=\"第一个版本\""
