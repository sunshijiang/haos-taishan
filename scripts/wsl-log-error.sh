#!/usr/bin/env bash
# Show the current build failure. Runs inside WSL2.
set -uo pipefail

LOG="$HOME/haos-taishan-build/build.log"

echo "=== 错误行 ==="
grep -nE "error:|Error [0-9]+|configure: error" "$LOG" 2>/dev/null | grep -viE "warning" | tail -12

echo ""
echo "=== 最后 25 行 ==="
tail -25 "$LOG" 2>/dev/null | cut -c1-200

echo ""
echo "=== autoreconf 实际用的命令 ==="
grep -nE "autoreconf|aclocal|libtoolize" "$LOG" 2>/dev/null | tail -8

echo ""
echo "=== PATH 中的 autoconf ==="
which autoconf 2>/dev/null
autoconf --version 2>/dev/null | head -1
