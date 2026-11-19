#!/bin/sh
# Installs a Linux kernel compiler stove (linux-ARCH-gcc16) from the release in linux-gcc16/ARCH.lock,
# beside the other stoves. ARCH is aarch64 (CM4 and Pi 5 cards), x86_64 (the AMD appliance) or
# powerpc (32-bit, the AC460).
#
#   linux-gcc16/install.sh ARCH STOVES [ARCHIVE]
#
# STOVES is the stoves folder (~/AmiCradle/stoves, Settings > Folders' "Stoves"); ARCHIVE the release's
# toolchain (the lock's archive_url; downloaded when not given). It:
#   1. refuses an archive whose SHA-256 isn't the lock's;
#   2. unpacks it as STOVES/linux-ARCH-gcc16-RELEASE/prefix (a new folder: one that is there already
#      is left as it is, and checked);
#   3. writes STOVE.json (the release, the archive, the compilers) and README.txt;
#   4. checks the compiler says the identity, and that a freestanding program for ARCH compiles, links
#      and runs (natively on x86_64, under qemu-aarch64 / qemu-ppc);
#   5. points STOVES/linux-ARCH-gcc16 at it, unless that name is a folder or links elsewhere and
#      KEEP_LINK=1 is set.
# A kernel is built with: make ARCH=arm64 (x86_64, powerpc) CROSS_COMPILE=STOVES/linux-ARCH-gcc16/prefix/bin/ARCH-linux-gnu-
# MIT, Copyright (c) 2026 AmiCradle Team.
set -eu
UNPACK=""
HERE=$(cd "$(dirname "$0")" && pwd)
ARCH=${1:?usage: install.sh ARCH STOVES [ARCHIVE]}
case $ARCH in aarch64|x86_64|powerpc) ;; *) echo "ARCH $ARCH: aarch64, x86_64 or powerpc"; exit 2 ;; esac
LOCK=${LINUX_GCC_LOCK:-"$HERE/$ARCH.lock"}   # the variable only for tests
STOVES=${2:?usage: install.sh ARCH STOVES [ARCHIVE]}
ARCHIVE=${3:-}
lock() { sed -n "s/^$1=//p" "$LOCK"; }
release=$(lock release); want=$(lock identity); top=$(lock top); T=$(lock target)
NAME=linux-$ARCH-gcc16
[ "$T" = "$ARCH-linux-gnu" ] || { echo "$LOCK is for $T, not $ARCH"; exit 2; }
DEST="$STOVES/$NAME-$release"
mkdir -p "$STOVES"; STOVES=$(cd "$STOVES" && pwd); DEST="$STOVES/$NAME-$release"
GCC="$DEST/prefix/bin/$T-gcc"

if [ -e "$DEST" ]; then
    echo "== $DEST is there already: checking it"
    [ -x "$GCC" ] || { echo "$DEST has no prefix/bin/$T-gcc: move it away first"; exit 2; }
    grep -q "\"archiveSha256\": \"$(lock archive_sha256)\"" "$DEST/STOVE.json" 2>/dev/null \
        || { echo "$DEST/STOVE.json is not from $(lock archive): move it away first"; exit 2; }
else
    echo "== 1. the archive"
    UNPACK=$(mktemp -d "$STOVES/.$NAME.XXXXXX")
    trap 'rm -rf "$UNPACK"' EXIT
    if [ -z "$ARCHIVE" ]; then
        ARCHIVE="$UNPACK/$(lock archive)"
        curl -fsSL --retry 3 -o "$ARCHIVE" "$(lock archive_url)"
    fi
    got=$(sha256sum "$ARCHIVE" | cut -d' ' -f1)
    if [ "$got" != "$(lock archive_sha256)" ]; then
        echo "$ARCHIVE: SHA-256 $got is not $release's ($(lock archive_sha256)): refused"
        exit 1
    fi
    echo "$ARCHIVE: $release ($got)"

    echo "== 2. $DEST"
    mkdir "$UNPACK/unpack"
    tar -C "$UNPACK/unpack" -xJf "$ARCHIVE"
    [ -x "$UNPACK/unpack/$top/bin/$T-gcc" ] || { echo "the archive has no $top/bin/$T-gcc"; exit 1; }
    mkdir "$UNPACK/stove"
    mv "$UNPACK/unpack/$top" "$UNPACK/stove/prefix"

    echo "== 3. STOVE.json"
    cat > "$UNPACK/stove/STOVE.json" <<JSON
{
  "schema": 1,
  "id": "$NAME",
  "name": "Linux $ARCH kernels, $(echo "$want" | tr -d '()')",
  "release": "$(echo "$want" | tr -d '()')",
  "status": "installed",
  "target": "$T",
  "use": "kernels and other freestanding code: C and libgcc, no C library",
  "prefix": "$DEST/prefix",
  "compilers": {
    "c": "$DEST/prefix/bin/$T-gcc"
  },
  "crossCompile": "$DEST/prefix/bin/$T-",
  "compilerArchive": {
    "repository": "DalsinAI/gfopengcc",
    "tag": "$(lock tag)",
    "commit": "$(lock commit)",
    "archive": "$(lock archive)",
    "archiveSha256": "$(lock archive_sha256)",
    "source": "$(lock source)",
    "sourceSha256": "$(lock source_sha256)"
  },
  "installed": "$(date -u +%Y%m%dT%H%M%SZ)"
}
JSON
    cat > "$UNPACK/stove/README.txt" <<TXT
$NAME: $(echo "$want" | tr -d '()') for $T (gfopengcc $(lock tag)), installed by amicradle-stoves
linux-gcc16/install.sh. A kernel cross compiler: C and libgcc, no C library.
  make ARCH=$( [ "$ARCH" = aarch64 ] && echo arm64 || echo "$ARCH" ) CROSS_COMPILE=$DEST/prefix/bin/$T- ...
TXT
    mv "$UNPACK/stove" "$DEST"
fi

echo "== 4. checks"
"$GCC" --version | sed -n 1p | grep -qF "$want" || { echo "$GCC does not say $want"; exit 1; }
"$GCC" --version | sed -n 1p
C=$(mktemp -d); trap 'rm -rf "$C" ${UNPACK:+"$UNPACK"}' EXIT
if [ "$ARCH" = aarch64 ]; then
cat > "$C/hello.c" <<'SRC'
static long sys(long n, long a, long b, long c)
{
  register long x8 __asm__("x8") = n, x0 __asm__("x0") = a, x1 __asm__("x1") = b, x2 __asm__("x2") = c;
  __asm__ volatile("svc #0" : "+r"(x0) : "r"(x8), "r"(x1), "r"(x2) : "memory");
  return x0;
}
void _start(void) { static const char m[] = "stove ok\n"; sys(64, 1, (long)m, sizeof m - 1); sys(93, 0, 0, 0); for (;;) ; }
SRC
RUN="qemu-aarch64"; FL="-mgeneral-regs-only"
elif [ "$ARCH" = powerpc ]; then
cat > "$C/hello.c" <<'SRC'
static long sys(long n, long a, long b, long c)
{
  register long r0 __asm__("r0") = n, r3 __asm__("r3") = a, r4 __asm__("r4") = b, r5 __asm__("r5") = c;
  __asm__ volatile("sc" : "+r"(r3), "+r"(r0), "+r"(r4), "+r"(r5) : : "cr0", "ctr", "r6", "r7", "r8", "r9", "r10", "r11", "r12", "memory");
  return r3;
}
void _start(void) { static const char m[] = "stove ok\n"; sys(4, 1, (long)m, sizeof m - 1); sys(1, 0, 0, 0); for (;;) ; }
SRC
RUN="qemu-ppc"; FL="-msoft-float"
else
cat > "$C/hello.c" <<'SRC'
static long sys(long n, long a, long b, long c)
{
  long r;
  __asm__ volatile("syscall" : "=a"(r) : "a"(n), "D"(a), "S"(b), "d"(c) : "rcx", "r11", "memory");
  return r;
}
void _start(void) { static const char m[] = "stove ok\n"; sys(1, 1, (long)m, sizeof m - 1); sys(60, 0, 0, 0); for (;;) ; }
SRC
RUN=""; FL="-mno-sse -mno-mmx -mno-red-zone"
fi
"$GCC" -O2 -static -nostdlib -ffreestanding $FL -o "$C/hello" "$C/hello.c" -lgcc
if [ -n "${NO_RUN:-}" ] || { [ -n "$RUN" ] && ! command -v "$RUN" > /dev/null; } || { [ -z "$RUN" ] && [ "$(uname -m)" != x86_64 ]; }; then
    echo "a freestanding program links (not run here)"
else
    [ "$($RUN "$C/hello")" = "stove ok" ] || { echo "the test program did not run${RUN:+ under $RUN}"; exit 1; }
    echo "a freestanding program runs${RUN:+ under $RUN}"
fi

echo "== 5. $STOVES/$NAME"
L="$STOVES/$NAME"
if [ -L "$L" ] || [ ! -e "$L" ]; then
    cur=$(readlink "$L" 2>/dev/null || true)
    if [ -n "$cur" ] && [ "$cur" != "$NAME-$release" ] && [ -n "${KEEP_LINK:-}" ]; then
        echo "$L stays at $cur (KEEP_LINK)"
    else
        ln -sfn "$NAME-$release" "$L"; echo "$L -> $NAME-$release"
    fi
else
    echo "$L is not a link: left as it is"
fi
echo "$NAME $release in $DEST"
