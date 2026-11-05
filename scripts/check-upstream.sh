#!/usr/bin/env bash
#
# check-upstream.sh - Report whether upstream home-assistant/operating-system
#                     has moved since the pinned revision in this repository.
#
# Exit codes:
#   0  upstream is up to date (or ahead of the pin -> "update available")
#   1  an error occurred
#
# Output (machine readable):
#   UPSTREAM_PINNED_SHA=<sha>
#   UPSTREAM_LATEST_SHA=<sha>
#   UPSTREAM_UPDATE_AVAILABLE=true|false
#
set -euo pipefail

UPSTREAM_REPO="${UPSTREAM_REPO:-https://github.com/home-assistant/operating-system.git}"
UPSTREAM_REF="${UPSTREAM_REF:-dev}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PIN_FILE="${REPO_ROOT}/upstream.pin"

log() { echo "[check-upstream] $*" >&2; }

[ -f "${PIN_FILE}" ] || { log "Missing ${PIN_FILE}"; exit 1; }

# The pin file may contain either a bare SHA or "<sha> <date>" style content.
PINNED_SHA="$(grep -oE '^[0-9a-f]{40}' "${PIN_FILE}" | head -1)"
[ -n "${PINNED_SHA}" ] || { log "Cannot parse a SHA from ${PIN_FILE}"; exit 1; }

log "Pinned SHA: ${PINNED_SHA}"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

git init -q "${TMP}/repo"
git -C "${TMP}/repo" remote add origin "${UPSTREAM_REPO}"

log "Fetching ${UPSTREAM_REF} from upstream (this can take a moment)"
git -C "${TMP}/repo" fetch --depth 1 --quiet origin "${UPSTREAM_REF}" || {
    log "Failed to fetch from upstream"
    exit 1
}

LATEST_SHA="$(git -C "${TMP}/repo" rev-parse "FETCH_HEAD^{commit}")"
log "Latest SHA: ${LATEST_SHA}"

if [ "${LATEST_SHA}" = "${PINNED_SHA}" ]; then
    UPDATE_AVAILABLE=false
else
    UPDATE_AVAILABLE=true
fi

echo "UPSTREAM_PINNED_SHA=${PINNED_SHA}"
echo "UPSTREAM_LATEST_SHA=${LATEST_SHA}"
echo "UPSTREAM_UPDATE_AVAILABLE=${UPDATE_AVAILABLE}"

exit 0
