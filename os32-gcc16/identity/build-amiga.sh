#!/bin/sh
# The os32-gcc16 stove's identity, for Cradle's stove_build (STOVE= and OUT= set, target os32-gcc16/identity):
# prints what the stove's compiler and STOVE.json say, fails unless the compiler is the release in
# ../toolchain.lock, then builds and links a small C program with it (no NDK needed) into OUT.
#   STOVE=~/AmiCradle/stoves/os32-gcc16 OUT=/tmp/id sh os32-gcc16/identity/build-amiga.sh
# MIT, Copyright (c) 2026 AmigaChrome Team.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
LOCK="$HERE/../toolchain.lock"
STOVE=${STOVE:?STOVE: the stove folder}
OUT=${OUT:-$HERE/build}
CC="$STOVE/prefix/bin/m68k-amigaos-gcc"
want=$(sed -n 's/^identity=//p' "$LOCK")
release=$(sed -n 's/^release=//p' "$LOCK")
got=$("$CC" --version | head -1)
echo "compiler: $got"
if [ -f "$STOVE/STOVE.json" ]; then
    echo "STOVE.json: $(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); a=d.get("compilerArchive") or {}; print(d.get("release"), a.get("name"), a.get("sha256"))' "$STOVE/STOVE.json")"
fi
case "$got" in
    *"$want"*) echo "identity: $release, as toolchain.lock says" ;;
    *) echo "identity: NOT $release (toolchain.lock wants \"$want\"): this stove needs os32-gcc16/upgrade.sh"; exit 1 ;;
esac
mkdir -p "$OUT"
cat > "$OUT/identity.c" <<'C'
#include <stdio.h>
#include <stdlib.h>
int main(int argc, char **argv)
{
    char *end;
    const char *in = argc > 1 ? argv[1] : " ";
    long v = strtol(in, &end, 10);
    /* open4's libnix leaves end at the input for a number that isn't there (its libnix 0008) */
    printf("os32-gcc16 identity: %ld, %s\n", v, end == in ? "end at the input" : "end moved");
    return 0;
}
C
"$CC" -m68040 -O2 -o "$OUT/identity" "$OUT/identity.c"
echo "$OUT/identity ($(wc -c < "$OUT/identity") bytes) built with $release"
