#!/bin/sh
# Installs a Linux userland compiler stove (linux-ARCH-glibc-gcc16) from the release in
# linux-glibc-gcc16/ARCH.lock, beside the other stoves. ARCH is x86_64 (daletop, the CI runners, the AMD
# appliance) or aarch64 (CM4 and Pi 5 cards). It builds Linux programs (C and C++) over a glibc 2.35 sysroot:
# AmiCradle's native runtimes (gfosmotherboards ci/build_runtimes.py, amicradle scripts/deploy/deploy_dev.py).
#
#   linux-glibc-gcc16/install.sh ARCH STOVES [ARCHIVE]
#
# STOVES is the stoves folder (~/AmiCradle/stoves, Settings > Folders' "Stoves"); ARCHIVE the release's
# toolchain (the lock's archive_url; downloaded when not given). It:
#   1. refuses an archive whose SHA-256 isn't the lock's;
#   2. unpacks it as STOVES/linux-ARCH-glibc-gcc16-RELEASE/prefix (a new folder: one that is there already
#      is left as it is, and checked);
#   3. writes STOVE.json (the release, the archive, the compilers, the sysroot) and README.txt;
#   4. checks gcc and g++ say the identity, the sysroot is inside the prefix, and that a C program that uses
#      threads and libm links, asks for no glibc symbol above 2.35 and runs (natively on x86_64 on an x86-64
#      host, under qemu-aarch64 with the sysroot's glibc);
#   5. points STOVES/linux-ARCH-glibc-gcc16 at it, unless that name is a folder or links elsewhere and
#      KEEP_LINK=1 is set.
# MIT, Copyright (c) 2026 AmiCradle Team.
set -eu
UNPACK=""
HERE=$(cd "$(dirname "$0")" && pwd)
ARCH=${1:?usage: install.sh ARCH STOVES [ARCHIVE]}
case $ARCH in x86_64|aarch64) ;; *) echo "ARCH $ARCH: x86_64 or aarch64"; exit 2 ;; esac
LOCK=${LINUX_GLIBC_LOCK:-"$HERE/$ARCH.lock"}   # the variable only for tests
STOVES=${2:?usage: install.sh ARCH STOVES [ARCHIVE]}
ARCHIVE=${3:-}
lock() { sed -n "s/^$1=//p" "$LOCK"; }
release=$(lock release); want=$(lock identity); top=$(lock top); T=$(lock target)
NAME=linux-$ARCH-glibc-gcc16
[ "$T" = "$ARCH-linux-gnu" ] || { echo "$LOCK is for $T, not $ARCH"; exit 2; }
mkdir -p "$STOVES"; STOVES=$(cd "$STOVES" && pwd); DEST="$STOVES/$NAME-$release"
GCC="$DEST/prefix/bin/$T-gcc"; GXX="$DEST/prefix/bin/$T-g++"

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
  "name": "Linux $ARCH programs, $(echo "$want" | tr -d '()'), glibc 2.35",
  "release": "$(echo "$want" | tr -d '()')",
  "status": "installed",
  "target": "$T",
  "use": "Linux programs over a glibc 2.35 sysroot (Ubuntu 22.04 and newer): C and C++; AmiCradle's native runtimes",
  "prefix": "$DEST/prefix",
  "compilers": {
    "c": "$DEST/prefix/bin/$T-gcc",
    "c++": "$DEST/prefix/bin/$T-g++"
  },
  "glibc": "2.35",
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
$NAME: $(echo "$want" | tr -d '()') for $T over glibc 2.35 (gfopengcc $(lock tag)), installed by
amicradle-stoves linux-glibc-gcc16/install.sh. C and C++ for Linux programs that start on Ubuntu 22.04
and newer (a C++ program for 22.04 links libstdc++ with -static-libstdc++).
  CC=$DEST/prefix/bin/$T-gcc CXX=$DEST/prefix/bin/$T-g++
TXT
    mv "$UNPACK/stove" "$DEST"
fi

echo "== 4. checks"
"$GCC" --version | sed -n 1p | grep -qF "$want" || { echo "$GCC does not say $want"; exit 1; }
"$GXX" --version | sed -n 1p | grep -qF "$want" || { echo "$GXX does not say $want"; exit 1; }
"$GCC" --version | sed -n 1p
SR=$("$GCC" -print-sysroot)
case $(cd "$SR" 2>/dev/null && pwd) in "$DEST"/*) echo "sysroot $SR" ;; *) echo "the sysroot ($SR) is not inside $DEST"; exit 1 ;; esac
C=$(mktemp -d); trap 'rm -rf "$C" ${UNPACK:+"$UNPACK"}' EXIT
cat > "$C/hello.c" <<'SRC'
#include <math.h>
#include <pthread.h>
#include <stdio.h>
static double r;
static void *work(void *a) { r = sqrt(*(double *)a); return 0; }
int main(void) { pthread_t t; double x = 16.0; pthread_create(&t, 0, work, &x); pthread_join(t, 0); printf("stove ok %g\n", r); return r != 4.0; }
SRC
"$GCC" -O2 -o "$C/hello" "$C/hello.c" -lm -lpthread
OBJDUMP="$DEST/prefix/bin/$T-objdump"
g=$("$OBJDUMP" -T "$C/hello" | grep -oE 'GLIBC_2\.[0-9]+' | sort -t. -k2,2n | tail -1)
[ "${g#GLIBC_2.}" -le 35 ] || { echo "a program asks for $g, above the 2.35 floor"; exit 1; }
if [ -n "${NO_RUN:-}" ]; then
    echo "a C program links, needs $g (not run here)"
elif [ "$ARCH" = x86_64 ] && [ "$(uname -m)" = x86_64 ]; then
    [ "$("$C/hello")" = "stove ok 4" ] || { echo "the test program did not run"; exit 1; }
    echo "a C program runs, needs $g"
elif [ "$ARCH" = aarch64 ] && command -v qemu-aarch64 > /dev/null; then
    [ "$(qemu-aarch64 -L "$SR" "$C/hello")" = "stove ok 4" ] || { echo "the test program did not run under qemu-aarch64"; exit 1; }
    echo "a C program runs under qemu-aarch64, needs $g"
elif [ "$ARCH" = aarch64 ] && [ "$(uname -m)" = aarch64 ]; then
    [ "$("$C/hello")" = "stove ok 4" ] || { echo "the test program did not run"; exit 1; }
    echo "a C program runs, needs $g"
else
    echo "a C program links, needs $g (not run here)"
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
