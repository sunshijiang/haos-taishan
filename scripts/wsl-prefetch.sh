#!/usr/bin/env bash
# Put the sources that the upstream download sites no longer serve into the
# download cache. Runs inside WSL2.
#
# Some upstream projects drop older releases from their own site. zlib for
# example no longer has 1.3.2 on www.zlib.net, and Buildroot's wget helper
# has no timeout, so the build sits there forever instead of moving on to
# the next mirror.
set -uo pipefail

DL="${BR2_DL_DIR:-/cache/dl}"

fetch() {
    local name="$1" subdir="$2" file="$3" url="$4"

    local dir="${DL}/${subdir}"
    mkdir -p "${dir}"

    if [ -s "${dir}/${file}" ]; then
        echo "  already there: ${subdir}/${file}"
        return 0
    fi

    echo "  fetching ${subdir}/${file}"
    if curl -fsSL --connect-timeout 15 --max-time 300 -o "${dir}/${file}" "${url}"; then
        echo "    ok, $(du -h "${dir}/${file}" | cut -f1)"
    else
        echo "    FAILED: ${url}" >&2
        rm -f "${dir}/${file}"
        return 1
    fi
}

echo "Pre-fetching sources that the upstream sites no longer serve"

# zlib 1.3.2 was removed from www.zlib.net, it is only on the Buildroot
# mirror now.
fetch zlib libzlib zlib-1.3.2.tar.xz \
      https://sources.buildroot.net/libzlib/zlib-1.3.2.tar.xz

echo "Done"
