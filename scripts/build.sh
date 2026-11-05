#!/usr/bin/env bash
#
# build.sh - Build the HAOS image for the LCKFB Taishan Pi.
#
# This is the local counterpart of the CI build. It runs the same upstream
# builder container, so the result is the same image.
#
# Usage:
#   ./scripts/build.sh [--ref <git-ref>] [--target taishan] [--jobs N]
#
# On Windows the script runs under Git Bash and drives Docker Desktop. The
# container works as root there, because Windows has no POSIX user id that
# could be handed over, and the paths are converted to the native form that
# Docker Desktop expects.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPSTREAM_REF=""
TARGET="taishan"
JOBS=""

log() { echo "[build] $*"; }
fail() { echo "[build] ERROR: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
    case "$1" in
        --ref)    UPSTREAM_REF="$2"; shift 2 ;;
        --target) TARGET="$2"; shift 2 ;;
        --jobs)   JOBS="$2"; shift 2 ;;
        -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
        *) fail "Unknown argument: $1" ;;
    esac
done

command -v docker >/dev/null 2>&1 || fail "docker is required but was not found in PATH"

# ---------------------------------------------------------------------
# 1. Detect the platform and prepare the paths
# ---------------------------------------------------------------------
IS_WINDOWS=0
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) IS_WINDOWS=1 ;;
esac

if [ "${IS_WINDOWS}" -eq 1 ]; then
    # Windows has no POSIX user id. The container runs as root and the
    # files it writes belong to the user that owns the mounted directory.
    BUILDER_UID=0
    BUILDER_GID=0
    # Docker Desktop wants native paths. MSYS_NO_PATHCONV keeps the shell
    # from rewriting them a second time.
    to_docker_path() { cygpath -m "$1"; }
    export MSYS_NO_PATHCONV=1
    log "Running on Windows, the container builds as root"
else
    BUILDER_UID="$(id -u)"
    BUILDER_GID="$(id -g)"
    to_docker_path() { printf '%s' "$1"; }
fi

UPSTREAM_DIR="${REPO_ROOT}/upstream"
CACHE_DIR="${REPO_ROOT}/.cache"
OUTPUT_DIR="${REPO_ROOT}/.output"

mkdir -p "${CACHE_DIR}/dl" "${CACHE_DIR}/cc" "${OUTPUT_DIR}"

# ---------------------------------------------------------------------
# 2. Prepare the upstream tree with the Taishan Pi overlay
# ---------------------------------------------------------------------
if [ -n "${UPSTREAM_REF}" ]; then
    bash "${REPO_ROOT}/scripts/sync-upstream.sh" --ref "${UPSTREAM_REF}" --dest "${UPSTREAM_DIR}"
else
    # Use the pinned revision so a local build matches the CI build.
    PINNED="$(grep -oE '^[0-9a-f]{40}' "${REPO_ROOT}/upstream.pin" | head -1)"
    [ -n "${PINNED}" ] || fail "Cannot determine the pinned upstream revision"
    bash "${REPO_ROOT}/scripts/sync-upstream.sh" --ref "${PINNED}" --dest "${UPSTREAM_DIR}"
fi

# ---------------------------------------------------------------------
# 3. Build the builder image
# ---------------------------------------------------------------------
log "Building the HAOS builder container image"
docker build -t haos-taishan-builder:local "${UPSTREAM_DIR}"

# ---------------------------------------------------------------------
# 4. Configure and build
# ---------------------------------------------------------------------
run_builder() {
    docker run --rm --privileged \
        -e BUILDER_UID="${BUILDER_UID}" \
        -e BUILDER_GID="${BUILDER_GID}" \
        -v "$(to_docker_path "${UPSTREAM_DIR}"):/build" \
        -v "$(to_docker_path "${CACHE_DIR}"):/cache" \
        -v "$(to_docker_path "${OUTPUT_DIR}"):/build/output" \
        haos-taishan-builder:local "$@"
}

MAKE_ARGS=""
[ -n "${JOBS}" ] && MAKE_ARGS="BR2_JLEVEL=${JOBS}"

log "Generating the build configuration (${TARGET}_defconfig)"
run_builder make "${TARGET}_defconfig"

log "Building the image, this takes a while"
# The output goes to a file, the console only gets the last lines. A full
# build prints tens of thousands of lines and that is more than a terminal
# wants to scroll through.
run_builder bash -c "make ${MAKE_ARGS} > /build/output/build.log 2>&1; rc=\$?; \
                     tail -n 60 /build/output/build.log; \
                     exit \${rc}"

log "Verifying the kernel configuration"
run_builder bash -c 'make BR2_CHECK_DOTCONFIG_OPTS="--github-format --strip-path-prefix=/build/" linux-check-dotconfig'

# ---------------------------------------------------------------------
# 5. Report
# ---------------------------------------------------------------------
log "Artifacts:"
ls -lh "${OUTPUT_DIR}/images/" 2>/dev/null || ls -lh "${UPSTREAM_DIR}/output/images/" 2>/dev/null || true

cat <<EOF

[build] Done.

  Image  : ${OUTPUT_DIR}/images/haos_${TARGET}-*.img.xz
  RAUC   : ${OUTPUT_DIR}/images/haos_${TARGET}-*.raucb

  Write the image to a TF card with:
    xz -dc haos_${TARGET}-*.img.xz | sudo dd of=/dev/sdX bs=4M conv=fsync status=progress

  The full build log is in ${OUTPUT_DIR}/build.log

EOF
