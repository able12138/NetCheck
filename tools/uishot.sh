#!/bin/bash
# 离屏渲染界面快照（不需要屏幕录制权限）：每个界面单独进程渲染，避免相互干扰
set -e
PROJ="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$PROJ/src"
OUT="$PROJ/build/uishot"
DIR="${1:-/tmp/netcheck_ui}"
mkdir -p "$PROJ/build" "$DIR"

FILES=()
for f in "$SRC"/*.swift; do
    case "$(basename "$f")" in
        AppEntry.swift) continue ;;   # 排除 App 入口（避免与快照程序争夺 @main）
    esac
    FILES+=("$f")
done

swiftc -parse-as-library -O \
    -target x86_64-apple-macos14.0 \
    -framework SwiftUI -framework AppKit -framework Charts -framework CoreWLAN -framework CoreLocation \
    "${FILES[@]}" "$PROJ/tools/uishot.swift" \
    -o "$OUT"

echo "已编译: $OUT"
for v in home speed nodes lan wifi info; do
    "$OUT" "$DIR" "$v"
done
