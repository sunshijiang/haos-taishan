#!/usr/bin/env bash
# Report which build tools are present, one per line.
set -u
for t in gcc g++ make git wget rsync unzip file python3 skopeo patch ccache \
         jq bc bison flex texinfo gawk xz bzip2 pigz file; do
    if command -v "$t" >/dev/null 2>&1; then
        echo "OK   $t"
    else
        echo "MISS $t"
    fi
done
