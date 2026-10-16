#!/bin/bash
# 响应性自测：量化「界面卡不卡」（主线程排队延迟）+ 测速进度回调频率
set -e
PROJ="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$PROJ/src"
OUT="$PROJ/build/perfcheck"
mkdir -p "$PROJ/build"

swiftc -parse-as-library -O \
    -target x86_64-apple-macos14.0 \
    -framework CoreWLAN -framework CoreLocation -framework AppKit \
    "$SRC/Models.swift" "$SRC/Shell.swift" "$SRC/HTTPMeter.swift" "$SRC/WiFiEngine.swift" \
    "$SRC/LANScanner.swift" "$SRC/OUI.swift" "$SRC/NetInfo.swift" "$SRC/SpeedEngines.swift" \
    "$SRC/Nodes.swift" "$PROJ/tools/perfcheck.swift" \
    -o "$OUT"

echo "编译完成，开始测量（约 20 秒）…"
script -q /tmp/netcheck_perf.log "$OUT"
echo
echo "参考基准（2026-10-16 本机实测）："
echo "  优化前 T1 主线程最大排队 1670ms / T2 回调 53.5 次每秒"
echo "  优化后 T1 主线程最大排队    0ms / T2 回调  4.2 次每秒"
