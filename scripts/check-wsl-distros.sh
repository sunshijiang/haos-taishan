#!/usr/bin/env bash
# Report the glibc version of every WSL distribution. Runs from Windows.
set -uo pipefail

WSL="$WINDIR/System32/wsl.exe"

for d in Ubuntu-22.04 Debian Ubuntu-18.04; do
    echo "=== $d ==="
    out=$("$WSL" -d "$d" -- bash -c '
        . /etc/os-release 2>/dev/null
        echo "  发行版: ${PRETTY_NAME:-未知}"
        echo "  glibc : $(ldd --version 2>/dev/null | head -1)"
        echo "  gcc   : $(gcc --version 2>/dev/null | head -1)"
    ' 2>/dev/null | tr -d '\0')
    if [ -n "$out" ]; then
        printf '%s\n' "$out"
    else
        echo "  (无法启动)"
    fi
done
