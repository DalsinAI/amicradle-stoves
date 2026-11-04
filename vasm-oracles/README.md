# vasm-oracles

Host (x86-64 Linux) vasm binaries that [gfopenasm](https://github.com/DalsinAI/gfopenasm)'s
clean-room tests compare our assembler's output against. Not a stove: test tools only.

`build-vasm-oracles.sh [OUT] [TARBALL]` builds them from the same release as the os32-gcc16 stove's
`vasmm68k_mot` (`../os32-gcc16/vasm/vasm.lock`: vasm 2.0f, the authors' own archive checked by
SHA-256), by the same method (`make CPU=... SYNTAX=...`, one fresh unpack per binary):

| Binary | CPU | Syntax |
| --- | --- | --- |
| `vasmm68k_mot`, `vasmm68k_std` | m68k | mot, std |
| `vasmppc_mot`, `vasmppc_std` | ppc | mot, std |
| `vasmarm_std` | arm | std |
| `vasmx86_std` | x86 | std |
| `vasmz80_oldstyle`, `vasmz80_std` | z80 | oldstyle, std |
| `vasm6502_oldstyle`, `vasm6502_std` | 6502 | oldstyle, std |

Each must say `vasm 2.0f` and assemble ` nop` to a non-empty `-Fbin` file. `OUT` (default
`~/AmiCradle/stoves/vasm-oracles/2.0f`) gets `bin/`, a `README.txt` (archive, SHA-256, build
commands, licence) and `SHA256SUMS`. About a minute.

```sh
sh vasm-oracles/build-vasm-oracles.sh
```

**Licence and clean room.** vasm is free for non-commercial use only and not open source. The oracles
are a build/test tool on our own machines: never redistributed, never shipped in a release of ours.
gfopenasm's authors use them only as black boxes and never read vasm's source; a separate builder runs
this script. Nothing of vasm's source is, or goes, in this repository.
