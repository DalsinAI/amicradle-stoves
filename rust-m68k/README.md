# rust-m68k: Rust for the 68040

Rust 1.97.0 for `m68k-unknown-none-elf`, built on the LLVM it ships with
(rust-lang/llvm-project `rustc/22.1-2026-05-19`, commit `08c84e69a8`) plus
the M68k backend fixes in `patches/llvm`. Stock Rust 1.97 builds 68k code that
prints wrong numbers, hangs, or crashes the compiler; with these patches its
output matches a PC's exactly.

Status: experimental. `core` and `compiler_builtins` only (`no_std`); there is
no AmigaOS target, `alloc` or `std` yet. Load files go through
[elf.library](https://github.com/DalsinAI/amicradle-guest/tree/main/libraries/openelf).

## What was wrong

| Patch | Problem | Seen as |
| --- | --- | --- |
| 0001 | An address made of a stack slot plus a register lost the register, so `buf[i]` on a local array always used `buf[0]`. | Integers printed with wrong digits. |
| 0002 | A register copy placed between a compare and its branch destroyed the condition flags. Upstream LLVM `e7dd336e0f`. | `core::fmt::write` looped forever. |
| 0003 | `DIVU.L`/`DIVS.L` with a 64-bit result were encoded with the remainder in `d0`, whatever register was asked for. | 64-bit division and `%` clobbered `d0`. |
| 0004 | Loads and stores were folded across calls. Upstream LLVM `a6032d293c`. | rustc crashed building `compiler_builtins` at opt-level 0. |
| 0005 | A 16-to-32-bit zero/sign extend could target an address register, where `AND.L`/`EXT.L` do not exist; `and.l #$ffff,%a1` was encoded as `%d1`. | `{:.3}` float printing lost the low half of its number. |
| 0006 | MOVEM and PHI lowering broke the machine verifier. Upstream LLVM `5ed74925eb`; its `cmp-cse.ll` checks are regenerated for this branch. | `-verify-machineinstrs` errors. |
| 0007 | The MOVEM collapse pass could merge the same register twice. Upstream LLVM `24b86130ef`. | Found upstream; needed before 0008. |
| 0008 | The same pass merged registers out of address order; MOVEM always uses the lowest register at the lowest address, so two values swapped. | At opt-level 0, a zero divisor reached `__udivdi3` and float printing hung. |

0001, 0003, 0005 and 0008 are ours, each with an LLVM regression test. All
M68k CodeGen, MC and disassembler tests pass with the patches.

## Building the stove

    ./build.sh            # LLVM with the patches, then Rust; rustup toolchain "rust-m68k"
    ./build.sh --llvm-only

Sources are pinned by commit (LLVM `08c84e69a84d`, Rust tag `1.97.0` =
`2d8144b78805`) and checked after the clone; a Rust checkout with local
changes is refused. A finished build writes `work/stove.json`: the stove's
identity, with its pinned refs, patches, target and default flags. LLVM is built with assertions on,
for X86 and M68k only.

## Building a program

The 68040 settings (soft float, large code model) are in `cargo-config.toml`;
`build.sh` also copies it to `work/cargo-config.toml`. Copy it into the
project's `.cargo/config.toml`, or pass it:

    RUSTC_BOOTSTRAP=1 cargo +rust-m68k build --release --target m68k-unknown-none-elf \
        --config /path/to/rust-m68k/cargo-config.toml \
        -Zbuild-std=core,compiler_builtins -Zbuild-std-features=compiler-builtins-mem

`-C code-model=large` is needed. The default small model reaches data with
16-bit PC-relative addresses, so any program over about 32 KB fails to link.
The large model uses absolute addresses, as GCC does.

Drop `-isa-68881,-isa-68882` only for code that needs an FPU and says so.

## Tests

`tests/run-tests` builds `tests/src` twice, for the 68040 and for this PC,
runs the 68040 build under `qemu-m68k -cpu m68040`, and compares the two
line by line. The program checks integer, 64-bit and 128-bit arithmetic,
soft-float maths and conversions, and `core::fmt` printing of integers and
floats at every precision. Results on 22 October 2026:

| Built with | Result |
| --- | --- |
| rust-m68k (this stove) | PASS, all 87 lines match the PC at opt-level 0, 1, 2, 3, s and z |
| Stock Rust 1.97.0, bitcode through the patched `llc` (`--llc`) | PASS at opt-level 2 |
| Stock Rust 1.97.0 | FAIL: hangs before printing a line at opt-level 2; rustc crashes building `compiler_builtins` at opt-level 0 |

    tests/run-tests                       # with the rust-m68k toolchain
    tests/run-tests --opt-level 0
    tests/run-tests --toolchain 1.97.0 --llc work/llvm-build/bin/llc
    tests/run-tests --toolchain 1.97.0    # stock Rust, to see it fail

Needs `qemu-m68k`, `binutils-m68k-linux-gnu` and the `rust-src` component.

## Licences

The scripts, tests and this README are MIT (see `../LICENSE`). LLVM and our
patches to it are under the Apache License 2.0 with LLVM Exceptions. Rust is
under MIT or Apache 2.0.
