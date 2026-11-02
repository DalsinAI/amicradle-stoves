#!/bin/sh
G=${G:-$HOME/gcc16}; OPENTLS=${OPENTLS:-$HOME/gfopentls}
# build_any.sh WHICH CPU TAG REF SRC...: WHICH = upstream | <bebbo build dir>; compile SRC, link with the mini libc, run under qemu-m68k, diff with REF
P=$G/prefix/bin; H=$(cd "$(dirname "$0")" && pwd); Q=$G/src/qemu/build/qemu-m68k
T=$OPENTLS
WHICH=$1; CPU=$2; TAG=$3; REF=$4; shift 4
O=$H/any-$TAG; rm -rf $O; mkdir -p $O
FLAGS="$CPU -O2 -fno-tree-loop-distribute-patterns -fno-delete-null-pointer-checks -fomit-frame-pointer ${EXTRA:-}"
INC="-I$T/include -I$T/library"
if [ "$WHICH" = upstream ]; then
  for f in "$@"; do $P/m68k-elf-gcc $FLAGS -I$H/include $INC -c $f -o $O/$(basename $f .c).o || echo "COMPILE-FAIL $f"; done
  $P/m68k-elf-gcc $CPU -O2 -fno-builtin -fno-tree-loop-distribute-patterns -c $H/mini.c -o $O/mini.o0
  $P/m68k-elf-gcc $CPU -c $H/crt0.S -o $O/crt0.o0
  LIBGCC=$($P/m68k-elf-gcc -print-libgcc-file-name); case "$CPU" in *68060*) LIBGCC=$G/build/gcc/m68k-elf/libgcc060/libgcc.a ;; esac
  $P/m68k-elf-ld -Ttext-segment=0x10000 -e _start -o $O/prog $O/crt0.o0 $O/*.o $O/mini.o0 ${LIBEXTRA:-} $LIBGCC || exit 1
else
  BB=$WHICH; CC="$BB/xgcc -B$BB/ -nostdinc -I$H/include-bebbo -I$H/include -I$BB/include"
  AS="$P/m68k-elf-as --register-prefix-optional $CPU"
  for f in "$@"; do $CC $FLAGS $INC -S $f -o $O/t.s && $AS $O/t.s -o $O/$(basename $f .c).o || echo "COMPILE-FAIL $f"; done
  $CC $CPU -O2 -fno-builtin -fno-tree-loop-distribute-patterns -S $H/mini.c -o $O/mini.s && $AS $O/mini.s -o $O/mini.o0
  $AS $H/crt0_us.S -o $O/crt0.o0
  LIBGCC=$H/libgcc020_us.a; case "$CPU" in *68060*) LIBGCC=$H/libgcc060_us.a ;; esac
  $P/m68k-elf-ld -Ttext-segment=0x10000 -e _start -o $O/prog $O/crt0.o0 $O/*.o $O/mini.o0 ${LIBEXTRA:-} $LIBGCC || exit 1
fi
QCPU=m68040; case "$CPU" in *68060*) [ -n "$ON060" ] && QCPU=m68060 ;; esac
timeout 600 $Q -cpu $QCPU $O/prog > $H/$TAG.txt 2>&1; rc=$?
diff $REF $H/$TAG.txt > $H/$TAG.diff && echo "$TAG: SAME (exit $rc)" || { echo "$TAG: DIFFERS (exit $rc)"; cut -c1-90 $H/$TAG.diff | head -20; }
