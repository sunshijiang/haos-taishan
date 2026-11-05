#!/usr/bin/env bash
# Report the state of the local WSL2 build. Runs inside WSL2.
set -uo pipefail

BUILD="${BUILD_ROOT:-$HOME/haos-taishan-build}"
LOG="$BUILD/build.log"
OUT="${OUTPUT_DIR:-/mnt/e/sun/TSP/haos-taishan/output/images}"

if [ -f "$LOG" ]; then
    echo "--- 构建日志尾部 ---"
    tail -n 8 "$LOG"
    echo ""
    printf '  已处理包数: %s\n' "$(grep -cE '^>>> ' "$LOG" 2>/dev/null)"
    printf '  日志大小  : %s\n' "$(du -h "$LOG" | cut -f1)"
else
    echo "  (还没有构建日志)"
fi

echo ""
echo "--- 磁盘占用 ---"
du -sh "$BUILD/upstream/output" 2>/dev/null | sed 's/^/  output: /'
du -sh /cache/dl 2>/dev/null | sed 's/^/  源码缓存: /'
du -sh /cache/cc 2>/dev/null | sed 's/^/  ccache: /'

echo ""
echo "--- 产物 ---"
if [ -d "$OUT" ]; then
    ls -lh "$OUT" | tail -5
else
    echo "  (尚未生成)"
fi
