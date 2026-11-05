#!/usr/bin/env bash
# Find where Buildroot sets the WGET command and the download helper.
set -uo pipefail

B="$HOME/haos-taishan-build/upstream/buildroot"

echo "=== WGET 定义 (全 buildroot 搜索) ==="
grep -rn "WGET" "$B/support/download/helpers" "$B/support/download/dl-wrapper" \
        "$B/package/pkg-download.mk" "$B/Makefile" 2>/dev/null | head -10

echo ""
echo "=== helpers 目录 ==="
ls "$B/support/download/helpers" 2>/dev/null
echo "--- default.post ---"
cat "$B/support/download/helpers/default.post" 2>/dev/null | head -20

echo ""
echo "=== BR2_PRIMARY_SITE 默认值 ==="
grep -rn "BR2_PRIMARY_SITE" "$B/Config.in" "$B/package/pkg-download.mk" 2>/dev/null | head -6

echo ""
echo "=== 卡住的 zlib 文件现状 ==="
ls -la /cache/dl/libzlib/ 2>/dev/null
ls -la /home/sun/haos-taishan-build/upstream/output/build/.zlib-*/output 2>/dev/null | head -3
