# os32-gcc16: tests

The os32-gcc16 stove is built by [DalsinAI/gfopengcc](https://github.com/DalsinAI/gfopengcc):
bebbo's amiga-gcc with GCC branch `amiga16.2` (GCC 16.2.0b) and that
repository's patches. The stove on the Team's PC was rebuilt on 9 October 2026
with patches 0001-0009, which fix among others the 68040 FPCR clash (0003),
the memmove direction (0004) and the 64-bit libcall argument pushed from a stack
slot that broke `-m68060`/`-m68040` builds (0008). gfopengcc's
`tests/repro/prove.sh` proves each of those under qemu-m68k.

On 12 October 2026 the stove on the Team's PC was brought up to gfopengcc's
`main` for C++ and threads (its `README.txt` and `patches/` record it):

- `cc1plus` with gcc patch 0010: `-fuse-cxa-atexit` is the default, so a
  `thread_local`'s destructor runs (#12);
- libnix with patches 0004-0006: FPCR back to 0 after the maths libraries open
  (#7), `__cxa_atexit` and `__dso_handle` (#12), and a `setlocale()` that is safe
  from several threads (#11);
- libpthread with aros-stuff 0001-0004: a thread's record never moves (#6),
  `pthread_detach` (#8), a CAS that returns the old value (#9), and a
  `pthread_join` that waits for a signal (#10).

## The compiler it carries: toolchain.lock (1 November 2026)

The stove is placed by hand on the Cradle machine (`~/AmiCradle/stoves/os32-gcc16`; today still `~/AmigaChrome/stoves/os32-gcc16` there), and until now its
compiler release was written only in that stove's own `STOVE.json` (`release`, `compilerArchive`). Dale,
1 November 2026: update it to the latest, GFOpenAmigaGCC 16.2.0-open4 (gfopenrtg's `library/build.sh`
refuses anything else). `toolchain.lock` pins that release here: tag `v16.2.0-open4` (6b6d0ced), the x86-64
toolchain `openamigagcc-16.2.0-open4-x86_64-linux.tar.xz`, SHA-256
`495319a2ffd803278f8827cad70074029c7aa9ecbe05d037e8646ba43ab94ab2` (the release's SHA256SUMS, checked against
the download). The compiler still names itself `OpenAmigaGCC 16.2.0-open4` in `--version`.

- `identity/build-amiga.sh`: for Cradle's `stove_build` (stove os32-gcc16, repo DalsinAI/amicradle-stoves,
  target `os32-gcc16/identity`). Prints the compiler's `--version` and the stove's `STOVE.json`, fails unless
  the compiler is toolchain.lock's release, then builds a small C program. On 1 November 2026 it said
  `OpenAmigaGCC 16.2.0-open3`.
- `upgrade.sh STOVES ARCHIVE`: makes the next stove in `STOVES/.next/os32-gcc16` from the verified archive and
  everything of the live stove but its compiler (see the script's head), and checks it. The live stove is only
  read. `tests/upgrade/test_upgrade.sh ARCHIVE` tests it on a pretend open3 stove.

On the Cradle machine, to move the stove to open4 (about 2 minutes, plus GFOpenNDK's libamiga builds; with the
folders as they are named there today, `~/AmigaChrome`, until the rename moves them to `~/AmiCradle`):

```sh
cd ~/AmigaChrome/stoves
curl -LO https://github.com/DalsinAI/gfopengcc/releases/download/v16.2.0-open4/openamigagcc-16.2.0-open4-x86_64-linux.tar.xz
sh ~/path/to/amicradle-stoves/os32-gcc16/upgrade.sh ~/AmigaChrome/stoves openamigagcc-16.2.0-open4-x86_64-linux.tar.xz
python3 ~/AmigaChrome/scripts/os32_stove.py --reapply-kits --stoves ~/AmigaChrome/stoves/.next --stove os32-gcc16
python3 ~/AmigaChrome/scripts/stove_openndk.py use ~/AmigaChrome/stoves/.next/os32-gcc16
# anything the old prefix had that the new one hasn't (should list nothing that matters):
diff <(cd os32-gcc16/prefix/m68k-amigaos && find include lib | sort) <(cd .next/os32-gcc16/prefix/m68k-amigaos && find include lib | sort) | grep '^<'
mkdir -p archive && mv os32-gcc16 archive/os32-gcc16-before-open4-$(date +%Y%m%dT%H%M%S) && mv .next/os32-gcc16 os32-gcc16
```

Then Cradle's `stove_build` of `os32-gcc16/identity` says `identity: 16.2.0-open4`. To go back: move the
archived folder back in place of `os32-gcc16`.

This folder adds broader qualification tests, which need no NDK:

- `tests/`: nineteen programs (and t3's pieces, t3a-t3h) built with `tests/build-tests.sh`, run on an instance
  with `tests/run-tests` and judged with `tests/check-results.sh`. MIT.
- `tests/qemu-check/`: how upstream GCC 16.2.0 and bebbo's public `amiga16.2`
  were checked on 11 October 2026 without an Amiga, under qemu-m68k. MIT.

## What the 11 October checks showed

- **gfopengcc's fixes are still needed.** Its push64 reproducer is still
  wrong with upstream GCC 16.2.0 and with bebbo's public `amiga16.2` (the
  AmigaPorts mirror, 7 and 11 October) at `-m68060`, and the FPCR clash still
  shows there with LRA. Both fixes are worth offering upstream.
- **With gfopengcc's FPCR change applied, bebbo's public `amiga16.2` passes
  GCC's execute torture suite**, at `-m68020 -m68881 -O2`:

  | Result | Tests |
  | --- | ---: |
  | Pass | 1,496 |
  | Fail | 14 |
  | Couldn't build in the harness | 182 |

  All 14 failures fail identically with upstream GCC there. They need
  `-fwrapv`, trampolines, `-finstrument-functions` or a full C library.
- **BearSSL and GFOpenCrypto agree with a PC at `-m68060`.** Built the way
  GFOpenTLS's CPU=060 build compiles them, both give the PC's output with every
  compiler tried. That code doesn't contain the push64 pattern, which is why
  t8 and t9 alone could not show it.

## The tests

All builds are for the 68040 only, soft float by default (17 October 2026).
`040` is `-m68040` with `-specs=build/m68k-soft-m68040.specs` (soft float,
`libm020`, maths through the mathieee libraries; see the top README for why the
specs file is needed); `040f` is `-m68040 -m68881` (hard float, as the browser
stack builds). `compat/` builds `libos32compat` both ways (soft by default,
hard in `m881/`): its maths parts return floating point values, so a program
must link the one that matches its float ABI. The C++ tests are soft float and
need a soft `libos32compat`: build it with `compat/build.sh DIR` and pass
`COMPAT_DIR=DIR` (an installed stove has only the old hard-float one).

To give the stove the soft-float link as its default, run
`../build/install-os32-specs.sh <stove>` after it is built (see the top README).

The stove's own default CPU is still the 68000: bebbo's GCC is configured
without `--with-cpu`, and a build with no CPU flag gets `-mcpu=68000` and the
68000 libraries. Making the 68040 the default takes a compiler rebuild in
gfopengcc (`--with-cpu=68040`), and a `libm040` multilib if the 68040 is to
have libraries of its own; today `-m68040` uses the `libm020` ones. Until then
every build passes `-m68040`.

| Test | What | Built for |
| --- | --- | --- |
| t1 | C++ exceptions through a static library and through C built with `-fexceptions`; destructors on unwind; rethrow; `exception_ptr` | 040 |
| t2 | `dynamic_cast` and `typeid` across translation units, virtual inheritance, `bad_cast` | 040 |
| t3 | `std::thread`, `mutex`, `condition_variable`, `thread_local`, `call_once`, `async` | 040 |
| t4 | 64-bit `atomic`, `atomic_ref`, `compare_exchange`, `atomic<double>` | 040 |
| t5 | a 3,000-case `switch` (`-mlong-jump-table-offsets`) | 040 |
| t6 | the FPCR clash (as gfopengcc 0003 fixed it) | 040f |
| t7 | 64-bit arithmetic: stack arguments, spills, shifts, multiplies, divides, varargs, structs | 040, 040f |
| t8 | BearSSL as GFOpenTLS compiles it (i15, ctmul32, m15 curves), output equal to `expected/` | 040, 040f |
| t9 | GFOpenCrypto (SHA-2, X25519, Ed25519, ChaCha20-Poly1305, AES, RSA, ECDSA, sntrup761), output equal to `expected/` | 040, 040f |
| t10 | the loop shift and an overlapping backward copy | 040, 040f |
| t11 | exceptions thrown and caught in 8 threads; carried out of `async`, `promise`, `packaged_task` and an `exception_ptr` | 040 |
| t12 | `thread_local` objects with constructors and destructors in 80 threads: destroyed by the time `join()` returns, counts equal | 040 |
| t13 | 50, then 100 threads alive at once (past libpthread's 22- and 94-slot table sizes), each with `thread_local` data | 040 |
| t14 | `shared_mutex` readers and writers; `shared_timed_mutex` `try_lock_for` and `try_lock_shared` | 040 |
| t15 | `jthread`, `stop_token`, `stop_callback`, `condition_variable_any::wait` with a `stop_token` | 040 |
| t16 | `atomic` wait/notify, `atomic_flag` wait, `latch`, `barrier`, `counting_semaphore` | 040 |
| t17 | `condition_variable_any` with `mutex`, `shared_mutex` and a lock of its own; `wait_for` timing out | 040 |
| t18 | `ostringstream`/`istringstream` (ints, hex, doubles) in 8 threads; `cout` from several threads | 040 |
| t19 | 1,150 short threads: one after another, in batches, detached, `async`; `thread_local` destructors | 040 |
| t12c, t13c, t19c | t12, t13 and t19 built with `-fuse-cxa-atexit` (and `src/cxa_dso.c` for `__dso_handle`), so that `thread_local` destructors are registered | 040 |

## What the tests show on AmigaOS (lab of Instance-32, 12 October)

Built with the stove as it is after the 12 October update and run in a lab copy
of Instance-32: **every test passes**. t1-t7, t10-t19, t3a-t3f, t3, t12c, t13c and
t19c return 0, t7 equals `expected/` for the 020 and the 060, and gfopengcc's
`tests/cxx/dtors.cpp` and `tests/libnix/setlocale_threads.c` pass. t18 passed six
runs out of six; before the update it hung the machine. t8 and t9 need an
gfopentls checkout and were not built.

C++ programs built with `-fbaserel32` and threads still hang, and `-fbaserel` C++
programs don't link; both were so before.

## What the tests showed on AmigaOS (lab of Instance-32, 11 October)

With the stove plus gfopengcc PRs #6 (libpthread) and #7 (libnix FPCR),
t1-t11, t14-t17, t3 (20 runs) and t12c/t13c pass, and t7-t9 equal `expected/`
for the 020 and the 060. The live stove fails t3 and t7-060. Still failing
with both fixes, each a problem of its own:

- **t12, t13, t19: no `thread_local` destructor runs.** The stove defaults to
  `-fno-use-cxa-atexit`, and GCC then emits no `__cxa_thread_atexit` call for a
  `thread_local`. Built with `-fuse-cxa-atexit` (t12c, t13c) they pass.
- **t19: `std::thread::detach()` throws** `system_error` ("No such process"):
  libpthread's `pthread_detach` is not implemented and returns ESRCH.
- **t18 ends the Shell running it** soon after 8 threads start formatting
  doubles with `ostringstream`. Still open.

```sh
cd os32-gcc16/tests
STOVE=~/AmiCradle/stoves/os32-gcc16 OPENTLS=~/gfopentls ./build-tests.sh
# copy bin/ and run-tests to the instance, Execute run-tests, copy results/ back
./check-results.sh results
```

`expected/` was made on a PC (x86-64, GCC 13) from the same sources.
