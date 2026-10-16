#!/bin/bash
# 引擎自检：用同一套源码（去掉 GUI 层）编译出命令行程序，真实跑各模块
set -e
PROJ="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$PROJ/src"
OUT="$PROJ/build/selftest"
mkdir -p "$PROJ/build"

swiftc -parse-as-library -O \
    -target x86_64-apple-macos14.0 \
    -framework Foundation -framework CoreWLAN -framework CoreLocation -framework AppKit \
    "$SRC/Shell.swift" "$SRC/Models.swift" "$SRC/HTTPMeter.swift" "$SRC/SpeedEngines.swift" \
    "$SRC/Nodes.swift" "$SRC/WiFiEngine.swift" "$SRC/LANScanner.swift" "$SRC/NetInfo.swift" \
    "$SRC/OUI.swift" "$PROJ/tools/selftest.swift" \
    -o "$OUT"

cp "$PROJ/resources/ieee-oui.txt" "$PROJ/build/ieee-oui.txt"
echo "自检程序: $OUT"
