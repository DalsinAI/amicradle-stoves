# linux-glibc-gcc16: the Linux userland compiler stoves

GFOpenAmigaGCC 16.2.0-open9 cross compilers on x86-64 Linux for Linux programs, built by
[gfopengcc](https://github.com/DalsinAI/gfopengcc) (`scripts/build-userland.sh`): stock GCC 16.2.0 and
binutils 2.47 with the fold-mem-offsets fix (GCC 0019) and the open9 identity, C and C++, over a sysroot of
glibc 2.35 and Linux 5.15's headers (Ubuntu 22.04's). A program they build asks for no glibc symbol above
2.35, so it starts on Ubuntu 22.04, Debian 12 and every newer system. They build AmiCradle's native runtimes
(a1200native, ac460native, their tuned builds, acaudiomixer): gfosmotherboards' `ci/build_runtimes.py` and
amicradle's `scripts/deploy/deploy_dev.py` take the stove for the target when it is installed.

| Stove | Target | For | Lock |
| --- | --- | --- | --- |
| linux-x86_64-glibc-gcc16 | x86_64-linux-gnu | daletop, the CI runners, the AMD x86 appliance | [x86_64.lock](x86_64.lock) |
| linux-aarch64-glibc-gcc16 | aarch64-linux-gnu | the CM4 and Pi 5 cards | [aarch64.lock](aarch64.lock) |

```sh
linux-glibc-gcc16/install.sh ARCH ~/AmiCradle/stoves [ARCHIVE]
CC=~/AmiCradle/stoves/linux-x86_64-glibc-gcc16/prefix/bin/x86_64-linux-gnu-gcc ...
```

`install.sh` refuses an archive whose SHA-256 is not the lock's, unpacks it as
`STOVES/linux-ARCH-glibc-gcc16-RELEASE/prefix` (a folder that is there already is only checked), writes
`STOVE.json` and `README.txt`, checks gcc and g++ say the lock's identity, the sysroot is inside the stove,
and a C program with threads and libm asks for nothing above GLIBC_2.35 and runs (natively on x86_64, under
qemu-aarch64 with the sysroot's glibc), and points `STOVES/linux-ARCH-glibc-gcc16` at it (`KEEP_LINK=1`
keeps a link that points elsewhere; a real folder by that name is never touched).

GCC 16's libstdc++ is newer than Ubuntu 22.04's: a C++ program that must start there links it in with
`-static-libstdc++`. The sysroot's glibc is only linked against; a program loads the system's own.

`tests/test_install.sh`: installs made-up releases (wrappers around the host's gcc and aarch64-linux-gnu-gcc,
or a real build named by `USERLAND_X86_64` / `USERLAND_AARCH64`), and checks the refusals and the locks.
