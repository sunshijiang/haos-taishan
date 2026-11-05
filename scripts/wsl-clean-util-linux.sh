#!/usr/bin/env bash
# Clean the util-linux build state so that it is configured again with the
# autoconf from ~/.local/bin. Runs inside WSL2.
set -uo pipefail

B="$HOME/haos-taishan-build/upstream"

echo "=== autoconf 版本（构建时用的是 PATH 里的） ==="
PATH="$HOME/.local/bin:$PATH" autoconf --version | head -1

echo ""
echo "=== 删除 util-linux 的构建目录与 stamp ==="
rm -rf "$B/output/build/host-util-linux-2.40.4"
rm -f  "$B"/output/build/host-util-linux-*.stamp* 2>/dev/null
rm -rf "$B/output/target/build/host-util-linux-2.40.4" 2>/dev/null
ls -d "$B"/output/build/host-util-linux* 2>&1 | head -2

echo ""
echo "=== 剩余构建目录大小 ==="
du -sh "$B/output/build" 2>/dev/null
