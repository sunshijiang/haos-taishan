#!/usr/bin/env bash
#
# wsl-setup.sh - Install the build dependencies inside WSL2.
#
# The Home Assistant OS build is a Buildroot cross compilation. It needs a
# normal Linux userland with the usual build tools, no Docker involved.
# The package list is the one from the upstream builder image
# (buildroot-external/Dockerfile), so the result is the same image.
#
# Run this inside WSL2:
#     bash scripts/wsl-setup.sh
#
set -euo pipefail

if [ ! -e /proc/sys/kernel/osrelease ] || ! grep -qi microsoft /proc/version 2>/dev/null; then
    echo "This script has to run inside WSL2." >&2
    exit 1
fi

if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    SUDO="sudo"
fi

. /etc/os-release
echo "[setup] Distribution: ${PRETTY_NAME:-unknown}"

PKGS="automake bash bc binutils build-essential bzip2 cpio e2fsprogs file git
      graphviz help2man jq make ncurses-dev openssh-client patch perl pigz
      python3 python3-matplotlib python-is-python3 qemu-utils rsync skopeo
      sudo texinfo unzip wget zip ccache"

echo "[setup] Installing the build dependencies"
${SUDO} apt-get update
# shellcheck disable=SC2086
${SUDO} apt-get install -y --no-install-recommends ${PKGS}

echo "[setup] Checking the tools"
missing=0
for tool in gcc g++ make git wget rsync unzip file python3 skopeo ccache patch; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
        echo "  MISSING: ${tool}" >&2
        missing=1
    fi
done

if [ "${missing}" -ne 0 ]; then
    echo "[setup] Some tools are still missing, check the output above." >&2
    exit 1
fi

cat <<EOF

[setup] Done.

  gcc      $(gcc --version | head -1)
  make     $(make --version | head -1)
  skopeo   $(skopeo --version)
  ccache   $(ccache --version | head -1)

  Next:
    bash scripts/wsl-build.sh

EOF
