#!/bin/sh
# Host test for ../gfopengpu-glu.sh: packs a stand-in gfopenrtg and build
# folder (no stove needed) and checks the kit's layout, its SHA256SUMS, that
# two packs are byte-identical, and that it refuses a missing file, a glu
# that is not 9.0.3 and a .pc file naming the build folder.
#   sh os32-gcc16/kits/tests/test-gfopengpu-glu.sh
# MIT, Copyright (c) 2026 AmiCradle Team.
set -u
S=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/gfopengpu-glu.sh
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fails=0 checks=0
ok() { checks=$((checks + 1)); if ! eval "$1"; then echo "FAIL: $2"; fails=$((fails + 1)); fi; }

R=$T/rtg; B=$T/build
mkdir -p "$R/library/modules/glu" "$R/library/modules/glut"
printf '{ "glu": { "version": "9.0.3" } }\n' > "$R/library/modules/glu/UPSTREAM.json"
echo '# GLU' > "$R/library/modules/glu/README.md"; echo '# GLUT' > "$R/library/modules/glut/README.md"
echo 'true' > "$R/library/modules/glut/build.sh"
git -C "$R" init -q && git -C "$R" -c user.name=t -c user.email=t@t add . && \
    git -C "$R" -c user.name=t -c user.email=t@t commit -q -m t --date=@1763300000
mkdir -p "$B/glu/include/GL" "$B/glu/lib/pkgconfig" "$B/glut/include/GL" "$B/glut/lib/pkgconfig"
echo glu > "$B/glu/include/GL/glu.h"; echo GLU > "$B/glu/lib/libGLU.a"; echo sgi > "$B/glu/LICENSE.txt"
printf 'prefix=${pcfiledir}/../..\nLibs: -L${libdir} -lGLU\n' > "$B/glu/lib/pkgconfig/glu.pc"
echo glut > "$B/glut/include/GL/glut.h"; echo fg > "$B/glut/include/GL/freeglut.h"
echo GLUT > "$B/glut/lib/libglut.a"; echo mit > "$B/glut/LICENSE.txt"
printf 'prefix=${pcfiledir}/../..\nLibs: -L${libdir} -lglut\n' > "$B/glut/lib/pkgconfig/glut.pc"

sh "$S" "$R" "$B" "$T/o1" > "$T/log1" 2>&1; rc=$?
ok '[ $rc -eq 0 ]' "pack failed: $(cat "$T/log1")"
K=$T/x/GFOpenGPU-GLU-9.0.3
mkdir -p "$T/x" && tar xzf "$T/o1/GFOpenGPU-GLU-9.0.3.tar.gz" -C "$T/x"
for f in include/GL/glu.h include/GL/glut.h include/GL/freeglut.h lib/libGLU.a lib/libglut.a \
         lib/pkgconfig/glu.pc lib/pkgconfig/glut.pc doc/GLU-LICENSE.txt doc/GLUT-LICENSE.txt \
         doc/GLU-README.md doc/GLUT-README.md KIT.txt SHA256SUMS; do
    ok "[ -f '$K/$f' ]" "kit has no $f"
done
ok '[ "$(ls "$T/x")" = GFOpenGPU-GLU-9.0.3 ]' "kit has more than one top folder"
ok '(cd "$K" && sha256sum -c --quiet SHA256SUMS)' "SHA256SUMS does not match"
ok '[ "$(wc -l < "$K/SHA256SUMS")" -eq 12 ]' "SHA256SUMS lists $(wc -l < "$K/SHA256SUMS") files, want 12"
ok 'grep -q "$(git -C "$R" rev-parse HEAD)" "$K/KIT.txt"' "KIT.txt does not name the commit"
ok 'grep -q "^$(sha256sum "$T/o1/GFOpenGPU-GLU-9.0.3.tar.gz" | cut -c1-64) " "$T/log1"' "SHA-256 not printed"
sleep 1; sh "$S" "$R" "$B" "$T/o2" > /dev/null 2>&1
ok 'cmp -s "$T/o1/GFOpenGPU-GLU-9.0.3.tar.gz" "$T/o2/GFOpenGPU-GLU-9.0.3.tar.gz"' "two packs differ"

# refusals
ok '! sh "$S" "$R" "$B" > /dev/null 2>&1' "two arguments taken"
mv "$B/glu/lib/libGLU.a" "$T/keep"
ok '! sh "$S" "$R" "$B" "$T/o3" > /dev/null 2>&1' "packed with no libGLU.a"
mv "$T/keep" "$B/glu/lib/libGLU.a"
printf 'prefix=%s/glu\n' "$B" > "$B/glu/lib/pkgconfig/glu.pc"
ok '! sh "$S" "$R" "$B" "$T/o4" > /dev/null 2>&1' "packed a glu.pc naming the build folder"
printf 'prefix=${pcfiledir}/../..\n' > "$B/glu/lib/pkgconfig/glu.pc"
printf '{ "glu": { "version": "9.0.2" } }\n' > "$R/library/modules/glu/UPSTREAM.json"
ok '! sh "$S" "$R" "$B" "$T/o5" > /dev/null 2>&1' "packed glu 9.0.2"

[ $fails -eq 0 ] && echo "gfopengpu-glu.sh: all $checks checks passed"
exit $((fails != 0))
