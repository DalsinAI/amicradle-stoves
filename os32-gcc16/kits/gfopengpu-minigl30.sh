#!/bin/sh
# GFOpenGPU-SDK 0.8.1: the 0.8 kit with minigl.library 30's clean-room
# interface (gfopenrtg main, library/minigl, merged in #221) in place of
# version 29's. The minigl files are replaced wholesale: every 0.8 MiniGL
# header (include/mgl/, libraries/minigl*.h, proto/minigl.h,
# clib/minigl_protos.h) is taken out and gfopenrtg's are put in, and
# libminigl.a and libmgl.a are those library/minigl/build.sh makes from the
# same commit. Nothing of the old headers' text is carried over (see
# gfopenrtg library/minigl/PROVENANCE.md). Everything else is 0.8's, as is.
#
#   gfopengpu-minigl30.sh KIT-0.8.tar.gz GFOPENRTG MINIGL_OUT OUT_DIR
#
# GFOPENRTG   a gfopenrtg checkout at the commit to take (main, ed6b41d or later)
# MINIGL_OUT  library/minigl/build.sh's output from that checkout (libminigl.a, libmgl.a)
# Makes OUT_DIR/GFOpenGPU-SDK-0.8.1.tar.gz (one top folder, sorted, owner
# 0, mtime of the gfopenrtg commit) and prints its SHA-256. The next kit
# tools/make_sdk.py makes (0.9) has the same files from its include/, so
# this is only until then.
# MIT, Copyright (c) 2026 AmiCradle Team.
set -eu
[ $# -eq 4 ] || { sed -n '2,19p' "$0"; exit 2; }
KIT=$(realpath "$1"); RTG=$(realpath "$2"); MGL=$(realpath "$3"); OUT=$(realpath -m "$4")
OLD=GFOpenGPU-SDK-0.8 NEW=GFOpenGPU-SDK-0.8.1
for f in "$RTG/library/minigl/PROVENANCE.md" "$RTG/include/mgl/mgltypes.h" "$MGL/libminigl.a" "$MGL/libmgl.a"; do
    [ -f "$f" ] || { echo "missing $f"; exit 1; }
done
grep -q 'minigl.library 30' "$RTG/library/minigl/README.md" || { echo "$RTG is not minigl.library 30"; exit 1; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
tar xzf "$KIT" -C "$tmp"
[ -d "$tmp/$OLD" ] || { echo "$KIT has no $OLD/"; exit 1; }
mv "$tmp/$OLD" "$tmp/$NEW"
K=$tmp/$NEW
# out, wholesale: every MiniGL interface file 0.8 had
rm -rf "$K/include/mgl"
rm -f "$K"/include/libraries/minigl*.h "$K/include/proto/minigl.h" "$K/include/clib/minigl_protos.h" \
      "$K/include/inline/minigl.h" "$K/include/pragmas/minigl_pragmas.h"
# in: gfopenrtg's MiniGL files
mkdir -p "$K/include/mgl" "$K/include/libraries" "$K/include/proto" "$K/include/clib" "$K/doc"
cp "$RTG"/include/mgl/*.h "$K/include/mgl/"
cp "$RTG"/include/libraries/minigl*.h "$K/include/libraries/"
cp "$RTG/include/proto/minigl.h" "$K/include/proto/"
cp "$RTG/include/clib/minigl_protos.h" "$K/include/clib/"
cp "$MGL/libminigl.a" "$MGL/libmgl.a" "$K/lib/"
cp "$RTG/library/minigl/PROVENANCE.md" "$K/doc/minigl-PROVENANCE.md"
cp "$RTG/library/minigl/README.md" "$K/doc/minigl-README.md"
rtg=$(git -C "$RTG" rev-parse HEAD)
cat >> "$K/README" <<EOF


GFOpenGPU-SDK 0.8.1
-------------------

0.8 with minigl.library 30's interface, rebuilt clean-room on 9 November
2026 (gfopenrtg ${rtg}, library/minigl): include/mgl/,
libraries/minigl.h and minigl_dispatch.h, proto/minigl.h,
clib/minigl_protos.h, lib/libminigl.a and lib/libmgl.a replace 0.8's
(version 29's) entirely. Programs built for minigl.library 29.x or 30.0
headers run on it unchanged; see doc/minigl-README.md and
doc/minigl-PROVENANCE.md.
EOF
( cd "$K" && find . -type f ! -name SHA256SUMS | LC_ALL=C sort | sed 's|^\./||' | xargs sha256sum > SHA256SUMS )
when=$(git -C "$RTG" log -1 --format=%ct)
mkdir -p "$OUT"
tar --sort=name --owner=0 --group=0 --numeric-owner --mtime="@$when" -C "$tmp" -cf - "$NEW" | gzip -n -9 > "$OUT/$NEW.tar.gz"
sha256sum "$OUT/$NEW.tar.gz"
