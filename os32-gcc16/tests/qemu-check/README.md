# qemu-check: GCC 16 m68k code checked without an Amiga

How the 11 October 2026 checks were run in a cloud workspace with no Amiga and
no NDK. A C test is compiled with a GCC 16 m68k compiler, linked as an ELF
program with a tiny C library (`crt0.S`, `mini.c`: Linux system calls for
write and exit), run under `qemu-m68k` user mode and its output compared with
the same program built on a PC.

Two compilers can be checked this way:
- **upstream GCC 16.2.0** built for `m68k-elf` (`gcc.sh`);
- **bebbo's amiga16.2** (the os32-gcc16 stove's compiler) built for
  `m68k-amigaos`, `cc1` only (`bebbo.sh`). Its assembly is assembled by the
  m68k-elf binutils with `--register-prefix-optional`, its symbols carry
  AmigaOS's leading underscore, so `crt0_us.S` calls `_main` and libgcc is
  copied with `m68k-elf-objcopy --prefix-symbols=_` (`libgcc020_us.a`,
  `libgcc060_us.a`).

Limits: no AmigaOS, no libnix, no hunk files; the stove's own multilib
libraries (libgcc, libnix built for each CPU) are not what runs here. Code
that uses floating point must be built with `-m68881` against the hard-float
libgcc, or the soft-float calls return in the wrong registers (the
`u2d`/`d2u` lines and two torture tests differ for that reason only).

## Sources (all reachable from GitHub)

| What | Where |
| --- | --- |
| GCC 16.2.0 | `github.com/gcc-mirror/gcc`, tag `releases/gcc-16.2.0` |
| bebbo's amiga16.2 | `github.com/AmigaPorts/gcc`, branch `amiga16.2` (`1d4ca5d4b`, 11 Oct; `26e100b31`, 7 Oct) |
| binutils (m68k-elf) | `github.com/riscv-collab/riscv-binutils-gdb` (2.38, all targets) |
| GMP 6.2.1, MPFR 3.1.3 | `github.com/alisw/GMP`, `github.com/alisw/MPFR` (touch `aclocal.m4`, then `configure` and the `Makefile.in`s, so make does not rerun automake) |
| MPC 1.1.0 | `github.com/BrianGladman/mpc` at `69ad1bc`, then `autoreconf -i` |
| flex 2.6.4 | GitHub release of `westes/flex` |
| QEMU 9.2.4 | `github.com/qemu/qemu`; `subprojects/keycodemapdb/README` created empty and `subdir_done()` at the top of `tests/fp/meson.build`, as only `m68k-linux-user` is built |

Run QEMU with `-cpu m68040`; `-cpu m68060` also works and traps the 64-bit
multiplies and divides a real 060 lacks; `-cpu any` is a ColdFire. Link at
`-Ttext-segment=0x10000`: the m68k-elf default of `0x80000000` does not run.

## Scripts

All take `G` (the work folder, default `~/gcc16`) and `OPENTLS` (an
gfopentls checkout).

- `libs.sh`, `gcc.sh`: GMP, MPFR, MPC, then upstream GCC (C, libgcc) for
  m68k-elf, built `-O0` (about 7 minutes on 2 cores).
- `bebbo.sh`: bebbo's `cc1` for m68k-amigaos (about 7 minutes).
- `qemu.sh`: `qemu-m68k`.
- `build_any.sh WHICH CPU TAG REF SRC...`: build and run a test, compare with
  `REF`. `WHICH` is `upstream` or a bebbo `gcc` build folder.
- `run_bebbo.sh`, `run_torture.sh`: GCC's execute torture tests, one file at a
  time (`LIST` is a file of test paths).
