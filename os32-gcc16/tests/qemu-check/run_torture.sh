#!/bin/sh
G=${G:-$HOME/gcc16}; OPENTLS=${OPENTLS:-$HOME/gfopentls}
# run_torture.sh LIST CPUFLAG OUTFILE: compile and run each execute test, record PASS/FAIL/NOLINK/NOCOMP
P=$G/prefix/bin; H=$(cd "$(dirname "$0")" && pwd); Q=${QEMU:-$G/src/qemu/build/qemu-m68k}
LIST=$1; CPU=$2; OUT=$3; W=$(mktemp -d)
FLAGS="${OPT:--O2} -fomit-frame-pointer -fno-tree-loop-distribute-patterns -fno-delete-null-pointer-checks -w"
$P/m68k-elf-gcc $CPU -O2 -fno-builtin -fno-tree-loop-distribute-patterns -c $H/mini.c -o $W/mini.o
$P/m68k-elf-gcc $CPU -c $H/crt0.S -o $W/crt0.o
: > $OUT
while read f; do
  b=$(basename $f .c)
  if ! timeout 60 $P/m68k-elf-gcc $CPU $FLAGS -I$H/include -c $f -o $W/t.o 2>/dev/null; then echo "NOCOMP $b" >> $OUT; continue; fi
  if ! $P/m68k-elf-gcc $CPU -nostdlib -Wl,-Ttext-segment=0x10000 -o $W/t $W/crt0.o $W/t.o $W/mini.o -lgcc 2>/dev/null; then echo "NOLINK $b" >> $OUT; continue; fi
  if timeout 20 $Q -cpu m68040 $W/t > /dev/null 2>&1; then echo "PASS $b" >> $OUT; else echo "FAIL $b" >> $OUT; fi
done < $LIST
rm -rf $W
