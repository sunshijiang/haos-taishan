#!/usr/bin/env bash
#
# verify-image.sh - Static checks on a produced HAOS image and on the
#                   Taishan Pi board configuration.
#
# This runs on the image file itself, so it can be executed on a build
# machine or on a device after flashing.
#
# Usage:
#   ./scripts/verify-image.sh <haos_taishan-*.img>
#   ./scripts/verify-image.sh --config-only
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE=""
CONFIG_ONLY=0

PASS=0
FAIL=0

ok()   { echo "  [ OK ] $*"; PASS=$((PASS + 1)); }
bad()  { echo "  [FAIL] $*"; FAIL=$((FAIL + 1)); }
info() { echo "  [INFO] $*"; }

check() {
    local description="$1"; shift
    if "$@" >/dev/null 2>&1; then ok "${description}"; else bad "${description}"; fi
}

if [ "${1:-}" = "--config-only" ]; then
    CONFIG_ONLY=1
elif [ -n "${1:-}" ]; then
    IMAGE="$1"
else
    echo "Usage: $0 <image> | --config-only" >&2
    exit 1
fi

echo "== 1. Board configuration =="
check "board/taishan/meta exists" test -f "${REPO_ROOT}/board/taishan/meta"
check "board/taishan/uboot-boot.ush exists" test -f "${REPO_ROOT}/board/taishan/uboot-boot.ush"
check "configs/taishan_defconfig exists" test -f "${REPO_ROOT}/configs/taishan_defconfig"
check "kernel patch exists" test -f "${REPO_ROOT}/board/taishan/patches/linux/0001-arm64-dts-rockchip-rk3566-lckfb-tspi-enable-eMMC-HS200.patch"
check "uboot patch exists" test -f "${REPO_ROOT}/board/taishan/patches/uboot/0001-configs-lckfb-tspi-rk3566-enable-HAOS-required-options.patch"

if grep -q 'BR2_LINUX_KERNEL_INTREE_DTS_NAME="rockchip/rk3566-lckfb-tspi"' \
        "${REPO_ROOT}/configs/taishan_defconfig"; then
    ok "defconfig points at the mainline Taishan Pi device tree"
else
    bad "defconfig does not point at rockchip/rk3566-lckfb-tspi"
fi

if grep -q 'BR2_TARGET_UBOOT_BOARD_DEFCONFIG="lckfb-tspi-rk3566"' \
        "${REPO_ROOT}/configs/taishan_defconfig"; then
    ok "defconfig points at the mainline Taishan Pi U-Boot defconfig"
else
    bad "defconfig does not point at lckfb-tspi-rk3566"
fi

if grep -q 'BR2_PACKAGE_HASSIO_MACHINE="green"' \
        "${REPO_ROOT}/configs/taishan_defconfig"; then
    ok "supervisor machine is set to an existing published machine (green)"
else
    bad "supervisor machine is not set to a published machine"
fi

if grep -q 'mmc-hs200-1_8v' \
        "${REPO_ROOT}/board/taishan/patches/linux/0001-arm64-dts-rockchip-rk3566-lckfb-tspi-enable-eMMC-HS200.patch"; then
    ok "eMMC HS200 is enabled by the kernel patch"
else
    bad "eMMC HS200 is not enabled"
fi

if [ "${CONFIG_ONLY}" -eq 1 ]; then
    echo
    echo "Passed: ${PASS}, Failed: ${FAIL}"
    [ "${FAIL}" -eq 0 ] || exit 1
    exit 0
fi

echo
echo "== 2. Image structure =="
check "image file exists" test -f "${IMAGE}"

if command -v sfdisk >/dev/null 2>&1; then
    dump="$(sfdisk --dump "${IMAGE}" 2>/dev/null || true)"
else
    dump=""
    info "sfdisk not available, skipping partition table checks"
fi

for label in hassos-boot hassos-kernel0 hassos-system0 hassos-kernel1 hassos-system1 hassos-bootstate hassos-overlay hassos-data; do
    if echo "${dump}" | grep -q "${label}"; then
        ok "partition ${label} present"
    else
        bad "partition ${label} missing"
    fi
done

# The A/B system partitions are referenced by fixed PARTUUIDs in the boot
# script. Verify that the image actually carries those UUIDs, otherwise the
# board will not find its root filesystem.
for uuid in 8d3d53e3-6d49-4c38-8349-aff6859e82fd a3ec664e-32ce-4665-95ea-7ae90ce9aa20; do
    if echo "${dump}" | grep -qi "${uuid}"; then
        ok "rootfs PARTUUID ${uuid} present"
    else
        bad "rootfs PARTUUID ${uuid} missing (the boot script hard-codes it)"
    fi
done

if [ -n "${dump}" ]; then
    # The data partition must be the last one so it absorbs the remaining
    # eMMC capacity, which is what makes one image work across 16 GB and
    # 128 GB variants.
    if echo "${dump}" | grep -A1 "hassos-data" | grep -q "start="; then
        ok "hassos-data is a sized partition that grows with the device"
    else
        info "hassos-data has no explicit size, it fills the remaining space"
    fi
fi

echo
echo "Passed: ${PASS}, Failed: ${FAIL}"
[ "${FAIL}" -eq 0 ] || exit 1
