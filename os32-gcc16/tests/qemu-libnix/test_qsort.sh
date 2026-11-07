#!/bin/sh
# test_qsort.sh [STOVE]: t20 (../src/t20_qsort.c) on a stove's own libnix qsort and
# bsearch, without an Amiga. For each libnix.a in STOVE/prefix/m68k-amigaos/libnix/lib
# (68000, 68020, -fbaserel and -fbaserel32 builds), qsort.o and bsearch.o are taken out,
# their code (.text; no data, no relocations but ___mulsi3) put in a Linux m68k
# program by loader.h, and run under qemu-m68k -cpu m68040. Then the same for
# ../../libnix/qsort.c (the fix) compiled by the stove's compiler with libnix's own
# flags for each build, beside the stove's bsearch.o.
# Needs m68k-linux-gnu-gcc and qemu-m68k. STOVE defaults to ~/AmiCradle/stoves/os32-gcc16.
# Exit 0 when every run says "t20 OK". A stove whose libnix has the old qsort fails
# (it never returns, or compares outside the array, on libwebp's sorts).
# MIT, Copyright (c) 2026 AmiCradle Team.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
STOVE=$(cd "${1:-$HOME/AmiCradle/stoves/os32-gcc16}" && pwd) || exit 2
P="$STOVE/prefix/bin/m68k-amigaos-"
L="$STOVE/prefix/m68k-amigaos/libnix/lib"
LINUXCC=${LINUXCC:-m68k-linux-gnu-gcc}
QEMU=${QEMU:-qemu-m68k}
for t in "${P}gcc" "${P}ar" "${P}objcopy" "${P}objdump"; do [ -x "$t" ] || { echo "no $t" >&2; exit 2; }; done
command -v "$LINUXCC" >/dev/null && command -v "$QEMU" >/dev/null || { echo "needs $LINUXCC and $QEMU" >&2; exit 2; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
echo "stove: $STOVE ($("${P}gcc" --version | head -n 1))"

# carray OBJ NAME: OBJ's .text as NAME_code[] and its ___mulsi3 relocations as NAME_rel[]
carray() {
    if "${P}objdump" -h "$1" | awk '$2 ~ /^\.(data|bss)$/ && $3 !~ /^0+$/ { bad = 1 } END { exit !bad }'; then
        echo "$1 has data: cannot run it here" >&2; return 1
    fi
    "${P}objcopy" -O binary -j .text "$1" "$W/text.bin" || return 1
    rel=$("${P}objdump" -r "$1" | awk '/^[0-9a-f]+ / { if ($2 != "RELOC32" || $3 != "___mulsi3") { print "bad " $0; exit } printf "0x%s, ", $1 }')
    case $rel in bad*) echo "$1: relocation it cannot run: ${rel#bad }" >&2; return 1 ;; esac
    echo "static const unsigned char $2_code[] __attribute__((aligned(4))) = {"
    od -An -v -tx1 "$W/text.bin" | sed 's/ *\([0-9a-f][0-9a-f]\)/0x\1,/g'
    echo "};"
    echo "static const unsigned long $2_rel[] = { ${rel}0 };"
}

# run LABEL QSORT.O BSEARCH.O
fails=0
run() {
    d="$W/run"; rm -rf "$d"; mkdir -p "$d"
    { echo "#define T_NAME \"$1\""; carray "$2" t_qsort && carray "$3" t_bsearch; } > "$d/code.h" || { echo "FAIL $1: cannot take its code"; fails=$((fails+1)); return; }
    cp "$HERE/loader.h" "$d/"
    if ! "$LINUXCC" -O2 -m68040 -static -I"$d" -DQSORT_UNDER_TEST='"loader.h"' -o "$d/t20" "$HERE/../src/t20_qsort.c" > "$d/cc.log" 2>&1; then
        echo "FAIL $1: build"; cat "$d/cc.log"; fails=$((fails+1)); return
    fi
    timeout 900 "$QEMU" -cpu m68040 "$d/t20" > "$d/out.txt" 2>&1; rc=$?
    sed 's/^/  /' "$d/out.txt"
    if [ $rc = 0 ] && grep -qx 't20 OK' "$d/out.txt"; then echo "PASS $1"; else echo "FAIL $1 (rc=$rc)"; fails=$((fails+1)); fi
}

# libnix's builds and the flags its Makefile.gcc6 gives each (gfopengcc's build adds the -O2 line)
LIBNIX_CFLAGS="-O2 -fomit-frame-pointer -fno-tree-loop-distribute-patterns -fno-builtin -ffast-math -D__libnix__"
for v in .:"" libm020:"-m68020" libb:"-fbaserel" libb/libm020:"-fbaserel -m68020" libb32/libm020:"-fbaserel32 -m68020"; do
    dir=${v%%:*}; flags=${v#*:}
    [ -f "$L/$dir/libnix.a" ] || continue
    o="$W/o/$dir"; mkdir -p "$o"
    (cd "$o" && "${P}ar" x "$L/$dir/libnix.a" qsort.o bsearch.o) || { echo "FAIL $dir: no qsort.o/bsearch.o"; fails=$((fails+1)); continue; }
    run "stove libnix lib/$dir" "$o/qsort.o" "$o/bsearch.o"
    # shellcheck disable=SC2086
    if "${P}gcc" -c $LIBNIX_CFLAGS $flags -o "$o/fixed.o" "$HERE/../../libnix/qsort.c"; then
        run "fixed qsort.c [$flags] lib/$dir" "$o/fixed.o" "$o/bsearch.o"
    else echo "FAIL fixed qsort.c [$flags]: build"; fails=$((fails+1)); fi
done
echo "$fails failing"
[ $fails = 0 ]
