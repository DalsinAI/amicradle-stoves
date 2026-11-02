#!/bin/sh
G=${G:-$HOME/gcc16}; OPENTLS=${OPENTLS:-$HOME/gfopentls}
cd $G/src/qemu && mkdir -p build && cd build && \
../configure --target-list=m68k-linux-user --disable-system --disable-tools --disable-docs --disable-download --disable-werror --prefix=$G/prefix > conf.log 2>&1 && \
make -j2 > make.log 2>&1 && echo QEMU-OK || echo QEMU-FAIL
