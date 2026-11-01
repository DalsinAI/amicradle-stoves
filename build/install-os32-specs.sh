#!/bin/sh
# Copyright (c) 2026 AmiCradle Team. MIT licence.
# install-os32-specs.sh [--check-only] STOVE
# Gives an AmigaOS 3.x stove (os32-gcc16 or os32, bebbo's m68k-amigaos-gcc) the
# 68040 soft-float link as its default: the stove's full specs (gcc -dumpspecs)
# with only *link_cpu changed, written to prefix/lib/gcc/m68k-amigaos/<ver>/specs.
# Stock, *link_cpu adds "-fl libm881" for -mcpu=6804*, so -m68040 alone
# compiles soft float but links libnix's FPU libm (strtod, atof, ldexp return
# in fp0; the rest runs FPU instructions). Fixed, -m68040 alone links libm020
# (maths through the mathieee libraries) and only -m68881, -mhard-float or a
# 68060 adds libm881. The new *link_cpu is the one in m68k-soft-m68040.specs.
# Then it checks: -m68040 alone links libm020 and not libm881; with -m68881,
# libm881. --check-only only checks.
# A stove under ~/AmiCradle/stoves is in use: set LIVE_OK=1 to write there.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
CHECK_ONLY=0
[ "${1:-}" = "--check-only" ] && { CHECK_ONLY=1; shift; }
[ $# -eq 1 ] || { echo "usage: $0 [--check-only] STOVE" >&2; exit 2; }
STOVE=$(cd "$1" && pwd)
GCC="$STOVE/prefix/bin/m68k-amigaos-gcc"
[ -x "$GCC" ] || { echo "no $GCC" >&2; exit 2; }
SPECS="$(dirname "$("$GCC" -print-libgcc-file-name)")/specs"
NEW=$(sed -n '/^\*link_cpu:$/{n;p;q}' "$HERE/m68k-soft-m68040.specs")
[ -n "$NEW" ] || { echo "no *link_cpu in $HERE/m68k-soft-m68040.specs" >&2; exit 2; }

if [ $CHECK_ONLY = 0 ]; then
    case "$STOVE/" in
        "$HOME/AmiCradle/stoves/"*) [ "${LIVE_OK:-0}" = 1 ] || { echo "$STOVE is a live stove: set LIVE_OK=1 to write its specs" >&2; exit 3; } ;;
    esac
    TMP="$SPECS.new"
    "$GCC" -dumpspecs | awk -v new="$NEW" '
        skip { skip = 0; print new; done = 1; next }
        /^\*link_cpu:$/ { print; skip = 1; next }
        { print }
        END { if (!done) exit 1 }' > "$TMP" || { rm -f "$TMP"; echo "no *link_cpu in the stove's specs" >&2; exit 4; }
    [ -f "$SPECS" ] && cp "$SPECS" "$SPECS.before-$(date -u +%Y%m%dT%H%M%SZ)"
    mv "$TMP" "$SPECS"
    echo "wrote $SPECS"
fi

# The check: a program that uses strtod and printf("%f"), linked with a map.
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
printf '#include <stdio.h>\n#include <stdlib.h>\nint main(int c, char **v) { printf("%%f\\n", strtod(c > 1 ? v[1] : "2.5", 0)); return 0; }\n' > "$W/t.c"
"$GCC" -noixemul -m68040 -O2 -o "$W/soft" "$W/t.c" -Wl,-Map,"$W/soft.map" -lm
"$GCC" -noixemul -m68040 -m68881 -O2 -o "$W/hard" "$W/t.c" -Wl,-Map,"$W/hard.map" -lm
bad=0
grep -q 'libm020' "$W/soft.map" || { echo "FAIL: -m68040 does not link libm020"; bad=1; }
if grep -q 'libm881' "$W/soft.map"; then echo "FAIL: -m68040 alone links libm881 (the stock *link_cpu)"; bad=1; fi
grep -q 'libm881' "$W/hard.map" || { echo "FAIL: -m68040 -m68881 does not link libm881"; bad=1; }
[ $bad = 0 ] && echo "ok: -m68040 links libm020 (soft float), -m68040 -m68881 links libm881"
exit $bad
