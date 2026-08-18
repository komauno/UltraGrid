#!/usr/bin/env bash
#
# GitHub Releases に上げる配布用 zip を作るスクリプト。
# アプリをビルドし、UltraGrid.app を zip に固めて dist/ に出力します。
# （無料配布向け＝署名・公証なし。ダウンロードした人は初回だけ Gatekeeper の
#   許可が必要です。手順は README に記載。）
#
# 使い方:
#   ./release_zip.sh            # バージョンは Info.plist の値を使う
#   ./release_zip.sh 0.1.0      # バージョンを指定
#
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

APP_NAME="UltraGrid"
CONFIG="Release"
DERIVED="build"
DIST="dist"

say() { printf "\n\033[1;34m▶︎ %s\033[0m\n" "$1"; }
die() { printf "\n\033[1;31m✗ %s\033[0m\n" "$1"; exit 1; }

command -v xcodegen >/dev/null 2>&1 || die "xcodegen がありません（brew install xcodegen）。"
xcodebuild -version >/dev/null 2>&1 || die "Xcode が必要です。"

say "プロジェクト生成"
xcodegen generate

say "ビルド（${CONFIG}）"
rm -rf "${DERIVED}"
xcodebuild \
  -project "${APP_NAME}.xcodeproj" \
  -scheme "${APP_NAME}" \
  -configuration "${CONFIG}" \
  -derivedDataPath "${DERIVED}" \
  CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual ENABLE_HARDENED_RUNTIME=NO \
  -quiet build

APP_PATH="${DERIVED}/Build/Products/${CONFIG}/${APP_NAME}.app"
[ -d "${APP_PATH}" ] || die "ビルド成果物が見つかりません。"

# バージョン（引数 > Info.plist）
VER="${1:-}"
if [ -z "${VER}" ]; then
  VER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${APP_PATH}/Contents/Info.plist" 2>/dev/null || echo "0.0.0")
fi

say "zip を作成（dist/${APP_NAME}-${VER}.zip）"
mkdir -p "${DIST}"
ZIP="${DIST}/${APP_NAME}-${VER}.zip"
rm -f "${ZIP}"
# ditto でリソースフォークやシンボリックリンクを保ったまま圧縮（.app 配布の定番）。
ditto -c -k --sequesterRsrc --keepParent "${APP_PATH}" "${ZIP}"

printf "\n\033[1;32m✅ 完成: %s\033[0m\n" "$(pwd)/${ZIP}"
echo "  この zip を GitHub の Releases に添付してください。"
