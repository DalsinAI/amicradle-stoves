#!/bin/sh
# m68kelf-gcc16/check.sh PREFIX [TARGET] [IDENTITY]
# Checks an m68k ELF stove's prefix does what a freestanding 68k ELF build needs: the identity, elf32-m68k
# objects with System V names (no leading underscore), -fPIC through the GOT, ld -q, ld -r, a PIE and a shared
# object (with a constructor), readelf on them, objcopy to binary, libgcc, and no shared GMP/MPFR/MPC.
# MIT, Copyright (c) 2026 AmiCradle Team.
set -eu
P=$(cd "${1:?usage: check.sh PREFIX [TARGET] [IDENTITY]}" && pwd)
T=${2:-m68k-linux-gnu}; ID=${3:-GFOpenAmigaGCC 16.2.0-open9}
X=$P/bin/$T-
fail() { echo "check: $*"; exit 1; }
"${X}gcc" --version | sed -n 1p | grep -qF "($ID)" || fail "${X}gcc does not say ($ID)"
"${X}ld" -V | grep -q m68kelf || fail "${X}ld has no m68kelf emulation"
for b in "${X}gcc" "${X}ld" "${X}as"; do
  ! ldd "$b" 2>/dev/null | grep -qE 'libgmp|libmpfr|libmpc' || fail "$b links GMP/MPFR/MPC shared"
done
C=$(mktemp -d); trap 'rm -rf "$C"' EXIT
cat > "$C/f.c" <<'SRC'
extern int g;
int f(int x) { return x + g; }
int g = 41;
__attribute__((constructor)) static void hello(void) { g++; }
long long mul(long long a, long long b) { return a * b / 3; }
SRC
cat > "$C/s.c" <<'SRC'
extern int f(int);
void _start(void) { f(1); for (;;) ; }
SRC
F="-m68040 -msoft-float -Os -ffreestanding -fno-builtin"
"${X}gcc" $F -c "$C/f.c" -o "$C/f.o"
"${X}readelf" -h "$C/f.o" | grep -q 'ELF32' || fail "f.o is not ELF32"
"${X}readelf" -h "$C/f.o" | grep -q 'MC68000' || fail "f.o is not m68k"
"${X}nm" "$C/f.o" | grep -qE ' T f$' || fail "f.o names f with something else (a leading underscore?)"
"${X}gcc" $F -fPIC -c "$C/f.c" -o "$C/fp.o"
"${X}readelf" -r "$C/fp.o" | grep -q 'GOT' || fail "-fPIC does not go through the GOT"
"${X}gcc" $F -c "$C/s.c" -o "$C/s.o"
"${X}ld" -q -N -Ttext=0 -e _start "$C/s.o" "$C/f.o" -lgcc -L"$("${X}gcc" -m68040 -msoft-float -print-libgcc-file-name | xargs dirname)" -o "$C/q.elf" \
  || fail "ld -q (relocations kept) failed"
"${X}readelf" -S "$C/q.elf" | grep -q '\.rela' || fail "ld -q kept no relocations"
"${X}ld" -r "$C/s.o" "$C/f.o" -o "$C/r.o" && "${X}readelf" -h "$C/r.o" | grep -q 'REL (Relocatable' || fail "ld -r failed"
"${X}gcc" $F -fPIE -c "$C/s.c" -o "$C/sp.o"
"${X}gcc" $F -fPIE -pie -nostdlib -Wl,-e,_start,--no-dynamic-linker,-z,norelro "$C/sp.o" "$C/fp.o" -lgcc -o "$C/pie.elf" \
  && "${X}readelf" -h "$C/pie.elf" | grep -q 'DYN' || fail "-pie failed"
"${X}gcc" $F -fPIC -shared -nostdlib -Wl,--hash-style=both "$C/f.c" -lgcc -o "$C/libf.so" \
  && "${X}readelf" -d "$C/libf.so" | grep -q 'INIT_ARRAY' || fail "-shared (with a constructor) failed"
"${X}objcopy" -O binary "$C/q.elf" "$C/q.bin" && [ -s "$C/q.bin" ] || fail "objcopy -O binary failed"
"${X}gcc" $F -print-libgcc-file-name | grep -q 'libgcc.a' || fail "no libgcc"
echo "check: $("${X}gcc" --version | sed -n 1p): elf32-m68k, SysV names, GOT, ld -q, ld -r, PIE, shared, readelf, objcopy: ok"
