#!/usr/bin/env bash
#
# UltraGrid をコマンド一発でビルドして、ちゃんとした .app として
# /Applications にインストールし、起動するスクリプト。
#
# 使い方（Terminal で）:
#   cd <このスクリプトがあるフォルダ>
#   ./build_app.sh
#
# 前提: macOS + Xcode 本体がインストール済み（xcodebuild が必要）。
#
set -euo pipefail

# スクリプトのある場所（＝プロジェクト直下）へ移動。
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

APP_NAME="UltraGrid"
CONFIG="Release"
DERIVED="build"
INSTALL_DIR="/Applications"

say() { printf "\n\033[1;34m▶︎ %s\033[0m\n" "$1"; }
ok()  { printf "\033[1;32m✓ %s\033[0m\n" "$1"; }
die() { printf "\n\033[1;31m✗ %s\033[0m\n" "$1"; exit 1; }

# ── 1. 必要ツールの確認 ────────────────────────────────
say "1/5  ツールを確認"

# 完全版 Xcode（xcodebuild）。CommandLineTools だけでは不可。
if ! xcodebuild -version >/dev/null 2>&1; then
  die "Xcode が見つかりません。App Store で Xcode を入れ、一度起動して同意した後、
     sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
     を実行してから、もう一度このスクリプトを走らせてください。"
fi
ok "Xcode: $(xcodebuild -version | head -1)"

# XcodeGen（project.yml → .xcodeproj）。無ければ Homebrew で導入。
if ! command -v xcodegen >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    say "xcodegen が無いので Homebrew で導入します"
    brew install xcodegen
  else
    die "xcodegen も Homebrew もありません。先に Homebrew を入れてください:
     https://brew.sh
     その後 'brew install xcodegen' でも可。"
  fi
fi
ok "xcodegen: $(xcodegen --version 2>/dev/null | head -1)"

# ── 2. Xcode プロジェクトを生成 ──────────────────────────
say "2/5  project.yml から Xcode プロジェクトを生成"
xcodegen generate
ok "${APP_NAME}.xcodeproj を生成"

# ── 3. ビルド（Release / ローカル用のアドホック署名）──────
say "3/5  ビルド（${CONFIG}）— 数十秒かかることがあります"
rm -rf "${DERIVED}"
xcodebuild \
  -project "${APP_NAME}.xcodeproj" \
  -scheme "${APP_NAME}" \
  -configuration "${CONFIG}" \
  -derivedDataPath "${DERIVED}" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGN_STYLE=Manual \
  ENABLE_HARDENED_RUNTIME=NO \
  -quiet \
  build
APP_PATH="${DERIVED}/Build/Products/${CONFIG}/${APP_NAME}.app"
[ -d "${APP_PATH}" ] || die "ビルド成果物が見つかりません: ${APP_PATH}"
ok "ビルド完了"

# ── 4. /Applications へインストール ─────────────────────
say "4/5  ${INSTALL_DIR} へインストール"
# 既に起動中なら終了しておく（上書きのため）。
osascript -e 'tell application "UltraGrid" to quit' >/dev/null 2>&1 || true
pkill -x "${APP_NAME}" >/dev/null 2>&1 || true
sleep 1
rm -rf "${INSTALL_DIR}/${APP_NAME}.app"
cp -R "${APP_PATH}" "${INSTALL_DIR}/"
# ダウンロード隔離属性を外して初回起動の警告を減らす。
xattr -dr com.apple.quarantine "${INSTALL_DIR}/${APP_NAME}.app" 2>/dev/null || true
ok "設置: ${INSTALL_DIR}/${APP_NAME}.app"

# ── 5. 自動起動を初期ONにして起動 ───────────────────────
say "5/5  自動起動を設定して起動"
# 設定ファイルがまだ無い初回だけ、ログイン時起動を ON にしておく。
SETTINGS_DIR="${HOME}/Library/Application Support/UltraGrid"
SETTINGS_FILE="${SETTINGS_DIR}/settings.json"
if [ ! -f "${SETTINGS_FILE}" ]; then
  mkdir -p "${SETTINGS_DIR}"
  printf '{\n  "launchAtLogin" : true\n}\n' > "${SETTINGS_FILE}"
  ok "初回設定: ログイン時に自動起動を ON"
else
  ok "既存の設定を尊重（自動起動はアプリ内トグルで変更できます）"
fi

open "${INSTALL_DIR}/${APP_NAME}.app"

printf "\n\033[1;32m✅ 完成しました\033[0m\n"
cat <<EOF
  ・アプリ: ${INSTALL_DIR}/${APP_NAME}.app（Launchpad / Spotlight から起動できます）
  ・メニューバーに UltraGrid のアイコンが出ます（Dock には出ません）
  ・初回は「アクセシビリティ」の許可を求められます:
      システム設定 → プライバシーとセキュリティ → アクセシビリティ で UltraGrid を ON
  ・自動起動の切り替え: メニューバーアイコン → 設定… → 一般 →「ログイン時に UltraGrid を起動する」

  次回から更新したいときは、このスクリプトをもう一度実行するだけです。
EOF
