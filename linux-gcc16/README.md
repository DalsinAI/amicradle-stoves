# linux-gcc16: the Linux kernel compiler stoves

GFOpenAmigaGCC 16.2.0-open9 cross compilers on x86-64 Linux for Linux kernels, built by
[gfopengcc](https://github.com/DalsinAI/gfopengcc) (`scripts/build-linux.sh`, `docs/linux.md`): stock GCC
16.2.0 and binutils 2.47 with the fold-mem-offsets fix (GCC 0019) and the open9 identity. C and libgcc only,
no C library: they build kernels and other freestanding code, not Linux programs.

| Stove | Target | For | Lock |
| --- | --- | --- | --- |
| linux-aarch64-gcc16 | aarch64-linux-gnu | CM4 and Pi 5 cards (`make ARCH=arm64`) | [aarch64.lock](aarch64.lock) |
| linux-x86_64-gcc16 | x86_64-linux-gnu | the AMD x86 appliance (`make ARCH=x86_64`) | x86_64.lock |
| linux-powerpc-gcc16 | powerpc-linux-gnu (32-bit) | the AC460 (`make ARCH=powerpc`) | powerpc.lock |

```sh
linux-gcc16/install.sh ARCH ~/AmiCradle/stoves [ARCHIVE]
make ARCH=arm64 CROSS_COMPILE=~/AmiCradle/stoves/linux-aarch64-gcc16/prefix/bin/aarch64-linux-gnu- ...
```

`install.sh` refuses an archive whose SHA-256 is not the lock's, unpacks it as
`STOVES/linux-ARCH-gcc16-RELEASE/prefix` (a folder that is there already is only checked), writes
`STOVE.json` and `README.txt`, checks the compiler says the lock's identity and that a freestanding program
for ARCH compiles, links and runs (natively on x86_64, under qemu-aarch64 / qemu-ppc), and points
`STOVES/linux-ARCH-gcc16` at it (`KEEP_LINK=1` keeps a link that points elsewhere; a real folder by that
name is never touched). Each stove is added beside the others, never in place of them.

`tests/test_install.sh`: installs made-up releases (wrappers around the host's own cross compilers, so no
network) for all three, and checks the refusals: another SHA-256, an archive without the compiler, a
compiler that says another release, a folder that is not the stove, a lock for another target, another ARCH.
