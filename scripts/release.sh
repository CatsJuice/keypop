#!/usr/bin/env bash
# 发布新版本：构建 → 签名 → 公证 → 打 DMG → Sparkle 签名 → 更新 appcast.xml → 推送并创建 GitHub Release
#
#   ./scripts/release.sh 1.1.0 "新增了 xxx；修复了 yyy"
#
# 平时由 GitHub Actions（.github/workflows/release.yml）调用；本地也能跑。
#
# 可选环境变量：
#   NOTARY_PROFILE=keypop-notary   notarytool 钥匙串配置名（本地用）
#   ASC_KEY_PATH / ASC_KEY_ID / ASC_ISSUER_ID   用 App Store Connect API 密钥公证（CI 用，优先于 NOTARY_PROFILE）
#   SPARKLE_KEY_FILE               Sparkle 私钥文件（CI 用；不设则从钥匙串账户 keypop 读取）
#   DRY_RUN=1                      只在 build/release/<版本> 里打包，不改仓库、不推送、不发 Release
#   SKIP_NOTARIZE=1                跳过公证（仅限 DRY_RUN 自测用）
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=${1:?用法: ./scripts/release.sh <版本号，如 1.1.0> [更新说明]}
NOTES=${2:-"问题修复和体验改进。"}
NOTARY_PROFILE=${NOTARY_PROFILE:-keypop-notary}
DRY_RUN=${DRY_RUN:-0}
SKIP_NOTARIZE=${SKIP_NOTARIZE:-0}
REPO=CatsJuice/keypop
SPARKLE_ACCOUNT=keypop
if [[ -n ${ASC_KEY_PATH:-} ]]; then
  NOTARY_AUTH=(--key "$ASC_KEY_PATH" --key-id "${ASC_KEY_ID:?}" --issuer "${ASC_ISSUER_ID:?}")
else
  NOTARY_AUTH=(--keychain-profile "$NOTARY_PROFILE")
fi
if [[ -n ${SPARKLE_KEY_FILE:-} ]]; then
  SPARKLE_SIGN=(--ed-key-file "$SPARKLE_KEY_FILE")
else
  SPARKLE_SIGN=(--account "$SPARKLE_ACCOUNT")
fi

die() { echo "✗ $*" >&2; exit 1; }
step() { echo; echo "▸ $*"; }

[[ $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "版本号格式应为 x.y.z"
IFS=. read -r MA MI PA <<< "$VERSION"
BUILD=$((MA * 10000 + MI * 100 + PA))   # CFBundleVersion，随版本号单调递增，Sparkle 用它比较新旧

# ---------- 发布前检查 ----------
LOCAL_CFG=KeyPop/Config/Local.xcconfig
[[ -f $LOCAL_CFG ]] || die "缺少 $LOCAL_CFG（发布必须用 Developer ID 证书签名，见 Signing.xcconfig 里的说明）"
IDENTITY=$(sed -n 's/^CODE_SIGN_IDENTITY *= *//p' $LOCAL_CFG | tail -1)
[[ $IDENTITY == "Developer ID Application:"* ]] || die "Local.xcconfig 里的 CODE_SIGN_IDENTITY 必须是 Developer ID Application 证书"
# 钥匙串里可能有同名的过期证书，直接用名字签会报 ambiguous，所以取有效证书的 SHA-1
SIGN_HASH=$(security find-identity -v -p codesigning | grep -F "\"$IDENTITY\"" | head -1 | awk '{print $2}')
[[ -n $SIGN_HASH ]] || die "钥匙串里找不到有效的证书：$IDENTITY"

if [[ $DRY_RUN != 1 ]]; then
  [[ $SKIP_NOTARIZE != 1 ]] || die "正式发布不能跳过公证"
  [[ -z $(git status --porcelain) ]] || die "工作区有未提交的改动"
  [[ $(git branch --show-current) == main ]] || die "请在 main 分支发布"
  git fetch -q origin main
  [[ $(git rev-parse HEAD) == $(git rev-parse origin/main) ]] || die "本地 main 和 origin/main 不一致，先同步"
  ! git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null || die "tag v$VERSION 已存在"
  gh auth status >/dev/null 2>&1 || die "gh 未登录"
fi
if [[ $SKIP_NOTARIZE != 1 ]]; then
  xcrun notarytool history "${NOTARY_AUTH[@]}" >/dev/null 2>&1 ||
    die "公证凭据不可用（本地需先 xcrun notarytool store-credentials $NOTARY_PROFILE；CI 检查 ASC_* Secrets）"
fi

OUT=build/release/$VERSION
rm -rf "$OUT"; mkdir -p "$OUT"
APP=$OUT/KeyPop.app
DMG=$OUT/KeyPop-$VERSION.dmg

# ---------- 构建 ----------
step "构建 v$VERSION（build $BUILD）"
xcodegen generate --quiet
xcodebuild -project KeyPop.xcodeproj -scheme KeyPop -configuration Release -derivedDataPath build/DerivedData \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" OTHER_CODE_SIGN_FLAGS="--timestamp" \
  -quiet clean build
ditto build/DerivedData/Build/Products/Release/KeyPop.app "$APP"
codesign --verify --deep --strict "$APP"
[[ $(codesign -dv --verbose=2 "$APP" 2>&1) == *"(runtime)"* ]] || die "没有启用 Hardened Runtime，无法公证"
SPARKLE_BIN=build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin

notarize() { # $1 要提交的文件
  local result="$OUT/notary-$(basename "$1").json"
  xcrun notarytool submit "$1" "${NOTARY_AUTH[@]}" --wait --timeout 30m --output-format json > "$result" || true
  local status id
  status=$(plutil -extract status raw -o - "$result" 2>/dev/null || echo unknown)
  if [[ $status != Accepted ]]; then
    id=$(plutil -extract id raw -o - "$result" 2>/dev/null || true)
    [[ -n $id ]] && xcrun notarytool log "$id" "${NOTARY_AUTH[@]}" || true
    die "公证失败：$status"
  fi
}

# ---------- 公证 App ----------
if [[ $SKIP_NOTARIZE != 1 ]]; then
  step "公证 App（通常需要几分钟）"
  ditto -c -k --keepParent "$APP" "$OUT/KeyPop.zip"
  notarize "$OUT/KeyPop.zip"
  xcrun stapler staple "$APP"
  rm "$OUT/KeyPop.zip"
fi

# ---------- DMG ----------
step "制作 DMG"
STAGE=$OUT/dmg
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/KeyPop.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "KeyPop" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"
codesign --sign "$SIGN_HASH" --timestamp "$DMG"
if [[ $SKIP_NOTARIZE != 1 ]]; then
  step "公证 DMG"
  notarize "$DMG"
  xcrun stapler staple "$DMG"
fi

# ---------- Sparkle 签名 + appcast ----------
step "Sparkle 签名"
SIG=$("$SPARKLE_BIN/sign_update" "${SPARKLE_SIGN[@]}" "$DMG")   # 输出：sparkle:edSignature="…" length="…"
URL="https://github.com/$REPO/releases/download/v$VERSION/KeyPop-$VERSION.dmg"
APPCAST=appcast.xml
[[ $DRY_RUN == 1 ]] && { cp appcast.xml "$OUT/appcast.xml"; APPCAST=$OUT/appcast.xml; }
python3 - "$APPCAST" "$VERSION" "$BUILD" "$URL" "$SIG" "$NOTES" <<'PY'
import sys, html, email.utils
path, version, build, url, sig, notes = sys.argv[1:]
items = "".join(f"<li>{html.escape(n.strip())}</li>" for n in notes.replace("；", ";").split(";") if n.strip())
item = f"""    <item>
      <title>{version}</title>
      <pubDate>{email.utils.formatdate(usegmt=True)}</pubDate>
      <sparkle:version>{build}</sparkle:version>
      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description><![CDATA[<ul>{items}</ul>]]></description>
      <enclosure url="{url}" type="application/octet-stream" {sig.strip()} />
    </item>
"""
s = open(path, encoding="utf-8").read()
marker = "<language>zh-cn</language>\n"
assert marker in s, "appcast.xml 格式不对"
s = s.replace(marker, marker + item, 1)   # 最新版本放最前
open(path, "w", encoding="utf-8").write(s)
PY
echo "  $SIG"

if [[ $DRY_RUN == 1 ]]; then
  step "DRY_RUN 完成：$DMG"
  exit 0
fi

# ---------- 提交、打 tag、发 Release ----------
step "提交并发布 GitHub Release"
sed -i '' -E "s/^(    MARKETING_VERSION: ).*/\1\"$VERSION\"/; s/^(    CURRENT_PROJECT_VERSION: ).*/\1\"$BUILD\"/" project.yml
git add appcast.xml project.yml
git commit -q -m "Release v$VERSION"
git tag "v$VERSION"
git push -q origin "v$VERSION"
gh release create "v$VERSION" "$DMG" --repo "$REPO" --title "KeyPop $VERSION" --notes "$NOTES"
# Release 文件上传完再推 main，appcast 才指向已存在的下载地址
git push -q origin main
step "✓ v$VERSION 已发布：https://github.com/$REPO/releases/tag/v$VERSION"
