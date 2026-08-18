#!/usr/bin/env bash
#
# 1024×1024 の PNG から、アプリアイコン（AppIcon）用の各サイズを書き出すスクリプト。
# macOS 標準の sips を使うので追加インストールは不要です。
#
# 使い方（Terminal で）:
#   ./make_icon.sh <元画像.png>
#   例:  ./make_icon.sh ~/Desktop/ultragrid_icon.png
#
# 実行後に ./build_app.sh を走らせるとアイコンが反映されます。
#
set -euo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SRC="${1:-}"
SET_DIR="Sources/UltraGrid/Assets.xcassets/AppIcon.appiconset"

die() { printf "\n\033[1;31m✗ %s\033[0m\n" "$1"; exit 1; }
ok()  { printf "\033[1;32m✓ %s\033[0m\n" "$1"; }

[ -n "${SRC}" ] || die "元画像を指定してください。  例:  ./make_icon.sh ~/Desktop/icon.png"
[ -f "${SRC}" ] || die "ファイルが見つかりません: ${SRC}"
[ -d "${SET_DIR}" ] || die "AppIcon.appiconset が見つかりません（プロジェクト直下で実行してください）。"

# 画像サイズを確認（正方形＆1024px 以上を推奨）。
W=$(sips -g pixelWidth  "${SRC}" | awk '/pixelWidth/{print $2}')
H=$(sips -g pixelHeight "${SRC}" | awk '/pixelHeight/{print $2}')
echo "元画像: ${W}×${H}px"
if [ "${W}" != "${H}" ]; then
  echo "\033[1;33m⚠ 正方形ではありません。1024×1024 に引き伸ばされます（推奨: 最初から正方形）。\033[0m"
fi
if [ "${W}" -lt 1024 ] || [ "${H}" -lt 1024 ]; then
  echo "\033[1;33m⚠ 1024px 未満です。拡大されるためぼやける可能性があります（推奨: 1024×1024）。\033[0m"
fi

# 一旦 1024×1024 に整える。
TMP="$(mktemp -d)/base_1024.png"
sips -s format png "${SRC}" --resampleHeightWidth 1024 1024 --out "${TMP}" >/dev/null

gen() { # gen <px>
  sips -z "$1" "$1" "${TMP}" --out "${SET_DIR}/icon_$1.png" >/dev/null
  ok "icon_$1.png"
}

echo "各サイズを書き出し中…"
for px in 16 32 64 128 256 512 1024; do gen "${px}"; done

rm -f "$(dirname "${TMP}")"/* 2>/dev/null || true
printf "\n\033[1;32m✅ アイコンを更新しました。\033[0m\n  次に  ./build_app.sh  を実行すると反映されます。\n"
