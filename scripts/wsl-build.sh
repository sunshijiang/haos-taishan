#!/usr/bin/env bash
#
# wsl-build.sh - Build the HAOS image for the LCKFB Taishan Pi inside WSL2.
#
# No Docker needed. The build runs the Buildroot cross compilation directly
# on the WSL2 userland.
#
# The tree is built inside the WSL2 filesystem and not on the Windows
# drive, for two reasons:
#
#   * The Windows filesystem is reached through a translation layer that is
#     several times slower, and a Buildroot build does a lot of small file
#     operations.
#   * Two files in the upstream tree have a literal "\x2d" in their name,
#     which NTFS cannot represent. On ext4 they are present.
#
# The finished image is copied back to the Windows drive at the end.
#
# Run this inside WSL2:
#     bash scripts/wsl-build.sh
#
# Options:
#     --ref <git-ref>   build against a different upstream revision
#     --jobs N          packages compiled in parallel, 0 means one per core
#     --keep-going      do not stop when a package fails
#
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-}"
BUILD_ROOT="${BUILD_ROOT:-$HOME/haos-taishan-build}"
UPSTREAM_REPO="${UPSTREAM_REPO:-https://github.com/home-assistant/operating-system.git}"
UPSTREAM_REF=""
JOBS="0"
KEEP_GOING=""

log() { echo "[wsl-build] $*"; }
fail() { echo "[wsl-build] ERROR: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
    case "$1" in
        --ref)       UPSTREAM_REF="$2"; shift 2 ;;
        --jobs)      JOBS="$2"; shift 2 ;;
        --keep-going) KEEP_GOING="1"; shift ;;
        -h|--help)   sed -n '2,22p' "$0"; exit 0 ;;
        *) fail "Unknown argument: $1" ;;
    esac
done

# ---------------------------------------------------------------------
# 1. Where is the repository?
# ---------------------------------------------------------------------
# The script can be started from the Windows path, WSL2 reports that as
# /mnt/e/..., or it can be started from a path that is already inside the
# WSL2 filesystem.
if [ -z "${REPO_ROOT}" ]; then
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    REPO_ROOT="$(cd "${script_dir}/.." && pwd)"
fi

case "${REPO_ROOT}" in
    /mnt/*) WIN_ROOT="${REPO_ROOT}" ;;
    *)      fail "Run this from inside WSL2, the repository is at ${REPO_ROOT}" ;;
esac

# The output goes back to the Windows drive so it can be picked up there.
OUT_DIR="${WIN_ROOT}/output"
mkdir -p "${OUT_DIR}"
mkdir -p "${BUILD_ROOT}"

log "Repository : ${WIN_ROOT}"
log "Build root : ${BUILD_ROOT}"
log "Output     : ${OUT_DIR}"

# ---------------------------------------------------------------------
# 2. Check the tools
# ---------------------------------------------------------------------
missing=0
for tool in gcc g++ make git wget rsync unzip file python3 skopeo patch; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
        echo "  MISSING: ${tool}" >&2
        missing=1
    fi
done
[ "${missing}" -eq 0 ] || fail "Run 'bash scripts/wsl-setup.sh' first"

# ---------------------------------------------------------------------
# 2b. A usable PATH
# ---------------------------------------------------------------------
# WSL adds the Windows PATH to the Linux one. Those entries carry spaces
# and backslashes, and Buildroot refuses to work with such a PATH:
#
#   Your PATH contains spaces, TABs, and/or newline (\n) characters.
#
# Keep the entries that look like plain Linux paths and drop the rest.
clean_path() {
    local old_ifs="${IFS}"
    local entry
    local -a kept=()
    IFS=':'
    for entry in ${PATH}; do
        case "${entry}" in
            ""|*\\*|*" "*|*"	"*) continue ;;
            [A-Za-z]:*) continue ;;
            *) kept+=("${entry}") ;;
        esac
    done
    IFS="${old_ifs}"
    local result=""
    for entry in ${kept[@]+"${kept[@]}"}; do
        if [ -n "${result}" ]; then
            result="${result}:${entry}"
        else
            result="${entry}"
        fi
    done
    printf '%s' "${result}"
}

NEW_PATH="$(clean_path)"
if [ "${NEW_PATH}" != "${PATH}" ]; then
    PATH="${NEW_PATH}"
    export PATH
    log "Cleaned the PATH, it had Windows entries with spaces in them"
fi

# ---------------------------------------------------------------------
# 2c. The cache directory
# ---------------------------------------------------------------------
# The defconfig points the download and the compiler cache at /cache, which
# is where the upstream builder container mounts them. Create the same
# directory here so the configuration does not have to change.
if [ ! -d /cache ] || [ ! -w /cache ]; then
    fail "/cache is missing or not writable. Run 'bash scripts/wsl-run.sh' from
       Windows, it prepares the directory."
fi
mkdir -p /cache/dl /cache/cc 2>/dev/null || true

# ---------------------------------------------------------------------
# 3. Prepare the upstream tree with the Taishan Pi overlay
# ---------------------------------------------------------------------
UPSTREAM_DIR="${BUILD_ROOT}/upstream"
OVERLAY_DIR="${BUILD_ROOT}/overlay"

if [ -z "${UPSTREAM_REF}" ]; then
    PINNED="$(grep -oE '^[0-9a-f]{40}' "${WIN_ROOT}/upstream.pin" | head -1)"
    [ -n "${PINNED}" ] || fail "Cannot read the pinned revision from upstream.pin"
    UPSTREAM_REF="${PINNED}"
fi

log "Upstream revision: ${UPSTREAM_REF}"

if [ ! -d "${UPSTREAM_DIR}/.git" ]; then
    log "Cloning upstream (a few minutes)"
    git clone --filter=blob:none "${UPSTREAM_REPO}" "${UPSTREAM_DIR}"
fi
git -C "${UPSTREAM_DIR}" fetch --tags --prune origin
git -C "${UPSTREAM_DIR}" -c advice.detachedHead=false checkout --force "${UPSTREAM_REF}"

log "Initialising the buildroot submodule"
git -C "${UPSTREAM_DIR}" submodule update --init --recursive --depth 1

# Overlay the board customisation.
log "Applying the Taishan Pi overlay"
rm -rf "${OVERLAY_DIR}/buildroot-external/board/taishan"
mkdir -p "${OVERLAY_DIR}/buildroot-external/board" "${OVERLAY_DIR}/buildroot-external/configs"
cp -a "${WIN_ROOT}/board/taishan" "${OVERLAY_DIR}/buildroot-external/board/taishan"
cp -a "${WIN_ROOT}/configs/taishan_defconfig" "${OVERLAY_DIR}/buildroot-external/configs/taishan_defconfig"

# The overlay lives next to the tree, so copy it in.
cp -a "${OVERLAY_DIR}/buildroot-external/board/taishan" "${UPSTREAM_DIR}/buildroot-external/board/taishan"
cp -a "${OVERLAY_DIR}/buildroot-external/configs/taishan_defconfig" \
      "${UPSTREAM_DIR}/buildroot-external/configs/taishan_defconfig"

# Register the board in the CI matrix of the upstream tree, the same thing
# the sync script does.
if [ -f "${UPSTREAM_DIR}/.github/workflows/matrix.json" ]; then
    python3 - "${UPSTREAM_DIR}/.github/workflows/matrix.json" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path) as fh:
    matrix = json.load(fh)

entry = {
    "id": "taishan",
    "defconfig": "taishan",
    "architecture": "aarch64",
    "label": "board/taishan",
}

if not any(item.get("id") == "taishan" for item in matrix):
    matrix.append(entry)
    with open(path, "w") as fh:
        json.dump(matrix, fh, indent=2)
        fh.write("\n")
    print("[wsl-build] matrix.json updated")
PY
fi

# ---------------------------------------------------------------------
# 4. Configure
# ---------------------------------------------------------------------
cd "${UPSTREAM_DIR}"

log "Generating the build configuration"
make taishan_defconfig

# ---------------------------------------------------------------------
# 5. Build
# ---------------------------------------------------------------------
LOG="${BUILD_ROOT}/build.log"

MAKE_ARGS=""
if [ "${JOBS}" != "0" ]; then
    MAKE_ARGS="BR2_JLEVEL=${JOBS}"
fi

log "Building the image, this takes a few hours"
log "The output goes to ${LOG}, tail it with: tail -f ${LOG}"

set +e
if [ -n "${KEEP_GOING}" ]; then
    # Buildroot stops at the first failing package. -k keeps going so that
    # a single broken package does not hide the state of the others.
    make ${MAKE_ARGS} -k > "${LOG}" 2>&1
    rc=$?
else
    make ${MAKE_ARGS} > "${LOG}" 2>&1
    rc=$?
fi
set -e

if [ "${rc}" -ne 0 ]; then
    log "The build failed, the last lines of the log:"
    tail -n 60 "${LOG}" >&2
    fail "See ${LOG} for the full output"
fi

log "Verifying the kernel configuration"
make BR2_CHECK_DOTCONFIG_OPTS="--github-format --strip-path-prefix=/build/" \
     linux-check-dotconfig >> "${LOG}" 2>&1 || fail "The kernel configuration check failed"

# ---------------------------------------------------------------------
# 6. Copy the result to the Windows drive
# ---------------------------------------------------------------------
log "Copying the image to ${OUT_DIR}"
mkdir -p "${OUT_DIR}/images"
cp -a "${UPSTREAM_DIR}/output/images/." "${OUT_DIR}/images/" 2>/dev/null || true
cp -a "${LOG}" "${OUT_DIR}/build.log" 2>/dev/null || true

log "Artifacts:"
ls -lh "${OUT_DIR}/images/" || true

cat <<EOF

[wsl-build] Done.

  Image  : ${OUT_DIR}/images/haos_taishan-*.img.xz
  RAUC   : ${OUT_DIR}/images/haos_taishan-*.raucb

  Write the image to a TF card with:
    xz -dc haos_taishan-*.img.xz | sudo dd of=/dev/sdX bs=4M conv=fsync status=progress

EOF
