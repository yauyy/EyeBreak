#!/bin/zsh
# 编译 Release 版，打包成 DMG（拖进「应用程序」安装），并生成 Sparkle 更新源 appcast.xml。产物在 dist/
#
# 可选环境变量：
#   VERSION=1.2               覆盖 App 版本号（默认取工程里的 MARKETING_VERSION）
#   BUILD=42                  覆盖构建号（默认取 git 提交数，保证每次发布递增；Sparkle 靠它判断新旧）
#   SKIP_BUILD_CHECK=1        跳过线上构建号校验（仅用于本机测试打包，禁止用于发布）
#   SPARKLE_KEY_FILE=path     用文件里的私钥签名（默认从钥匙串读取 generate_keys 生成的私钥）
#   SPARKLE_PUBLIC_KEY=...    覆盖内置公钥（仅用于本机测试）
#   SPARKLE_FEED_URL=...      覆盖更新源地址（仅用于本机测试）
#   DOWNLOAD_URL_PREFIX=...   覆盖 appcast 里的下载地址前缀（仅用于本机测试）
#   DERIVED_DATA=path         构建目录（默认 ~/Library/Developer/Xcode/DerivedData/EyeBreak-build）。
#                             不要放在「文稿」「桌面」等受保护的文件夹里，否则每次运行编出来的 App 都会弹访问权限提示
#
# 更新说明：如果存在 docs/release-notes/<版本号>.md，会嵌入 appcast，显示在 Sparkle 的更新窗口里。
set -euo pipefail

cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

setting() {
  xcodebuild -project EyeBreak.xcodeproj -target EyeBreak -configuration Release -showBuildSettings 2>/dev/null \
    | awk -v key="$1" '$1 == key && $2 == "=" { sub(/^[^=]*= /, ""); print; exit }'
}

normalize_build_number() {
  local value="$1"
  while [[ "$value" == 0* && ${#value} -gt 1 ]]; do
    value="${value#0}"
  done
  printf '%s' "$value"
}

build_number_is_greater() {
  # 用长度和字典序比较，避免构建号超过 shell 整数范围时溢出。
  [[ ${#1} -gt ${#2} || ( ${#1} -eq ${#2} && "$1" > "$2" ) ]]
}

check_build_number() {
  if [[ ! "$BUILD" =~ '^[0-9]+$' ]]; then
    echo "错误：新构建号必须是非负十进制整数，当前为：$BUILD" >&2
    exit 1
  fi
  if [[ "${SKIP_BUILD_CHECK:-}" == 1 ]]; then
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" >&2
    echo "警告：SKIP_BUILD_CHECK=1，已跳过线上构建号校验！仅用于本机测试，禁止发布本次产物。" >&2
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" >&2
    return
  fi

  # 始终检查正式更新源，不能被本机测试用的 SPARKLE_FEED_URL 覆盖。
  local latest_feed="https://github.com/yauyy/EyeBreak/releases/latest/download/appcast.xml"
  local feed_xml version_count version_value version_index latest_build=0
  local version_xpath="//*[local-name()='version' and namespace-uri()='http://www.andymatuschak.org/xml-namespaces/sparkle'] | //@*[local-name()='version' and namespace-uri()='http://www.andymatuschak.org/xml-namespaces/sparkle']"
  if ! feed_xml="$(curl --fail --location --silent --show-error --connect-timeout 15 --max-time 45 "$latest_feed")"; then
    echo "错误：无法读取线上 appcast，未能确认最新构建号，已停止打包。" >&2
    exit 1
  fi
  if ! printf '%s' "$feed_xml" | /usr/bin/xmllint --nonet --noout - 2>/dev/null; then
    echo "错误：线上 appcast XML 解析失败，已停止打包。" >&2
    exit 1
  fi
  # 兼容 version 元素和 enclosure 上的 version 属性，两者都按 Sparkle 命名空间读取。
  if ! version_count="$(printf '%s' "$feed_xml" | /usr/bin/xmllint --nonet --xpath "count($version_xpath)" - 2>/dev/null)" \
      || [[ ! "$version_count" =~ '^[0-9]+$' || "$version_count" == 0 ]]; then
    echo "错误：线上 appcast 中没有可读取的 sparkle:version，已停止打包。" >&2
    exit 1
  fi
  for (( version_index = 1; version_index <= version_count; version_index++ )); do
    if ! version_value="$(printf '%s' "$feed_xml" | /usr/bin/xmllint --nonet --xpath "string(($version_xpath)[$version_index])" - 2>/dev/null)" \
        || [[ ! "$version_value" =~ '^[0-9]+$' ]]; then
      echo "错误：线上 appcast 含有无法解析的 sparkle:version，已停止打包。" >&2
      exit 1
    fi
    version_value="$(normalize_build_number "$version_value")"
    if build_number_is_greater "$version_value" "$latest_build"; then
      latest_build="$version_value"
    fi
  done
  if ! build_number_is_greater "$(normalize_build_number "$BUILD")" "$latest_build"; then
    echo "错误：新构建号 $BUILD 必须严格大于线上最大构建号 $latest_build，已停止打包。" >&2
    echo "请增加提交数或使用 BUILD 指定更大的构建号。" >&2
    exit 1
  fi
  echo "==> 构建号校验通过：$BUILD > $latest_build"
}

VERSION="${VERSION:-$(setting MARKETING_VERSION)}"
BUILD="${BUILD:-$(git rev-list --count HEAD)}"
check_build_number
PUBLIC_KEY="${SPARKLE_PUBLIC_KEY:-$(setting SPARKLE_PUBLIC_KEY)}"
FEED_URL="${SPARKLE_FEED_URL:-$(setting SPARKLE_FEED_URL)}"
DOWNLOAD_URL_PREFIX="${DOWNLOAD_URL_PREFIX:-https://github.com/yauyy/EyeBreak/releases/download/v$VERSION/}"

if [[ -z "$PUBLIC_KEY" ]]; then
  echo "错误：工程里还没有配置 SPARKLE_PUBLIC_KEY，打出来的 App 无法自动更新。" >&2
  echo "先运行 generate_keys 生成密钥，把公钥填进 Xcode 的 SPARKLE_PUBLIC_KEY 构建设置。" >&2
  exit 1
fi

DERIVED_DATA="${DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/EyeBreak-build}"
APP=$DERIVED_DATA/Build/Products/Release/EyeBreak.app
DMG=dist/EyeBreak-$VERSION.dmg
STAGING=$DERIVED_DATA/dmg-staging
APPCAST_STAGING=$DERIVED_DATA/appcast-staging
SPARKLE_BIN=$DERIVED_DATA/SourcePackages/artifacts/sparkle/Sparkle/bin

echo "==> Building EyeBreak $VERSION ($BUILD) (Release)"
xcodebuild -project EyeBreak.xcodeproj -scheme EyeBreak -configuration Release -derivedDataPath "$DERIVED_DATA" \
  -destination 'generic/platform=macOS' \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" \
  SPARKLE_PUBLIC_KEY="$PUBLIC_KEY" SPARKLE_FEED_URL="$FEED_URL" \
  build -quiet

echo "==> Creating $DMG"
rm -rf "$STAGING" && mkdir -p "$STAGING" dist
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname "EyeBreak" -srcfolder "$STAGING" -ov -format UDZO "$DMG" -quiet
rm -rf "$STAGING"

echo "==> Generating dist/appcast.xml"
# 每次都重新生成：更新源只需要指向最新版本，也避免旧文件里的条目（例如本机测试的）混进正式发布
rm -f dist/appcast.xml
rm -rf "$APPCAST_STAGING" && mkdir -p "$APPCAST_STAGING"
cp "$DMG" "$APPCAST_STAGING/"
NOTES="docs/release-notes/$VERSION.md"
if [[ -f "$NOTES" ]]; then
  cp "$NOTES" "$APPCAST_STAGING/EyeBreak-$VERSION.md"
fi
KEY_ARGS=()
if [[ -n "${SPARKLE_KEY_FILE:-}" ]]; then
  KEY_ARGS=(--ed-key-file "$SPARKLE_KEY_FILE")
fi
"$SPARKLE_BIN/generate_appcast" "${KEY_ARGS[@]}" \
  --download-url-prefix "$DOWNLOAD_URL_PREFIX" \
  --embed-release-notes \
  --link "https://github.com/yauyy/EyeBreak" \
  --maximum-deltas 0 \
  -o "$PWD/dist/appcast.xml" \
  "$APPCAST_STAGING"
rm -rf "$APPCAST_STAGING"

shasum -a 256 "$DMG"
echo "==> 发布时上传这两个文件：$DMG dist/appcast.xml"
