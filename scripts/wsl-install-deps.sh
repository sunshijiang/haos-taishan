#!/usr/bin/env bash
# Install the missing build dependencies inside WSL2.
set -euo pipefail

if [ ! -e /proc/sys/kernel/osrelease ] || ! grep -qi microsoft /proc/version 2>/dev/null; then
    echo "This script has to run inside WSL2." >&2
    exit 1
fi

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
    SUDO="sudo"
fi

# The package list is the one from the upstream builder image
# (buildroot-external/Dockerfile), so the result is the same image.
PKGS="automake bash bc binutils build-essential bzip2 cpio e2fsprogs file git
      graphviz help2man jq make ncurses-dev openssh-client patch perl pigz
      python3 python3-matplotlib python-is-python3 qemu-utils rsync skopeo
      sudo texinfo unzip wget zip ccache"

echo "[setup] Installing the build dependencies"
${SUDO} apt-get update
# shellcheck disable=SC2086
${SUDO} apt-get install -y --no-install-recommends ${PKGS}
${SUDO} rm -rf /var/lib/apt/lists/*

echo "[setup] Done"
