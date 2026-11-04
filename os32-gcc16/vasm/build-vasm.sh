#!/bin/sh
# Builds vasmm68k_mot (vasm, CPU=m68k SYNTAX=mot) from vasm.lock's release into a stove's prefix/bin.
#
#   os32-gcc16/vasm/build-vasm.sh STOVE [TARBALL]
#
# STOVE is the stove folder (its prefix/bin gets vasmm68k_mot); TARBALL the release archive, downloaded
# from vasm.lock's url when not given. The archive must have vasm.lock's SHA-256. The program must say
# vasm.lock's version. The stove's own README.txt gets a note.
#
# vasm's licence: free for non-commercial use, not open source (vasm's own doc/vasm.texi). It is a build
# tool on the Cradle machine only: never put it, or a stove that holds it, in a release of ours.
# This script is MIT, Copyright (c) 2026 AmiCradle Team.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
lock() { sed -n "s/^$1=//p" "$HERE/vasm.lock"; }
STOVE=${1:?usage: build-vasm.sh STOVE [TARBALL]}
[ -d "$STOVE/prefix/bin" ] || { echo "$STOVE has no prefix/bin"; exit 2; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
A=${2:-}
if [ -z "$A" ]; then A=$T/vasm.tar.gz; curl -fsSL -o "$A" "$(lock url)"; fi
got=$(sha256sum "$A" | cut -d' ' -f1)
[ "$got" = "$(lock sha256)" ] || { echo "$A: SHA-256 $got is not vasm $(lock version)'s ($(lock sha256)): refused"; exit 1; }
tar -C "$T" -xzf "$A"
make -C "$T/vasm" CPU=m68k SYNTAX=mot > "$T/make.log" 2>&1 || { tail -n 20 "$T/make.log"; exit 1; }
"$T/vasm/vasmm68k_mot" -v 2>&1 | head -n 1 | grep -Fq "vasm $(lock version)" || { echo "the build does not say vasm $(lock version)"; exit 1; }
install -m 755 "$T/vasm/vasmm68k_mot" "$STOVE/prefix/bin/vasmm68k_mot"
printf '.text\n moveq #0,d0\n rts\n' > "$T/t.s"
"$STOVE/prefix/bin/vasmm68k_mot" -quiet -Fhunk -o "$T/t.o" "$T/t.s"
[ -s "$T/t.o" ] || { echo "vasmm68k_mot made no object"; exit 1; }
if [ -f "$STOVE/README.txt" ] && ! grep -q 'vasmm68k_mot' "$STOVE/README.txt"; then
  printf '\nvasmm68k_mot (prefix/bin): vasm %s from %s (SHA-256 %s), built by\namicradle-stoves os32-gcc16/vasm/build-vasm.sh. vasm is free for non-commercial use, not open\nsource: a build tool here only, never in a release.\n' "$(lock version)" "$(lock url)" "$(lock sha256)" >> "$STOVE/README.txt"
fi
"$STOVE/prefix/bin/vasmm68k_mot" -v 2>&1 | head -n 3
