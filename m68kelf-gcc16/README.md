# m68kelf-gcc16: the m68k ELF companion stove

`m68kelf-gcc16-open9` is GFOpenAmigaGCC 16.2.0-open9 for **68k ELF**: `m68k-linux-gnu`, the System V ABI (no
leading underscore), `elf32-m68k` objects, `-fPIC` through the GOT, `-pie`, `-shared`, `ld -q` (relocations kept)
and `ld -r`, `readelf` and `objcopy`. It is C only, with libgcc and no C library: what a freestanding 68k ELF build
needs. os32-gcc16's binutils know only the Amiga's formats (`ld -V`: amiga, amiga_bss), and its GCC uses the Amiga
ABI (`_name`, `-fbaserel` in place of `-fPIC`, no `-shared`), so it can't make these.

Its first user is DalsinAI/gfopenelflibrary. elf.library and its tools are linked as ELF at 0 and made into hunk
files by `tools/mkhunk.py`. Its `ELF/` examples (a `-q` executable, an object, a PIE, a shared object with a
constructor) are the very files elf.library loads. Before this stove, it needed Debian/Ubuntu's `gcc-m68k-linux-gnu`.

The stove is gfopengcc's Linux kernel compiler recipe (`scripts/build-linux.sh`) for one more target:

- the same stock GCC 16.2.0 and binutils 2.47 (gfopengcc `scripts/linux.lock`, the m68k-aros pins), each checked
  against its SHA-256;
- the same `patches/linux/series` (fold-mem-offsets, GCC 0019);
- the same configure, and the release identity.

All of it is taken from gfopengcc at the commit in [m68kelf.lock](m68kelf.lock).

```sh
m68kelf-gcc16/build.sh STOVES [WORK] [JOBS]       # TARBALLS=DIR: tarballs to take before downloading
STOVES/m68kelf-gcc16-open9/prefix/bin/m68k-linux-gnu-gcc ...
```

`build.sh`:

1. refuses a stove that is there already;
2. builds into WORK, configured for the final place;
3. runs `check.sh` on the result;
4. writes `STOVE.json`: the release, the target, the sources and their SHA-256, the gfopengcc commit, and the
   prefix's archive with its SHA-256;
5. puts that archive (`m68kelf-gcc16-open9-x86_64-linux.tar.xz`, reproducible) and its `.sha256` in the stove's
   `dist/` for publishing;
6. moves the stove into place.

`check.sh PREFIX` tests the identity, the `m68kelf` emulation, System V names, a `-fPIC` object's GOT
relocations, `ld -q`, `ld -r`, a PIE, a shared object with a constructor, `objcopy -O binary`, and libgcc.

The open9 rebuild runs gfopenelflibrary through `os32-gcc16/rebuild/recipes/m68kelf.sh`, which sets `M68K_ELF`,
`CC`, `LD`, `NM` and `OBJCOPY` to this stove beside the rebuild's own.
