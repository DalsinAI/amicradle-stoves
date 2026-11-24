#!/bin/sh
# A rebuild recipe for a build that wants the m68k ELF tools (68k ELF, System V ABI):
#   sh "$REBUILD/recipes/m68kelf.sh" COMMAND [ARG ...]
# runs COMMAND with M68K_ELF (the tools' prefix) and CC, LD, NM, OBJCOPY set to the m68kelf-gcc16-open9
# stove beside the rebuild's stove (STOVES/m68kelf-gcc16-open9, made by m68kelf-gcc16/build.sh), or
# M68KELF_STOVE. Each is kept when it is already set. MIT, Copyright (c) 2026 AmiCradle Team.
set -eu
[ $# -gt 0 ] || { echo "usage: m68kelf.sh COMMAND [ARG ...]" >&2; exit 2; }
E=${M68KELF_STOVE:-$(dirname "$STOVE")/m68kelf-gcc16-open9}
X=$E/prefix/bin/m68k-linux-gnu-
[ -x "${X}gcc" ] || { echo "m68kelf.sh: no ${X}gcc (make the stove with m68kelf-gcc16/build.sh)" >&2; exit 2; }
M68K_ELF=${M68K_ELF:-$X}; CC=${CC:-${X}gcc}; LD=${LD:-${X}ld}; NM=${NM:-${X}nm}; OBJCOPY=${OBJCOPY:-${X}objcopy}
export M68K_ELF CC LD NM OBJCOPY
echo "m68kelf.sh: $("${X}gcc" --version | sed -n 1p) ($E)"
exec "$@"
