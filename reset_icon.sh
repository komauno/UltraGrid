#!/usr/bin/env bash
#
# 設定したアプリアイコンをリセットして、デフォルトアイコンに戻すスクリプト。
# 生成済みの icon_*.png を削除し、AppIcon の参照を空にします。
#
# 使い方:
#   ./reset_icon.sh
#   その後  ./build_app.sh  で反映（デフォルトアイコンに戻る）
#
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SET_DIR="Sources/UltraGrid/Assets.xcassets/AppIcon.appiconset"
[ -d "${SET_DIR}" ] || { echo "AppIcon.appiconset が見つかりません。"; exit 1; }

# 生成済みアイコンを削除。
rm -f "${SET_DIR}"/icon_*.png

# 参照を空にした Contents.json に戻す。
cat > "${SET_DIR}/Contents.json" <<'JSON'
{
  "images" : [
    { "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON

printf "\033[1;32m✓ アイコンをリセットしました。\033[0m\n  ./build_app.sh で反映するとデフォルトアイコンに戻ります。\n  新しいアイコンにするときは  ./make_icon.sh <画像.png>  を実行してください。\n"
