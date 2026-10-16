#!/bin/bash
# 构建「网络体检 / NetCheck」原生 App（无需 Xcode，仅用 Command Line Tools 的 swiftc）
#
#   ./build.sh              以本机架构构建
#   ./build.sh --universal  构建 Intel + Apple Silicon 通用二进制（在任一架构机器上均可）
set -e

PROJ="$(cd "$(dirname "$0")" && pwd)"
SRC="$PROJ/src"
RES="$PROJ/resources"
BUILD="$PROJ/build"
APP="$BUILD/网络体检.app"
APPID="io.github.able12138.netcheck"
VERSION="1.2.0"
MINOS="14.0"

UNIVERSAL=0
for a in "$@"; do
    case "$a" in
        --universal) UNIVERSAL=1 ;;
        *) echo "未知参数: $a"; exit 1 ;;
    esac
done

SWIFT_FLAGS=(-parse-as-library -O
    -framework SwiftUI -framework AppKit -framework Charts
    -framework CoreWLAN -framework CoreLocation)

echo "==> 清理"
rm -rf "$BUILD"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> 生成图标"
ICONSET="$BUILD/AppIcon.iconset"
swiftc -O "$PROJ/tools/genicon.swift" -o "$BUILD/genicon" >/dev/null
"$BUILD/genicon" "$ICONSET" >/dev/null
iconutil --convert icns --output "$APP/Contents/Resources/AppIcon.icns" "$ICONSET"
rm -rf "$ICONSET" "$BUILD/genicon"

build_arch() {   # $1 = 架构
    local arch="$1"
    echo "==> 编译 Swift 源码（$arch）"
    swiftc "${SWIFT_FLAGS[@]}" -target "${arch}-apple-macos${MINOS}" \
        "$SRC"/*.swift -o "$BUILD/NetCheckCN.$arch"
}

if [ "$UNIVERSAL" = "1" ]; then
    build_arch x86_64
    build_arch arm64
    echo "==> 合并为通用二进制"
    lipo -create "$BUILD/NetCheckCN.x86_64" "$BUILD/NetCheckCN.arm64" \
         -output "$APP/Contents/MacOS/NetCheckCN"
    rm -f "$BUILD"/NetCheckCN.x86_64 "$BUILD"/NetCheckCN.arm64
else
    build_arch "$(uname -m)"
    mv "$BUILD/NetCheckCN.$(uname -m)" "$APP/Contents/MacOS/NetCheckCN"
fi

echo "==> 装配资源"
cp "$RES/Info.plist" "$APP/Contents/Info.plist"
cp "$RES/ieee-oui.txt" "$APP/Contents/Resources/ieee-oui.txt"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# 版本号写入 Info.plist（与 git tag 对齐）
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist" 2>/dev/null || true

echo "==> 临时签名（ad-hoc）"
codesign --force --sign - --identifier "$APPID" "$APP" 2>/dev/null || true

echo "==> 校验签名与架构"
lipo -archs "$APP/Contents/MacOS/NetCheckCN" 2>/dev/null || true
codesign -dv "$APP" 2>&1 | grep -E "Identifier|Signature" || true

echo "==> 完成：$APP"
du -sh "$APP"
