#!/usr/bin/env bash
#
# build.sh - Build the HAOS image for the LCKFB Taishan Pi.
#
# This is the local counterpart of the CI build. It requires Docker on the
# host, because the HAOS build itself runs inside the upstream builder
# container (debian:trixie + buildroot toolchain + skopeo).
#
# Usage:
#   ./scripts/build.sh [--ref <git-ref>] [--target taishan]
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPSTREAM_REF=""
TARGET="taishan"
UPSTREAM_DIR="${REPO_ROOT}/upstream"

log() { echo "[build] $*"; }
fail() { echo "[build] ERROR: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
    case "$1" in
        --ref)    UPSTREAM_REF="$2"; shift 2 ;;
        --target) TARGET="$2"; shift 2 ;;
        -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
        *) fail "Unknown argument: $1" ;;
    esac
done

command -v docker >/dev/null 2>&1 || fail "docker is required but was not found in PATH"

# ---------------------------------------------------------------------
# 1. Prepare the upstream tree with the Taishan Pi overlay
# ---------------------------------------------------------------------
if [ -n "${UPSTREAM_REF}" ]; then
    "${REPO_ROOT}/scripts/sync-upstream.sh" --ref "${UPSTREAM_REF}" --dest "${UPSTREAM_DIR}"
else
    # Use the pinned revision so local builds match CI builds.
    PINNED="$(grep -oE '^[0-9a-f]{40}' "${REPO_ROOT}/upstream.pin" | head -1)"
    [ -n "${PINNED}" ] || fail "Cannot determine the pinned upstream revision"
    "${REPO_ROOT}/scripts/sync-upstream.sh" --ref "${PINNED}" --dest "${UPSTREAM_DIR}"
fi

# ---------------------------------------------------------------------
# 2. Build the builder image
# ---------------------------------------------------------------------
log "Building the HAOS builder container image"
docker build -t haos-taishan-builder:local "${UPSTREAM_DIR}"

# ---------------------------------------------------------------------
# 3. Configure and build
# ---------------------------------------------------------------------
mkdir -p "${REPO_ROOT}/.cache/dl" "${REPO_ROOT}/.cache/cc" "${REPO_ROOT}/.output"

run_builder() {
    docker run --rm --privileged \
        -e BUILDER_UID="$(id -u)" \
        -e BUILDER_GID="$(id -g)" \
        -v "${UPSTREAM_DIR}:/build" \
        -v "${REPO_ROOT}/.cache:/cache" \
        -v "${REPO_ROOT}/.output:/build/output" \
        haos-taishan-builder:local "$@"
}

log "Generating the build configuration (${TARGET}_defconfig)"
run_builder make "${TARGET}_defconfig"

log "Building the image, this takes a while"
run_builder make

log "Verifying the kernel configuration"
run_builder bash -c 'make BR2_CHECK_DOTCONFIG_OPTS="--github-format --strip-path-prefix=/build/" linux-check-dotconfig'

# ---------------------------------------------------------------------
# 4. Report
# ---------------------------------------------------------------------
log "Artifacts:"
ls -lh "${UPSTREAM_DIR}/output/images/" || true

cat <<EOF

[build] Done.

  Image  : ${UPSTREAM_DIR}/output/images/haos_${TARGET}-*.img.xz
  RAUC   : ${UPSTREAM_DIR}/output/images/haos_${TARGET}-*.raucb

  Write the image to a TF card with:
    xz -dc haos_${TARGET}-*.img.xz | sudo dd of=/dev/sdX bs=4M conv=fsync status=progress

EOF
