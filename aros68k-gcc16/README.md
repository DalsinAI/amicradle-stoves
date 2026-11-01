# aros68k-gcc16: GCC 16.2 for AROS 68k

A modern C and C++ compiler for AROS on the 68k: GCC 16.2.0 with binutils
2.47, built through AROS's own crosstools from AROS
[`c8860e674d`](https://github.com/aros-development-team/AROS/commit/c8860e674d7c5fbab304e2bf201f7a9c81c98629),
whose patches cover m68k-aros up to GCC 16.2. AROS still builds 68k with GCC
6.5 by default; this stove sits beside it and replaces nothing.

**Status: experimental.** First built and qualified 2 October 2026: C, C++20,
threads and the AROS API pass; C++ exceptions do not yet (see Findings).

## What it gives you

- C23 by default, C++20 and later, and a current libstdc++.
- `std::exception_ptr` on the 68000. GCC 6.5's library leaves it out on CPUs
  without lock-free atomics.
- The same AROS headers and libraries as an AROS build, as its sysroot.
- Programs are AROS 68k programs (ELF). They need AROS, not AmigaOS.
- All our builds are for the 68040 only. GCC itself is configured for the
  68000 (as AROS 68k's is), so `build.sh`'s `specs` file makes `-mcpu=68040`
  the default (17 Oct 2026): a build that names no CPU, or asks for the 68000,
  gets the 68040. A 68040 build is soft float (the `m68040/softfp` libraries)
  unless it asks for `-m68881` or `-mhard-float`, so one program runs on a full
  68040 and on an LC/EC040. GCC alone makes `-m68040` hard float; the specs
  file adds `-msoft-float`, and a stove without that file needs
  `-m68040 -msoft-float` on the command line. Making the 68040 the compiler's
  own default would take a rebuild with `--with-cpu=68040`.

## Build it

```sh
./build.sh                 # about an hour on 8 cores
./build.sh --verify-only   # just fetch-check the sources
```

`sources.lock` pins every input by SHA-256. GCC and binutils are also checked
against their GNU signatures with `gpgv`. One quirk handled for you: AROS
fetches isl as `.tar.bz2` while isl publishes `.tar.xz`, so the script repacks
it.

The result is in `work/`:

| Folder | What |
| --- | --- |
| `work/toolchain/` | the compiler: `m68k-aros-gcc`, `m68k-aros-g++` and friends |
| `work/sdk-build/` | the AROS crosstools build; it holds the compiler's sysroot, so keep it |
| `work/stove.json` | the identity: versions, AROS ref, build time |

Check which compiler you have with `m68k-aros-gcc --version`: this stove says
16.2.0.

## Use it

```sh
work/toolchain/m68k-aros-gcc -O2 -o hello hello.c
work/toolchain/m68k-aros-g++ -O2 -std=gnu++20 -o app app.cpp
work/toolchain/m68k-aros-g++ -O2 -o threads threads.cpp -lpthread -latomic
```

**Every C++ program on AROS 68k needs** `-Wl,-u,__pthread_Init_Func -lpthread -latomic`
(both this stove and AROS's GCC 6.5; see Findings). Without it, the first
`std::string`, `new`, static-local guard or `shared_ptr` can hang for ever.

Old Amiga sources may need `-std=gnu11 -fpermissive`. Since GCC 14, implicit
function declarations, implicit int and pointer/integer mixing are errors;
since GCC 15, C23 is the default, so `bool` is a keyword and `int f()` means
no arguments. Code that bends the aliasing rules is common, so
`-fno-strict-aliasing` is worth having for old code.

**Address 0 is memory** (chip RAM, with exec's pointer at 4), so the stove
makes `-fno-delete-null-pointer-checks` the default (8 Oct 2026). Without it,
GCC at `-O2` turns a read through a pointer it has proved null into `TRAP #7`,
and drops null checks that follow a read. `build.sh` writes a `specs` file
beside libgcc (`toolchain/lib/gcc/m68k-aros/16.2.0/specs`) that adds the flag
for C and C++, and stops if a read of address 0 still compiles to the trap.
A build can still pass `-fdelete-null-pointer-checks`. A stove built before
17 Oct 2026 gets the same defaults by putting that file there by hand:

```
*self_spec:
%{mcpu=68000:%<mcpu=68000 -mcpu=68040} %{mcpu=68000|mcpu=68040:%{!m68881:%{!mhard-float:-msoft-float}}}

*cc1:
+ -fno-delete-null-pointer-checks

*cc1plus:
+ -fno-delete-null-pointer-checks
```

## Tests

`tests/` holds seven programs, built for the 68040 with soft float (`-m68040 -msoft-float`) by this stove
and, for comparison, by AROS's GCC 6.5:

| Test | Covers |
| --- | --- |
| t1 | the C library: formatting, strings, sorting, memory |
| t2 | 64-bit integers and floating point (soft float) |
| t3 | C++: classes, containers, lambdas; C++17 and C++20 when the compiler has them |
| t4 | exceptions: deep unwinding, destructors, rethrow, `exception_ptr` |
| t5 | threads: pthreads, `std::thread`, mutex, condition variable, atomics |
| t6 | the AROS API: exec and dos calls through the library stubs |
| t7 | a benchmark whose checksums must match a host build's |

```sh
G6=/path/to/aros/toolchain/m68k-aros- tests/build-tests.sh   # G6 is optional
```

Then copy `tests/bin/` and `tests/run-tests` to `DH1:GCC16/` on an AROS 68k
machine and `Execute DH1:GCC16/run-tests`. Results land in
`DH1:GCC16/results.txt`.

## Results

First qualification, 2 October 2026, on an AmiCradle A1200 with the AC090
running AROS 68k (Instance-21). Raw output in `tests/results/2026-10-02/`.

| Test | GCC 16.2 | GCC 6.5 |
| --- | --- | --- |
| t1 C library | 11/11 | 11/11 |
| t2 64-bit integers, floating point | 12/12 | 12/12 |
| t3 C++ library | 15/15 (C++20, with `std::format`) | 7/7 (C++14; 8 newer checks skipped) |
| t4 exceptions | **spins** | **spins** |
| t5 threads | 4/4 | 4/4 |
| t6 AROS API (exec, dos) | 12/12 | 12/12 |
| t7 benchmark | checksums match the host's | checksums match the host's |

t3 and t5 are linked as in the note under *Use it*. The benchmark's times are
the same for both compilers within the 20 ms timer's resolution (about 0.8 s,
most of it soft-float).

## Findings

- **C++ hangs at its first lock unless pthread is forced in early.** The C++
  library takes its locks through pthread. When only libstdc++ pulls the
  pthread objects in, `collect-aros` leaves pthread's `ADD2INIT` entry
  (`__aros_set_INIT___pthread_Init_Func`) out of the init set: `nm` shows it
  at address 0, type `r`. pthread's semaphores stay zeroed and the first
  `ObtainSemaphore` waits for ever (the task waits on `SIGF_SINGLE`). A program
  that calls `pthread_create` itself is fine. `-Wl,-u,__pthread_Init_Func`
  puts the entry back (type `d`). The same holds for GCC 6.5, so it is AROS's
  link, not the compiler. Evidence: `narrowing-*.txt`, `src/narrow/`.
- **C++ exceptions do not work yet, under either compiler.** A throw spins
  between the program and one ROM routine; the unwinder's frame registration
  looks the likely suspect (the same init-set story). Under investigation.
- **Linking the whole of `libpthread.a` fails:** `pthread_attr_setstacksize`
  is defined twice (in `pthread.o` and its own object). An AROS packaging bug.
- **Program size:** C++20 with `std::format` is large (14 MB for t3 against
  1.8 MB under GCC 6.5's C++14); C programs are within a few per cent.
- GCC 6.5 (AROS's default) has no `std::exception_ptr` on the 68000, and
  `std::atomic` needs `-latomic`. GCC 16.2 has both.
