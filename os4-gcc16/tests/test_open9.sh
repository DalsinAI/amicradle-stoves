#!/bin/sh
# os4-gcc16 on the open9 code base (Dale 18 Nov 2026): build.sh gives the compiler gfopengcc's release
# identity, applies gfopengcc's fold-mem-offsets fix (patches/gcc/0019, the same bytes) after the AmigaOS
# patch, writes the release into stove.json and checks the built compiler says it. No build, no network.
# MIT, Copyright (c) 2026 AmiCradle Team.
set -u
HERE=$(cd "$(dirname "$0")/.." && pwd); B=$HERE/build.sh; P=$HERE/patches/gcc-16.2.0-0019-fold-mem-offsets.patch
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails+1)); }
sh -n "$B" && ok "build.sh parses" || bad "build.sh does not parse"
grep -qx 'RELEASE="GFOpenAmigaGCC 16.2.0-open9"' "$B" && ok "release identity GFOpenAmigaGCC 16.2.0-open9" || bad "no RELEASE line"
grep -qF -- "--with-pkgversion='\$RELEASE'" "$B" && ok "GCC is configured with it" || bad "pkgversion is not \$RELEASE"
# gfopengcc's patches/gcc/0019 (open8 and later), byte for byte
want=$(sed -n 's/^# 0019 sha256: //p' "$0")
[ "$(sha256sum "$P" | cut -d' ' -f1)" = "$want" ] && ok "0019 is gfopengcc's ($want)" || bad "0019 is not gfopengcc's patch"
[ "$(grep '^+++ ' "$P" | sed 's/^+++ b\///')" = gcc/fold-mem-offsets.cc ] && ok "0019 only changes gcc/fold-mem-offsets.cc" || bad "0019 changes more"
a=$(grep -n 'gcc-\$GCC_VERSION-amigaos.patch"' "$B" | head -1 | cut -d: -f1)
f=$(grep -n 'gcc-\$GCC_VERSION-0019-fold-mem-offsets.patch"' "$B" | head -1 | cut -d: -f1)
[ -n "$a" ] && [ -n "$f" ] && [ "$f" -gt "$a" ] && ok "0019 goes on after the AmigaOS patch" || bad "0019 is not applied after the AmigaOS patch"
grep -qF '"release": release' "$B" && ok "stove.json carries the release" || bad "stove.json has no release"
grep -qF 'grep -qF "($RELEASE)"' "$B" && ok "the smoke tests check the compiler says it" || bad "no identity check"
[ $fails -eq 0 ] && echo "test_open9: all passed" || { echo "test_open9: $fails failed"; exit 1; }
# 0019 sha256: e46dfd19b24c728078f2060b1b6fd63a36c22343e2d04c23557a0bf65f22d81b
