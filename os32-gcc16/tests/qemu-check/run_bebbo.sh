#!/bin/sh
G=${G:-$HOME/gcc16}; OPENTLS=${OPENTLS:-$HOME/gfopentls}
# run_bebbo.sh BB CPUFLAG SRC OUTTXT: compile one C file with bebbo's cc1 (m68k-amigaos), link as ELF, run under qemu
P=$G/prefix/bin; H=$(cd "$(dirname "$0")" && pwd); Q=$G/src/qemu/build/qemu-m68k
BB=$1; CPU=$2; SRC=$3; OUT=$4; W=$(mktemp -d)
CC="$BB/xgcc -B$BB/ -nostdinc -I$H/include-bebbo -I$H/include -I$BB/include"
FLAGS="${OPT:--O2} -fomit-frame-pointer -fno-tree-loop-distribute-patterns -fno-delete-null-pointer-checks -w"
LIBGCC=$H/libgcc020_us.a; case "$CPU" in *68060*) LIBGCC=$H/libgcc060_us.a ;; esac
$CC $CPU -O2 -fno-builtin -fno-tree-loop-distribute-patterns -S $H/mini.c -o $W/mini.s && $P/m68k-elf-as --register-prefix-optional $CPU $W/mini.s -o $W/mini.o
$P/m68k-elf-as --register-prefix-optional $CPU $H/crt0_us.S -o $W/crt0.o
r=NOCOMP
if timeout 60 $CC $CPU $FLAGS -S $SRC -o $W/t.s 2>/dev/null && $P/m68k-elf-as --register-prefix-optional $CPU $W/t.s -o $W/t.o 2>/dev/null; then
  r=NOLINK
  if $P/m68k-elf-ld -Ttext-segment=0x10000 -e _start -o $W/t $W/crt0.o $W/t.o $W/mini.o $LIBGCC 2>/dev/null; then
    if timeout 20 $Q -cpu m68040 $W/t > $W/out.txt 2>&1; then r=PASS; else r=FAIL; fi
    [ -n "$OUT" ] && cp $W/out.txt $OUT
  fi
fi
echo $r; rm -rf $W
