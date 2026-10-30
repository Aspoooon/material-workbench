#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
STAGE=$(mktemp -d /tmp/material-dmg.XXXXXX)
trap 'rm -rf "$STAGE"' EXIT
ditto "dist/素材工作台.app" "$STAGE/素材工作台.app"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/安装说明.txt" <<'TXT'
把「素材工作台」拖到「Applications」即可安装。
Apple Silicon，macOS 27 或以上；无需安装其他依赖。
当前为本机临时签名，没有 Developer ID 签名或 Apple 公证。
如 macOS 拦截来源已确认的这份应用，可在「系统设置 → 隐私与安全性」确认打开。
应用默认保护原素材。重命名会直接修改原文件名，可在当前会话内撤销。
TXT
hdiutil create -volname '素材工作台' -srcfolder "$STAGE" -ov -format UDZO "dist/素材工作台.dmg"
hdiutil verify "dist/素材工作台.dmg"
