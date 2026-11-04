#!/bin/sh
# Builds the vasm "oracle" set: host (x86-64 Linux) vasm binaries that gfopenasm's clean-room tests
# compare our assembler's output against. Same release, same check and same build method as
# os32-gcc16/vasm/build-vasm.sh (it reads that folder's vasm.lock), one clean build per CPU/syntax.
#
#   vasm-oracles/build-vasm-oracles.sh [OUT] [TARBALL]
#
# OUT defaults to ~/AmiCradle/stoves/vasm-oracles/<version>; the binaries go in OUT/bin, with
# OUT/README.txt and OUT/SHA256SUMS. TARBALL is the release archive, downloaded from vasm.lock's url
# when not given; it must have vasm.lock's SHA-256. Each binary must say vasm.lock's version and
# assemble a one-line source for its CPU to -Fbin.
#
# vasm's licence: free for non-commercial use, not open source (vasm's own doc/vasm.texi). These are
# test tools on our own machines only: never redistributed, never in a release of ours. Nothing of
# vasm's source goes in this repository or to gfopenasm's authors: only the built programs are used,
# by a separate builder, as black boxes.
# This script is MIT, Copyright (c) 2026 AmiCradle Team.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
LOCK=$HERE/../os32-gcc16/vasm/vasm.lock
lock() { sed -n "s/^$1=//p" "$LOCK"; }
V=$(lock version)
OUT=${1:-$HOME/AmiCradle/stoves/vasm-oracles/$V}
A=${2:-}

# CPU SYNTAX one-line-source (each assembled with -Fbin as the smoke test)
ORACLES='m68k mot nop
m68k std nop
ppc mot nop
ppc std nop
arm std nop
x86 std nop
z80 oldstyle nop
z80 std nop
6502 oldstyle nop
6502 std nop'

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
if [ -z "$A" ]; then A=$T/vasm.tar.gz; curl -fsSL -o "$A" "$(lock url)"; fi
got=$(sha256sum "$A" | cut -d' ' -f1)
[ "$got" = "$(lock sha256)" ] || { echo "$A: SHA-256 $got is not vasm $V's ($(lock sha256)): refused"; exit 1; }
mkdir -p "$OUT/bin"

echo "$ORACLES" | while read -r cpu syn src; do
  b=vasm${cpu}_$syn
  rm -rf "$T/vasm"; tar -C "$T" -xzf "$A"
  make -C "$T/vasm" CPU="$cpu" SYNTAX="$syn" > "$T/make.log" 2>&1 || { echo "$b:"; tail -n 20 "$T/make.log"; exit 1; }
  "$T/vasm/$b" -v 2>&1 | head -n 1 | grep -Fq "vasm $V" || { echo "$b does not say vasm $V"; exit 1; }
  install -m 755 "$T/vasm/$b" "$OUT/bin/$b"
  printf ' %s\n' "$src" > "$T/t.s"
  rm -f "$T/t.bin"
  "$OUT/bin/$b" -quiet -Fbin -o "$T/t.bin" "$T/t.s" || { echo "$b: smoke test failed"; exit 1; }
  [ -s "$T/t.bin" ] || { echo "$b made no output"; exit 1; }
  printf '%-20s ok  (%s ->%s)\n' "$b" "$src" "$(od -An -tx1 "$T/t.bin" | tr -s ' \n' ' ')"
done

(cd "$OUT/bin" && sha256sum vasm*) > "$OUT/SHA256SUMS"

{
  printf 'vasm %s oracles: host (%s) builds for gfopenasm clean-room comparison testing.\n\n' "$V" "$(uname -m) $(uname -s)"
  printf 'Archive: %s\nSHA-256: %s\n' "$(lock url)" "$(lock sha256)"
  printf 'Built:   %s, %s, by amicradle-stoves vasm-oracles/build-vasm-oracles.sh\n\n' "$(date -u +%Y-%m-%d)" "$(cc --version | head -n 1)"
  printf 'Build commands (each from a fresh unpack of the archive, checked by SHA-256 first):\n'
  echo "$ORACLES" | while read -r cpu syn src; do printf '  make -C vasm CPU=%s SYNTAX=%s   -> bin/vasm%s_%s\n' "$cpu" "$syn" "$cpu" "$syn"; done
  printf '\nSmoke test: each binary assembles " nop" with -quiet -Fbin to a non-empty file.\n'
  printf 'SHA256SUMS lists the binaries in bin/.\n\n'
  printf 'Licence: vasm is free for non-commercial use only and is not open source. These\n'
  printf 'binaries are a build/test tool on our own machines: never redistributed, never\n'
  printf 'shipped in our releases. gfopenasm (MIT) is clean-room: its authors use these\n'
  printf 'programs only as black boxes and never read vasm'"'"'s source.\n'
} > "$OUT/README.txt"
echo "$OUT/bin:"; cat "$OUT/SHA256SUMS"
