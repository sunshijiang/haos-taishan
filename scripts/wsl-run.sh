#!/usr/bin/env bash
# Drive the build from the Windows side.
#
# It prepares the cache directory that the defconfig expects, then runs the
# build inside WSL2 and streams the log into the repository.
#
#     bash scripts/wsl-run.sh [options for wsl-build.sh]
#
# The cache directory is created as root because / belongs to root, and WSL
# allows starting a distribution as root without a password.
set -uo pipefail

REPO="/mnt/e/sun/TSP/haos-taishan"
DISTRO="${WSL_DISTRO:-Ubuntu-22.04}"
LOG_LOCAL="/e/sun/TSP/haos-taishan/wsl-build-output.log"
WSL="$WINDIR/System32/wsl.exe"

echo "=== [$(date '+%F %T')] WSL2 build starting ==="

# The defconfig points BR2_DL_DIR and BR2_CCACHE_DIR at /cache, which is
# where the upstream builder container mounts them. The same directory has
# to exist here.
echo "Preparing /cache"
"$WSL" -d "$DISTRO" -u root -- bash -c '
    mkdir -p /cache/dl /cache/cc
    chmod -R 0777 /cache
    ls -ld /cache /cache/dl /cache/cc
' || {
    echo "Could not prepare /cache" >&2
    exit 1
}

echo ""
"$WSL" -d "$DISTRO" -- bash -c "cd '$REPO' && exec bash scripts/wsl-build.sh $*" 2>&1 | tee -a "$LOG_LOCAL"
rc=${PIPESTATUS[0]}

echo ""
echo "=== [$(date '+%F %T')] WSL2 build finished, exit code ${rc} ==="
exit $rc
