#!/bin/sh
# amiganeverball's release build (build.sh), with the inputs its README gathers by hand:
#   - Neverball 1.6.0 at build.sh's pinned commit, cloned beside the clone (../neverball-source, kept between
#     rebuilds; put back to the pin, unpatched, every time, so build.sh applies its patches to clean source);
#   - the official data-1.6.0.pk3: NEVERBALL_DATA_PK3, else $HOME/.cache/neverball/data-1.6.0.pk3 (build.sh checks
#     its SHA-256);
#   - GFOpenGPU's SDK and the compiler from the stove (opengpu-sdk.sh; build.sh's STOVE is the prefix).
# The package (build/neverball-release/package/Neverball) goes into $OUT.
# MIT, Copyright (c) 2026 AmiCradle Team.
set -eu
PIN=$(sed -n 's/^PIN=//p' build.sh)
[ -n "$PIN" ] || { echo "neverball.sh: build.sh names no PIN" >&2; exit 2; }
DATA=${NEVERBALL_DATA_PK3:-$HOME/.cache/neverball/data-1.6.0.pk3}
[ -f "$DATA" ] || { echo "neverball.sh: no $DATA (the official Neverball 1.6.0 data; or set NEVERBALL_DATA_PK3)" >&2; exit 2; }
SRC=$(cd .. && pwd)/neverball-source
[ -d "$SRC/.git" ] || git clone -q https://github.com/Neverball/neverball.git "$SRC"
git -C "$SRC" cat-file -e "$PIN^{commit}" 2>/dev/null || git -C "$SRC" fetch -q origin
git -C "$SRC" -c advice.detachedHead=false checkout -q -f --detach "$PIN"
git -C "$SRC" clean -qfdx
rm -f "$(git -C "$SRC" rev-parse --absolute-git-dir)/openup-patches-applied"
P=$STOVE; [ -x "$STOVE/prefix/bin/m68k-amigaos-gcc" ] && P=$STOVE/prefix
NEVERBALL_DATA_PK3=$DATA STOVE=$P sh "$REBUILD/recipes/opengpu-sdk.sh" sh build.sh "$SRC"
cp -R build/neverball-release/package/Neverball "$OUT/"
echo "neverball.sh: build/neverball-release/package/Neverball copied into $OUT"
