#!/bin/sh
G=${G:-$HOME/gcc16}; OPENTLS=${OPENTLS:-$HOME/gfopentls}
G=$G; H=$G/host; P=$G/prefix; B=$G/build
export PATH=$P/bin:$H/bin:$PATH
echo "== libs $(date +%T)"; $(dirname "$0")/libs.sh || { echo LIBS-FAIL; exit 1; }
echo "== gcc-configure $(date +%T)"; rm -rf $B/gcc; mkdir -p $B/gcc && cd $B/gcc && CFLAGS=-O0 CXXFLAGS=-O0 $G/gcc-16.2.0/configure --target=m68k-elf --prefix=$P --enable-languages=c --disable-multilib --without-headers --with-newlib --disable-nls --disable-shared --disable-threads --disable-libssp --disable-libquadmath --disable-libgomp --disable-libatomic --disable-decimal-float --disable-bootstrap --with-gmp=$H --with-mpfr=$H --with-mpc=$H MAKEINFO=true > conf.log 2>&1 || { echo CONF-FAIL; exit 1; }
echo "== all-gcc $(date +%T)"; make -j2 all-gcc MAKEINFO=true > make-gcc.log 2>&1 && make install-gcc MAKEINFO=true > inst-gcc.log 2>&1 || { echo GCC-FAIL; exit 1; }
echo "== libgcc $(date +%T)"; make -j2 all-target-libgcc MAKEINFO=true > make-libgcc.log 2>&1 && make install-target-libgcc MAKEINFO=true > inst-libgcc.log 2>&1 || { echo LIBGCC-FAIL; exit 1; }
echo "== done $(date +%T)"
