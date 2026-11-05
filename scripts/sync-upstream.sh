#!/usr/bin/env bash
#
# sync-upstream.sh - Fetch home-assistant/operating-system and overlay the
#                     Taishan Pi board customisation.
#
# The upstream tree is NOT vendored into this repository. Instead the build
# works on a checkout of upstream plus the board overlay that lives here.
# Keeping the overlay separate means an upstream sync is a plain
# "git fetch + git checkout" and never a merge conflict.
#
# Usage:
#   sync-upstream.sh [--ref <git-ref>] [--dest <dir>] [--no-patch]
#
# Environment:
#   UPSTREAM_REPO   upstream git URL      (default: https://github.com/home-assistant/operating-system.git)
#   UPSTREAM_REF    upstream branch/tag    (default: dev)
#
set -euo pipefail

UPSTREAM_REPO="${UPSTREAM_REPO:-https://github.com/home-assistant/operating-system.git}"
UPSTREAM_REF="${UPSTREAM_REF:-dev}"

DEST=""
DO_PATCH=1

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

while [ $# -gt 0 ]; do
    case "$1" in
        --ref)     UPSTREAM_REF="$2"; shift 2 ;;
        --dest)    DEST="$2"; shift 2 ;;
        --no-patch) DO_PATCH=0; shift ;;
        -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

DEST="${DEST:-${REPO_ROOT}/upstream}"

log() { echo "[sync-upstream] $*"; }
fail() { echo "[sync-upstream] ERROR: $*" >&2; exit 1; }

log "Repository : ${UPSTREAM_REPO}"
log "Reference  : ${UPSTREAM_REF}"
log "Destination: ${DEST}"

# ---------------------------------------------------------------------------
# 1. Fetch upstream
# ---------------------------------------------------------------------------
if [ -d "${DEST}/.git" ]; then
    log "Reusing existing checkout in ${DEST}"
    git -C "${DEST}" fetch --tags --prune origin
else
    mkdir -p "$(dirname "${DEST}")"
    if git -C "${DEST}" rev-parse --verify "${UPSTREAM_REF}^{commit}" >/dev/null 2>&1; then
        : # ref is a local commit, handled below
    fi
    # A branch or tag name can be cloned directly; a raw commit SHA cannot,
    # because "git clone --branch" only understands refs. Detect a SHA and
    # fall back to a plain clone plus fetch.
    if printf '%s' "${UPSTREAM_REF}" | grep -qE '^[0-9a-f]{40}$'; then
        log "Cloning upstream (shallow, no branch) into ${DEST}"
        git clone --depth 1 --no-checkout "${UPSTREAM_REPO}" "${DEST}"
        git -C "${DEST}" fetch --depth 1 origin "${UPSTREAM_REF}" || \
            git -C "${DEST}" fetch --depth 50 origin
    else
        log "Cloning upstream (shallow) into ${DEST}"
        git clone --depth 1 --branch "${UPSTREAM_REF}" "${UPSTREAM_REPO}" "${DEST}"
    fi
fi

# Resolve the requested ref to a concrete commit so builds are reproducible.
# Try each candidate in turn and keep only the first result that is a
# 40-character SHA. git rev-parse echoes the argument back for an unknown
# ref, so a plain "||" chain would poison the variable.
resolve_sha() {
    local candidate
    for candidate in "origin/${UPSTREAM_REF}^{commit}" \
                     "${UPSTREAM_REF}^{commit}" \
                     "FETCH_HEAD^{commit}" \
                     "HEAD^{commit}"; do
        candidate="$(git -C "${DEST}" rev-parse --verify "${candidate}" 2>/dev/null | head -1)"
        if printf '%s' "${candidate}" | grep -qE '^[0-9a-f]{40}$'; then
            printf '%s' "${candidate}"
            return 0
        fi
    done
    return 1
}

UPSTREAM_SHA="$(resolve_sha)" || fail "Cannot resolve upstream ref '${UPSTREAM_REF}' to a commit"

log "Upstream commit: ${UPSTREAM_SHA}"

# Materialise the tree at that commit.
#
# Note: upstream contains a couple of file names with a literal "\x2d"
# sequence (e.g. .../etc-NetworkManager-system\x2dconnections.mount). Git for
# Windows refuses to check those out because the backslash is an invalid
# path character. Disable the NTFS path protection so the checkout works on
# Windows as well; on Linux the setting is a no-op.
git -C "${DEST}" config core.protectNTFS false || true
git -C "${DEST}" config core.protectHFS false || true
git -C "${DEST}" -c advice.detachedHead=false checkout --force "${UPSTREAM_SHA}" || {
    log "Checkout reported errors, retrying with NTFS path protection disabled"
    git -C "${DEST}" -c core.protectNTFS=false -c core.protectHFS=false \
        -c advice.detachedHead=false checkout --force "${UPSTREAM_SHA}" || true
}

# ---------------------------------------------------------------------------
# 2. Buildroot submodule (the actual build system)
# ---------------------------------------------------------------------------
log "Initialising the buildroot submodule"
git -C "${DEST}" submodule update --init --recursive --depth 1

BUILDROOT_SHA="$(git -C "${DEST}" rev-parse HEAD)"
log "Upstream tree ready (${BUILDROOT_SHA})"

# ---------------------------------------------------------------------------
# 3. Overlay the Taishan Pi board customisation
# ---------------------------------------------------------------------------
if [ "${DO_PATCH}" -eq 1 ]; then
    log "Applying the Taishan Pi overlay"

    BOARD_SRC="${REPO_ROOT}/board/taishan"
    BOARD_DST="${DEST}/buildroot-external/board/taishan"

    [ -d "${BOARD_SRC}" ] || fail "Board overlay missing: ${BOARD_SRC}"

    mkdir -p "${BOARD_DST}"
    # Replace the board directory wholesale so removed files do not linger.
    rm -rf "${BOARD_DST}"
    cp -a "${BOARD_SRC}" "${BOARD_DST}"

    # The defconfig lives in buildroot-external/configs/<name>_defconfig
    cp -a "${REPO_ROOT}/configs/taishan_defconfig" \
          "${DEST}/buildroot-external/configs/taishan_defconfig"

    # Register the board in the CI matrix so the upstream test workflow can
    # pick it up as well.
    if [ -f "${DEST}/.github/workflows/matrix.json" ]; then
        log "Registering the taishan board in .github/workflows/matrix.json"
        python3 - "${DEST}/.github/workflows/matrix.json" <<'PY'
import json, sys

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
    print("[sync-upstream] matrix.json updated")
else:
    print("[sync-upstream] matrix.json already contains taishan")
PY
    fi

    log "Overlay applied"
fi

# ---------------------------------------------------------------------------
# 4. Report
# ---------------------------------------------------------------------------
cat <<EOF

[sync-upstream] Done.

  Upstream repo : ${UPSTREAM_REPO}
  Upstream ref  : ${UPSTREAM_REF}
  Upstream SHA  : ${UPSTREAM_SHA}
  Tree          : ${DEST}

Next:
  docker run --rm --privileged -v "${DEST}:/build" haos-builder \\
      bash -c 'make taishan_defconfig && make'

EOF
