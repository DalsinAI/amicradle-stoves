#!/bin/sh
# GLU and GLUT for GFOpenGPU's GL as a stove kit, so a GL port includes
# <GL/glu.h> and links -lGLU (or -lglut) with no copy of its own. Both come
# from gfopenrtg, which has built them since 7 Nov 2026 (ae1b62b): SGI's
# libGLU (Mesa's glu 9.0.3, SGI Free B 2.0: matrix helpers, mipmaps,
# quadrics, the tessellator and NURBS) and GLUT (freeglut 3.6.0's interface
# on GLA). The stove's GFOpenGPU-SDK 0.8.1 was packed without them, so
# today the stove has only TinyGL's five calls (tgl/glu.h) and ports write
# their own (4DTris's quadrics, Sea Defender's tessellator, Chromium B.S.U.).
#
#   gfopengpu-glu.sh GFOPENRTG BUILD OUT_DIR
#
# GFOPENRTG  a gfopenrtg checkout at the commit to take
# BUILD      the folder library/modules/glu/build.sh and glut/build.sh made
#            from it with this stove (STOVE16=<stove>/prefix
#            KIT=<stove>/prefix/m68k-amigaos), holding glu/ and glut/
#            (tests/glut/build-amiga.sh makes both)
# Makes OUT_DIR/GFOpenGPU-GLU-9.0.3.tar.gz (one top folder, sorted, owner
# 0, mtime of the gfopenrtg commit) and prints its SHA-256. Its include/
# and lib/ (with lib/pkgconfig/glu.pc and glut.pc) go to the stove's
# prefix/m68k-amigaos as os32_stove.py --kit puts any kit; the notices go
# to share/. MIT, Copyright (c) 2026 AmiCradle Team.
set -eu
[ $# -eq 3 ] || { sed -n '2,22p' "$0"; exit 2; }
RTG=$(realpath "$1"); B=$(realpath "$2"); OUT=$(realpath -m "$3")
NAME=GFOpenGPU-GLU-9.0.3
for f in "$RTG/library/modules/glu/UPSTREAM.json" "$RTG/library/modules/glut/build.sh" \
         "$B/glu/include/GL/glu.h" "$B/glu/lib/libGLU.a" "$B/glu/lib/pkgconfig/glu.pc" "$B/glu/LICENSE.txt" \
         "$B/glut/include/GL/glut.h" "$B/glut/lib/libglut.a" "$B/glut/lib/pkgconfig/glut.pc" "$B/glut/LICENSE.txt"; do
    [ -f "$f" ] || { echo "missing $f"; exit 1; }
done
grep -q '"version": "9.0.3"' "$RTG/library/modules/glu/UPSTREAM.json" || { echo "$RTG's glu is not 9.0.3"; exit 1; }
# the .pc files find the kit from where they are: they must not name a build folder
if grep -q "$B" "$B/glu/lib/pkgconfig/glu.pc" "$B/glut/lib/pkgconfig/glut.pc"; then
    echo "a .pc file names $B"; exit 1
fi
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
K=$tmp/$NAME
mkdir -p "$K/include" "$K/lib/pkgconfig" "$K/doc"
cp -a "$B/glu/include/." "$B/glut/include/." "$K/include/"
cp "$B/glu/lib/libGLU.a" "$B/glut/lib/libglut.a" "$K/lib/"
cp "$B/glu/lib/pkgconfig/glu.pc" "$B/glut/lib/pkgconfig/glut.pc" "$K/lib/pkgconfig/"
cp "$B/glu/LICENSE.txt" "$K/doc/GLU-LICENSE.txt"
cp "$B/glut/LICENSE.txt" "$K/doc/GLUT-LICENSE.txt"
cp "$RTG/library/modules/glu/README.md" "$K/doc/GLU-README.md"
[ -f "$RTG/library/modules/glut/README.md" ] && cp "$RTG/library/modules/glut/README.md" "$K/doc/GLUT-README.md"
rtg=$(git -C "$RTG" rev-parse HEAD)
cat > "$K/KIT.txt" <<EOF
GLU 9.0.3 and GLUT for GFOpenGPU's GL as a stove kit: DalsinAI/gfopenrtg
$rtg, library/modules/glu and glut. include/GL/glu.h, GL/glut.h and
freeglut's headers, lib/libGLU.a, lib/libglut.a and their .pc files go
to the stove; programs use pkg-config glu (or glut), or -lGLU -lGL.
TinyGL's five GLU calls are weak in libGLU.a, so -ltinygl -lGLU links too.
Made by amicradle-stoves os32-gcc16/kits/gfopengpu-glu.sh.
EOF
( cd "$K" && find . -type f ! -name SHA256SUMS | LC_ALL=C sort | sed 's|^\./||' | xargs sha256sum > SHA256SUMS )
when=$(git -C "$RTG" log -1 --format=%ct)
mkdir -p "$OUT"
tar --sort=name --owner=0 --group=0 --numeric-owner --mtime="@$when" -C "$tmp" -cf - "$NAME" | gzip -n -9 > "$OUT/$NAME.tar.gz"
sha256sum "$OUT/$NAME.tar.gz"
