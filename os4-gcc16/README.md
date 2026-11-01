# os4-gcc16: GCC 16.2 for AmigaOS 4.1 PowerPC

A modern C and C++ compiler for AmigaOS 4.1 on the PowerPC (`ppc-amigaos`):
GCC 16.2.0 with binutils 2.47, built from the pinned GNU releases and our own
AmigaOS patches, on the machine that uses it. No Docker and no prebuilt
compilers. On a Cradle machine it is the `os4` stove
(`~/AmigaChrome/stoves/os4`), which builds the AC460's guest software.

**Status: experimental.** First written 14 October 2026, and first built on the
Cradle machine the same day with every smoke test passing (see Results).
Run-time tests on an AC460 come next.

## Where the patches come from

The AmigaOS 4 support in GCC and binutils is the adtools project's work:
[sba1/adtools](https://github.com/sba1/adtools) up to GCC 11, carried on by
[AmigaLabs/adtools](https://github.com/AmigaLabs/adtools) to GCC 15.3 and
binutils 2.40. We ported those patches forward to GCC 16.2.0 and binutils 2.47:

| Patch | Ported from | What changed in the port |
| --- | --- | --- |
| `patches/binutils-2.47-amigaos.patch` | AmigaLabs `binutils/2.40` (`063184c1`) | Rebased onto 2.47's bfd, gas and ld. The base-relative relocation sizes now use 2.47's byte counts. The AmigaOS ELF vector no longer leaks its overrides into the FreeBSD and VxWorks vectors. The native-gdb parts are left out: the 2.47 release has no gdb. |
| `patches/gcc-16.2.0-amigaos.patch` | AmigaLabs `gcc/15` (`87ac263c`) | Rebased onto GCC 16's rs6000 back end, C and C++ front ends, driver, libgcc and libstdc++. Four bugs in the GCC 15 patch are fixed, among them `-mbaserel`, which crashed on every data access. |

Both patches carry their regenerated `configure` and `Makefile.in` files, so
building needs no autotools. They are GPL, like the code they patch.
[PORTING.md](PORTING.md) says what each port changed, and the known issues
it carries over.

## What it gives you

- C23 by default, C++20 and later, and a current libstdc++.
- The AmigaOS 4 ABI features of the adtools compiler: interface calls
  (`IDOS->Printf()`), `linearvarargs` for the varargs methods, `-mbaserel`,
  `-mcrt=` to choose the C library, and the `__amigaos4__` predefines.
- Three C libraries, chosen with `-mcrt=`:

| `-mcrt=` | C library | Built from | On the Amiga |
| --- | --- | --- | --- |
| `newlib` (the default) | newlib | Hyperion's SDK | `newlib.library`, which every OS 4.1 has |
| `clib2` | clib2 ([sodero/clib2](https://github.com/sodero/clib2) `1a42c693`); `clib2-ts` is its thread-safe build | source, here | nothing: it links statically |
| `clib4` | clib4 ([AmigaLabs/clib4](https://github.com/AmigaLabs/clib4) `30e487d2`) | source, here | `clib4.library` in `LIBS:`, built here too (`prefix/ppc-amigaos/SDK/clib4/clib4.library`) |

## The SDK

The OS 4.1 API headers (`exec`, `dos`, the interfaces) and newlib's start-up
code come from Hyperion's AmigaOS 4.1 SDK. It is a free download, but it is
not ours to redistribute. `build.sh` downloads it from Hyperion on the machine
that builds the stove, or takes the archive you give it with `--sdk`. It is
never committed and never published with a stove. `build.sh` pins its
SHA-256 (`SDK_SHA256`) and refuses an archive that differs before unpacking
it; `stove.json` records it too.

## Build it

```sh
./build.sh --stove ~/AmigaChrome/stoves/os4 --work "${AMIGACHROME_DEV:-$HOME/AmigaChrome-dev}/stove-work/os4-gcc16"
```

| Option | Default | What |
| --- | --- | --- |
| `--stove DIR` | `WORK/stove` | Where the stove lives. The compiler keeps this path for its SDK, so build it in place. |
| `--work DIR` | `./work` | Sources, build trees and logs (several GB). Keep it off `/tmp` if `/tmp` is RAM. |
| `--sdk FILE` | download | Hyperion's `SDK_54.25.lha`, if you already have it. |
| `--jobs N` | every CPU | Parallel make jobs. |
| `--until STEP` | `test` | Stop after `sources`, `binutils`, `sdk`, `xgcc`, `clib2`, `clib4`, `gcc` or `test`. |
| `--verify-only` | | Fetch nothing; check the sources and stop. |

The steps:
1. Fetch and check the sources against `sources.lock` (SHA-256), and GCC and
   binutils against their GNU signatures with `gpgv`. clib2 and clib4 are
   fetched at their pinned commits.
2. Build binutils.
3. Unpack the SDK into `prefix/ppc-amigaos/SDK`, as adtools does.
4. Build the compiler (`xgcc`). gmp, mpfr, mpc and isl are built in the tree.
5. Build clib2.
6. Build clib4 and `clib4.library`. If clib4 does not build, the stove carries
   on without it and says so.
7. Build and install the rest of GCC: libgcc, libstdc++, libatomic and libssp,
   for newlib and clib2.
8. Run the smoke tests (`tests/smoke/`).
9. Write `stove.json`.

Each step leaves a stamp, so running `build.sh` again carries on from the step
that failed. Whatever was in the stove folder before a build is moved to
`replaced-<time>/`, never deleted. A failing step names its log and shows its
last lines.

Host needs (Ubuntu): `build-essential bison flex texinfo gawk m4 xz-utils
bzip2 curl git python3 patch lhasa gpgv`.

## Use it

```sh
PATH=~/AmigaChrome/stoves/os4/prefix/bin:$PATH
ppc-amigaos-gcc -O2 -o hello hello.c                    # newlib
ppc-amigaos-gcc -mcrt=clib2 -O2 -o hello hello.c        # runs on a bare OS 4.1
ppc-amigaos-gcc -mcrt=clib2 -mbaserel -O2 -o hello hello.c   # base-relative data
ppc-amigaos-g++ -athread=native -O2 -std=gnu++20 -o app app.cpp
ppc-amigaos-gcc -O2 -nostartfiles -nostdlib -o my.device my_device.c -lgcc
```

C++ programs that use libstdc++ link with `-athread=native` (or
`-athread=single`), as with adtools: it adds the thread functions libstdc++
and libgcc's unwinder call. Without it the link stops at undefined
`__gthread_*` symbols.

Programs link with `-q`, so they keep their relocations: OS 4.1's ELF loader
needs them. Use `-D__USE_INLINE__` for the classic `Printf(...)` call style
instead of `IDOS->Printf(...)`.

Old Amiga sources may need `-std=gnu11 -fpermissive`: since GCC 14, implicit
function declarations, implicit int and pointer/integer mixing are errors, and
since GCC 15, C23 is the default (`bool` is a keyword, `int f()` takes no
arguments).

## Tests

`build.sh` step 8 builds `tests/smoke/` and checks that each result is a
big-endian PowerPC ELF executable that keeps its relocations:

| Test | Covers |
| --- | --- |
| `hello.c` with newlib, clib2, clib4, and clib2 with `-mbaserel` | C, an interface call (`IDOS->Printf`), the C library |
| `hello.cpp` with newlib and clib2 | C++, libstdc++, exceptions |
| `device.c` | a device-style link: no start files, no C library, libgcc's 64-bit division |

Run-time tests on an AmigaChrome AC460 (OS 4.1) come next.

## Results

| Date | Machine | Recipe | Result |
| --- | --- | --- | --- |
| 14 Oct 2026 | The Cradle machine (Ubuntu, x86-64), SDK 54.25 from Hyperion | `cc1452c` | All nine steps. clib2 and clib4 built. Smoke tests: c-newlib, c-clib2, c-clib4, cxx-newlib, cxx-clib2, device and baserel all ok. |
