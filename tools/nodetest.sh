#!/bin/bash
# 节点目录真实复验：全跑一遍 NodeCatalog，输出状态/速度/失败归因
# 用法：./tools/nodetest.sh [每节点秒数，默认 6]
set -e
PROJ="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$PROJ/src"
OUT="$PROJ/build/nodetest"
mkdir -p "$PROJ/build"

swiftc -parse-as-library -O \
    -target x86_64-apple-macos14.0 \
    "$SRC/Models.swift" "$SRC/Shell.swift" "$SRC/HTTPMeter.swift" \
    "$SRC/Nodes.swift" "$SRC/SpeedEngines.swift" \
    "$PROJ/tools/nodetest.swift" \
    -o "$OUT"

script -q /tmp/netcheck_nodetest.log "$OUT" "$@"
