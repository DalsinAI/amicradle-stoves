#!/bin/sh
# install-qsort.sh [--check-only] STOVE: puts the fixed qsort (qsort.c here) into each
# libnix.a of an os32-gcc16 stove, compiled by the stove's own compiler with the flags
# libnix's Makefile.gcc6 gives that build (gfopengcc's build adds the -O2 line).
# libnix's own qsort, to GFOpenAmigaGCC 16.2.0-open6, never returns or reads outside
# the array when the comparison function never returns 0 (libwebp's do): see the head
# of qsort.c and ../README.md. The old qsort.o of each library is kept in
# STOVE/libnix-qsort-before-<UTC time>/; put one back with
#   m68k-amigaos-ar r STOVE/prefix/m68k-amigaos/libnix/lib/<build>/libnix.a <kept>/<build>/qsort.o
# Then (and with --check-only, which changes nothing) it checks that every libnix.a's
# qsort.o has the code this qsort.c compiles to, and when m68k-linux-gnu-gcc and
# qemu-m68k are there, runs ../tests/qemu-libnix/test_qsort.sh on the stove.
# A stove under ~/AmiCradle/stoves (or ~/AmigaChrome/stoves) is in use: LIVE_OK=1 to
# write there; a stove being made in its .next/ needs none.
# MIT, Copyright (c) 2026 AmiCradle Team. qsort.c is public domain, as libnix.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
CHECK_ONLY=0
[ "${1:-}" = "--check-only" ] && { CHECK_ONLY=1; shift; }
[ $# -eq 1 ] || { echo "usage: $0 [--check-only] STOVE" >&2; exit 2; }
STOVE=$(cd "$1" && pwd)
P="$STOVE/prefix/bin/m68k-amigaos-"
L="$STOVE/prefix/m68k-amigaos/libnix/lib"
[ -x "${P}gcc" ] || { echo "no ${P}gcc" >&2; exit 2; }
[ -d "$L" ] || { echo "no $L" >&2; exit 2; }
CFLAGS="-O2 -fomit-frame-pointer -fno-tree-loop-distribute-patterns -fno-builtin -ffast-math -D__libnix__"
BUILDS='.:
libm020:-m68020
libb:-fbaserel
libb/libm020:-fbaserel -m68020
libb32/libm020:-fbaserel32 -m68020'
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
cp "$HERE/qsort.c" "$W/qsort.c"

# compile BUILD FLAGS: $W/<build>/qsort.o (compiled in $W, so the object names qsort.c alone)
compile() {
    mkdir -p "$W/$1"
    # shellcheck disable=SC2086
    (cd "$W" && "${P}gcc" -c $CFLAGS $2 -o "$1/qsort.o" qsort.c)
}
code() {   # code OBJ: its .text bytes and relocations, to compare
    "${P}objcopy" -O binary -j .text "$1" "$1.text" && cat "$1.text" && "${P}objdump" -r "$1" | sed -n 's/^\([0-9a-f]* .*\)/\1/p'
}

if [ $CHECK_ONLY = 0 ]; then
    case "$STOVE/" in
        "$HOME/AmiCradle/stoves/.next/"* | "$HOME/AmigaChrome/stoves/.next/"*) ;;
        "$HOME/AmiCradle/stoves/"* | "$HOME/AmigaChrome/stoves/"*) [ "${LIVE_OK:-0}" = 1 ] || { echo "$STOVE is a live stove: set LIVE_OK=1 to change its libnix" >&2; exit 3; } ;;
    esac
    KEEP="$STOVE/libnix-qsort-before-$(date -u +%Y%m%dT%H%M%SZ)"
    echo "$BUILDS" | while IFS=: read -r b flags; do
        [ -f "$L/$b/libnix.a" ] || continue
        compile "$b" "$flags"
        mkdir -p "$KEEP/$b"
        (cd "$KEEP/$b" && "${P}ar" x "$L/$b/libnix.a" qsort.o)
        "${P}ar" rs "$L/$b/libnix.a" "$W/$b/qsort.o"
        echo "libnix lib/$b: qsort.o replaced (the old one is in $KEEP/$b)"
    done
fi

bad=0; n=0
for b in . libm020 libb libb/libm020 libb32/libm020; do
    [ -f "$L/$b/libnix.a" ] || continue
    flags=$(echo "$BUILDS" | sed -n "s|^$b:||p")
    compile "$b" "$flags"
    mkdir -p "$W/have/$b"
    (cd "$W/have/$b" && "${P}ar" x "$L/$b/libnix.a" qsort.o)
    n=$((n+1))
    if [ "$(code "$W/have/$b/qsort.o" | od -An -v -tx1)" = "$(code "$W/$b/qsort.o" | od -An -v -tx1)" ]; then
        echo "ok: libnix lib/$b has the fixed qsort"
    else
        echo "FAIL: libnix lib/$b has another qsort (libnix's own, before 7 Nov 2026?)"; bad=1
    fi
done
[ $n -gt 0 ] || { echo "FAIL: no libnix.a in $L"; exit 1; }
if command -v m68k-linux-gnu-gcc >/dev/null 2>&1 && command -v qemu-m68k >/dev/null 2>&1; then
    if sh "$HERE/../tests/qemu-libnix/test_qsort.sh" "$STOVE" > "$W/qemu.log" 2>&1; then
        echo "ok: tests/qemu-libnix/test_qsort.sh passes on the stove's libnix"
    else
        grep -E '^(FAIL|PASS) ' "$W/qemu.log"; echo "FAIL: tests/qemu-libnix/test_qsort.sh"; bad=1
    fi
else
    echo "(no m68k-linux-gnu-gcc and qemu-m68k: tests/qemu-libnix/test_qsort.sh not run)"
fi
exit $bad
