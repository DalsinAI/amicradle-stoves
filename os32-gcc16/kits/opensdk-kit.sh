#!/bin/sh
# The Open SDK (DalsinAI/gfopensdk) as a stove kit, so a stove's compiler
# finds every Open library's headers with no -I and links -lopensdk:
#
#   include/   the SDK's Include/ (proto, inline, clib, pragmas, libraries/ ...)
#              -> the stove's prefix/m68k-amigaos/include
#   lib/       libopensdk.a (a stub for every call in SFD/, Lib/build.sh with
#              this stove) and m68k-soft-m68040.specs
#              -> prefix/m68k-amigaos/lib
#   the rest   FD/, SFD/, Include_I/, Docs/, Examples/, Templates/, the
#              readme, licence and manifest -> prefix/m68k-amigaos/share/GFOpenSDK/
#
# OpenNDK (the OS's own headers) is not in it: the stove has it already
# (prefix/m68k-amigaos/ndk-include).
#
#   opensdk-kit.sh SDK STOVE VERSION OUT_DIR
#
# SDK      a gfopensdk checkout, at the commit to take (its offline check must pass)
# STOVE    the os32-gcc16 stove whose gcc builds libopensdk.a
# VERSION  the kit's version: the SDK's (0.3), or below it for a pre-release
#          (0.2.91: 0.3's first pre-release), as os32_stove.py --kit reads
#          NAME-VERSION from the folder
# Makes OUT_DIR/GFOpenSDK-VERSION.tar.gz (sorted, owner 0, mtime of the
# SDK commit) and prints its SHA-256. MIT, Copyright (c) 2026 AmiCradle Team.
set -eu
[ $# -eq 4 ] || { sed -n '2,24p' "$0"; exit 2; }
SDK=$(realpath "$1"); STOVE=$(realpath "$2"); VER=$3; OUT=$(realpath -m "$4")
case $VER in ''|*[!0-9.]*) echo "bad version: $VER"; exit 2 ;; esac
[ -f "$SDK/manifest.json" ] && [ -d "$SDK/Include" ] || { echo "$SDK is not a gfopensdk checkout"; exit 1; }
[ -x "$STOVE/prefix/bin/m68k-amigaos-gcc" ] || { echo "$STOVE has no m68k-amigaos-gcc"; exit 1; }
python3 "$SDK/tools/gather.py" --offline-check
commit=$(git -C "$SDK" rev-parse HEAD)
dirty=$(git -C "$SDK" status --porcelain --untracked-files=no)
[ -z "$dirty" ] || { echo "$SDK has changes not committed"; exit 1; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
# libopensdk.a, from a clean copy of the commit (Lib/build.sh writes Lib/build/)
git -C "$SDK" archive --format=tar --prefix=src/ HEAD | tar xf - -C "$tmp"
PREFIX="$STOVE/prefix/bin/m68k-amigaos-" sh "$tmp/src/Lib/build.sh" >/dev/null
K=$tmp/GFOpenSDK-$VER
mkdir -p "$K/include" "$K/lib"
cp -a "$tmp/src/Include/." "$K/include/"
cp "$tmp/src/Lib/build/m68k-amigaos/libopensdk.a" "$tmp/src/Lib/m68k-soft-m68040.specs" "$K/lib/"
for d in FD SFD Include_I Docs Examples Templates; do
    [ -d "$tmp/src/$d" ] && cp -a "$tmp/src/$d" "$K/$d"
done
cp "$tmp/src/README.md" "$tmp/src/LICENSE" "$tmp/src/CONTRIBUTORS.md" "$tmp/src/manifest.json" "$K/"
cat > "$K/KIT.txt" <<EOF
GFOpenSDK $VER as a stove kit: DalsinAI/gfopensdk $commit.
Headers in the stove's include folder, libopensdk.a and the soft-float
specs in its lib folder, the rest here. Made by amicradle-stoves
os32-gcc16/kits/opensdk-kit.sh with $("$STOVE/prefix/bin/m68k-amigaos-gcc" --version | head -1).
EOF
( cd "$K" && find . -type f ! -name SHA256SUMS | LC_ALL=C sort | sed 's|^\./||' | xargs sha256sum > SHA256SUMS )
when=$(git -C "$SDK" log -1 --format=%ct)
mkdir -p "$OUT"
tar --sort=name --owner=0 --group=0 --numeric-owner --mtime="@$when" -C "$tmp" -cf - "GFOpenSDK-$VER" | gzip -n -9 > "$OUT/GFOpenSDK-$VER.tar.gz"
sha256sum "$OUT/GFOpenSDK-$VER.tar.gz"
