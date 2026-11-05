#!/usr/bin/env bash
# Show a range of the Buildroot log. Runs inside WSL2.
#   bash wsl-log-show.sh <start> <end>
set -uo pipefail

LOG="$HOME/haos-taishan-build/build.log"
START="${1:-1}"
END="${2:-200}"

sed -n "${START},${END}p" "$LOG" | cut -c1-220
