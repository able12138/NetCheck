#!/bin/bash
# 更新 IEEE OUI 厂商库（官方权威数据，含 MA-L / MA-M / MA-S 三种长度）
# 输出格式（App 直接读取）：<6或7或9位十六进制大写前缀><空格><厂商名>
set -e
PROJ="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$PROJ/resources/ieee-oui.txt"
TMP="$(mktemp -d)"
CURL="/opt/local/bin/curl"; [ -x "$CURL" ] || CURL="/usr/bin/curl"

echo "==> 下载 IEEE 官方 OUI 数据"
"$CURL" -sL -m 60 -o "$TMP/mal.csv" "https://standards-oui.ieee.org/oui/oui.csv"
"$CURL" -sL -m 60 -o "$TMP/mam.csv" "https://standards-oui.ieee.org/oui28/mam.csv"
"$CURL" -sL -m 60 -o "$TMP/mas.csv" "https://standards-oui.ieee.org/oui36/oui36.csv"
wc -l "$TMP"/*.csv

echo "==> 合并为 App 读取格式"
/opt/local/bin/python3.12 - "$TMP" "$OUT" <<'PY'
import csv, sys, os
tmp, out = sys.argv[1], sys.argv[2]
rows = {}
for fn in ("mal.csv", "mam.csv", "mas.csv"):
    p = os.path.join(tmp, fn)
    if not os.path.exists(p):
        continue
    with open(p, newline="", encoding="utf-8", errors="ignore") as f:
        for r in csv.DictReader(f):
            a = (r.get("Assignment") or "").strip().upper()
            org = (r.get("Organization Name") or "").strip().replace("\t", " ")
            if len(a) in (6, 7, 9) and org:
                rows.setdefault(a, org)
with open(out, "w", encoding="utf-8") as f:
    for k in sorted(rows):
        f.write(f"{k}    {rows[k]}\n")
print(f"写入 {len(rows)} 条 → {out}")
PY
rm -rf "$TMP"
