# AmiCradle stoves

Stoves are the compilers AmiCradle's Kitchen cooks Amiga builds with. This
repository holds the recipe for each one: pinned and verified sources, a
build script, an identity file, and the tests that prove it works on the
machine it targets. Built stoves are published as releases.

| Stove | Compiler | Builds programs for | Status |
| --- | --- | --- | --- |
| [aros68k-gcc16](aros68k-gcc16/) | GCC 16.2.0, binutils 2.47 | AROS 68k (68040) | Experimental |
| [os32-gcc16](os32-gcc16/) | bebbo's GCC 16.2.0b (`amiga16.2`) | AmigaOS 3.x (68040) | Tests only: built by [gfopengcc](https://github.com/DalsinAI/gfopengcc) |
| [os4-gcc16](os4-gcc16/) | GCC 16.2.0, binutils 2.47, with our AmigaOS 4 patches | AmigaOS 4.1 PowerPC | Experimental |
| [rust-m68k](rust-m68k/) | Rust 1.97.0 on LLVM 22.1 with our M68k fixes | 68040, `no_std` (`m68k-unknown-none-elf`) | Experimental |

All our 68k builds are for the 68040 only, and soft float by default, so one
program runs on a full 68040 and on an LC/EC040; maths go through the Amiga's
mathieee libraries, which use the FPU when there is one. Hard float
(`-m68881`) is for code that needs an FPU and says so.

With the AmigaOS 3.x stoves (os32-gcc16, and os32 with GCC 6.5), `-m68040`
alone compiles soft float, but the stock link spec (`*link_cpu`) adds libnix's
FPU maths library (`libm881`) for any 68040. Its `strtod`, `atof` and `ldexp`
return in `fp0` while soft-float code reads `d0/d1` (wrong numbers; `printf
("%f")` prints 0.000000) and the rest runs FPU instructions (a crash on an
LC/EC040). Two fixes, both in `build/`:

- `build/m68k-soft-m68040.specs`: pass `-specs=<its absolute path>` with
  `-m68040` on every soft-float build that links libnix. Then `-m68040` alone
  links the soft `libm020`; only `-m68881`, `-mhard-float` or a 68060 adds
  `libm881`.
- `build/install-os32-specs.sh STOVE`: gives a stove the same `*link_cpu` as its
  default. It writes the stove's full specs (`gcc -dumpspecs`) with only that
  line changed to `prefix/lib/gcc/m68k-amigaos/<version>/specs`, then checks
  that `-m68040` alone links `libm020` and not `libm881`, and that `-m68881`
  still links `libm881`. Run it when a stove is built (os32-gcc16 is built by
  gfopengcc, os32 is bebbo's amiga-gcc). It refuses a stove under
  `~/AmiCradle/stoves` unless `LIVE_OK=1`: a stove in use is changed only
  on purpose. `--check-only` just checks. The `-specs=` flag stays harmless on
  a stove that has the fix.

The game ports (amicradle-gameports: AstroMenace, AssaultCube, UQM,
NXEngine) link zlib, PNG, JPEG and FreeType from an inventory pinned by
SHA-256 in that repository's `toolchain/port-dependencies.lock.json`, and
refuse to build (`DEPENDENCY_GATE_FAILED`) until a stove holds it in
`prefix/m68k-amigaos/port-deps/`. `build/install-port-deps.sh STOVE GAMEPORTS
SOURCE` stages it with the gameports checkout's own `port_dependencies.py`:
every hash is checked first, only `port-deps/` is written, and a stove that
already verifies is left as it is. `--check-only` just checks; a live stove
under `~/AmiCradle/stoves` needs `LIVE_OK=1`, as for the specs.

The aros68k-gcc16 recipe makes `-mcpu=68040` with soft float its default
through its own specs file (see its README).

Each stove says what it is in `stove.json`, so it is never mistaken for
another compiler: a stove is added beside the ones that work, never in place
of them.

os4-gcc16 is built here, but it needs Hyperion's AmigaOS 4.1 SDK for the OS
headers. Its `build.sh` downloads the SDK on the machine that builds the stove
(or takes the archive you give it); the SDK is never committed or published.

The AmigaOS 3.2 stoves are not built here. They need the AmigaOS NDK, which is
not ours to redistribute; they stay on the machines that hold their own NDK.
`os32-gcc16/` holds tests for the GCC 16 one; its recipe and patches are DalsinAI/gfopengcc.

## Licences

The scripts, tests and documents here are MIT licensed (see LICENSE).

The compilers are built from third-party sources under their own licences:
GCC and binutils under the GPL (version 3 or later), with GCC's runtime
library exception, and so are our AmigaOS patches to them; gmp, mpfr and mpc under the LGPL; isl under the MIT
licence; LLVM, and our patches to it, under the Apache License 2.0 with LLVM
Exceptions; Rust under MIT or Apache 2.0; AROS and its headers and libraries under the AROS Public License; clib2 under
the BSD 3-clause licence; clib4 under the BSD 3-clause licence, with some
files under the LGPL and GPL.
Every release that carries binaries also carries the exact sources and
patches they were built from. Programs you compile with a stove can be under
any licence you choose.

## Contributors

AmigaChrome stoves is created and maintained by [SacredTrees](https://github.com/SacredTrees) with The AmiCradle Team, copyright AmiCradle Team. Everyone whose work it includes is credited in [`CONTRIBUTORS.md`](CONTRIBUTORS.md).
