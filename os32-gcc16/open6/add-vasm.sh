#!/bin/sh
# add-vasm.sh STOVE TARBALL: vasmm68k_mot and vobjdump (vasm 2.0f, ../vasm/vasm.lock) into
# STOVE/prefix/bin, built from vasm's own release tarball. Game ports assemble with it
# (amigachocolatedoom looks for "$STOVE/prefix/bin/vasmm68k_mot" first).
# vasm is free for non-commercial use, not open source: a build tool on our machines,
# never in a release of ours (and so neither is a stove that holds it).
# MIT, Copyright (c) 2026 AmiCradle Team.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
STOVE=${1:?usage: add-vasm.sh STOVE TARBALL}
A=${2:?usage: add-vasm.sh STOVE TARBALL}
sh "$HERE/../vasm/build-vasm.sh" "$STOVE" "$A" > /dev/null
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
tar -C "$T" -xzf "$A"
make -C "$T/vasm" CPU=m68k SYNTAX=mot vobjdump > "$T/make.log" 2>&1 || { tail -n 20 "$T/make.log"; exit 1; }
install -m 755 "$T/vasm/vobjdump" "$STOVE/prefix/bin/vobjdump"
"$STOVE/prefix/bin/vasmm68k_mot" -v < /dev/null 2>&1 | head -n 1
