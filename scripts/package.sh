#!/bin/zsh
# 编译 Release 版并打包成 DMG（拖进「应用程序」安装），产物在 dist/
# 可选环境变量：VERSION=1.1 覆盖 App 版本号（默认取工程里的 MARKETING_VERSION）
set -euo pipefail

cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

VERSION="${VERSION:-$(xcodebuild -project EyeBreak.xcodeproj -target EyeBreak -configuration Release -showBuildSettings 2>/dev/null \
  | awk '/ MARKETING_VERSION =/ { print $3 }')}"
APP=build/Build/Products/Release/EyeBreak.app
DMG=dist/EyeBreak-$VERSION.dmg
STAGING=build/dmg-staging

echo "==> Building EyeBreak $VERSION (Release)"
xcodebuild -project EyeBreak.xcodeproj -scheme EyeBreak -configuration Release -derivedDataPath build \
  -destination 'generic/platform=macOS' MARKETING_VERSION="$VERSION" build -quiet

echo "==> Creating $DMG"
rm -rf "$STAGING" && mkdir -p "$STAGING" dist
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname "EyeBreak" -srcfolder "$STAGING" -ov -format UDZO "$DMG" -quiet
rm -rf "$STAGING"

shasum -a 256 "$DMG"
