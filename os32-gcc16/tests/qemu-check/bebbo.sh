#!/bin/sh
G=${G:-$HOME/gcc16}; OPENTLS=${OPENTLS:-$HOME/gfopentls}
G=$G; H=$G/host; P=$G/prefix; B=$G/build/bebbo
export PATH=$P/bin:$H/bin:$PATH
rm -rf $B; mkdir -p $B && cd $B
echo "== configure $(date +%T)"
CFLAGS=-O0 CXXFLAGS=-O0 $G/src/bebbo-gcc/configure --target=m68k-amigaos --prefix=$G/bprefix --enable-languages=c --disable-multilib --disable-nls --disable-shared --disable-threads --disable-libssp --disable-libquadmath --disable-libgomp --disable-libatomic --disable-decimal-float --disable-bootstrap --disable-plugin --with-gmp=$H --with-mpfr=$H --with-mpc=$H --with-as=$P/bin/m68k-elf-as --with-ld=$P/bin/m68k-elf-ld MAKEINFO=true > conf.log 2>&1 || { echo CONF-FAIL; exit 1; }
echo "== all-gcc $(date +%T)"
make -j2 all-gcc MAKEINFO=true > make.log 2>&1 || { echo GCC-FAIL; exit 1; }
echo "== done $(date +%T)"
