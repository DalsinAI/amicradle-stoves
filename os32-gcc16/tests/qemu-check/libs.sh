#!/bin/sh
G=${G:-$HOME/gcc16}; OPENTLS=${OPENTLS:-$HOME/gfopentls}
G=$G; S=$G/src; H=$G/host; B=$G/build
cd $B/gmp && make -s -j2 MAKEINFO=true -C . all > make.log 2>&1; make -s MAKEINFO=true install > inst.log 2>&1; ls $H/include/gmp.h || exit 1
rm -rf $B/mpfr && mkdir -p $B/mpfr && cd $B/mpfr && $S/mpfr/configure -q --prefix=$H --with-gmp=$H --disable-shared --enable-static > conf.log 2>&1 && make -s -j2 MAKEINFO=true > make.log 2>&1 && make -s MAKEINFO=true install > inst.log 2>&1; ls $H/include/mpfr.h || exit 1
rm -rf $B/mpc && mkdir -p $B/mpc && cd $B/mpc && $S/mpc/configure -q --prefix=$H --with-gmp=$H --with-mpfr=$H --disable-shared --enable-static > conf.log 2>&1 && make -s -j2 MAKEINFO=true > make.log 2>&1 && make -s MAKEINFO=true install > inst.log 2>&1; ls $H/include/mpc.h || exit 1
echo LIBS-OK
