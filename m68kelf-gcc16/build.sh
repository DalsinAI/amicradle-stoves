#!/bin/bash
# m68kelf-gcc16/build.sh STOVES [WORK] [JOBS]
# Builds the m68k ELF companion stove, STOVES/m68kelf-gcc16-open9: GFOpenAmigaGCC 16.2.0-open9 for
# m68k-linux-gnu (68k ELF, the System V ABI: no leading underscore, -fPIC with a GOT, -pie, -shared, ld -r,
# readelf and objcopy for elf32-m68k), C only, libgcc without a C library: what a freestanding 68k ELF
# build needs, such as gfopenelflibrary's (elf.library and its tools are linked as ELF and made into hunk
# files; its ELF examples are the very files elf.library loads). os32-gcc16's binutils know only the
# Amiga's formats, so it can't make them.
# It is gfopengcc's Linux kernel compiler recipe (scripts/build-linux.sh) for one more target: the same
# stock GCC 16.2.0 and binutils 2.47 (gfopengcc scripts/linux.lock, the m68k-aros pins), the same
# patches/linux/series (fold-mem-offsets, GCC 0019), the same configure and the release identity, taken
# from gfopengcc at the commit in m68kelf.lock. Each tarball is checked against the lock's SHA-256.
#   STOVES   the stoves folder; the stove is made as STOVES/m68kelf-gcc16-open9 (refused if it is there)
#   WORK     where it builds (default STOVES/../stove-build/m68kelf-gcc16); TARBALLS: a folder of tarballs
#            to take before downloading (each still checked)
# It writes STOVE.json (release, target, sources and their SHA-256, the gfopengcc commit, the archive of the
# prefix and its SHA-256), puts that archive (m68kelf-gcc16-open9-x86_64-linux.tar.xz) and its .sha256 in
# the stove's dist/ for publishing, and checks the stove (check.sh) before it moves it into place.
# Needs the host's GCC build tools and static GMP, MPFR and MPC (libgmp-dev, libmpfr-dev, libmpc-dev).
# MIT, Copyright (c) 2026 AmiCradle Team.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
STOVES=$(cd "${1:?usage: build.sh STOVES [WORK] [JOBS]}" && pwd)
WORK=${2:-$STOVES/../stove-build/m68kelf-gcc16}; mkdir -p "$WORK"; WORK=$(cd "$WORK" && pwd)
JOBS=${3:-$(nproc)}
lock() { sed -n "s/^$1=//p" "$HERE/m68kelf.lock"; }
NAME=$(lock name); T=$(lock target); ID=$(lock identity); GFC=$(lock gfopengcc_commit)
DEST=$STOVES/$NAME
[ ! -e "$DEST" ] || { echo "$DEST is there already: refused (move it away first)"; exit 2; }
say() { echo "== $*"; }
sha() { sha256sum "$1" | cut -d' ' -f1; }

say "gfopengcc at $GFC (the series, the patches, linux.lock)"
G=$WORK/gfopengcc
[ -d "$G/.git" ] || git clone -q "$(lock gfopengcc_url)" "$G"
git -C "$G" cat-file -e "$GFC^{commit}" 2>/dev/null || git -C "$G" fetch -q origin
R=$WORK/recipe; rm -rf "$R"; mkdir -p "$R"
git -C "$G" archive "$GFC" scripts/linux.lock patches | tar -x -C "$R"

say "sources (gfopengcc scripts/linux.lock)"
A=$WORK/tarballs; mkdir -p "$A"
for name in gcc binutils; do
  read -r _ url pin file < <(grep -E "^$name[[:space:]]" "$R/scripts/linux.lock")
  f=$A/$file
  if [ ! -f "$f" ] || [ "$(sha "$f")" != "$pin" ]; then
    rm -f "$f"
    if [ -n "${TARBALLS:-}" ] && [ -f "$TARBALLS/$file" ] && [ "$(sha "$TARBALLS/$file")" = "$pin" ]; then cp "$TARBALLS/$file" "$f"
    else curl -fsSL --retry 3 -o "$f.part" "$url" && mv "$f.part" "$f"; fi
  fi
  [ "$(sha "$f")" = "$pin" ] || { echo "$file is not the pinned $pin"; exit 1; }
  echo "$name: $file ($pin)"
  eval "${name}_file=\$file ${name}_sha=\$pin"
done

# Configured for its final place (DEST/prefix) and installed under WORK/stage (DESTDIR), then moved there.
S=$WORK/src; B=$WORK/build; LOGS=$WORK/logs; STAGE=$WORK/stage; P=$STAGE$DEST/prefix
rm -rf "$S" "$B" "$STAGE"; mkdir -p "$S" "$B" "$LOGS" "$P"
tar -C "$S" -xf "$A/$gcc_file"; tar -C "$S" -xf "$A/$binutils_file"
GS=$S/${gcc_file%.tar.*}; BS=$S/${binutils_file%.tar.*}
grep -v '^#' "$R/patches/linux/series" | while read -r tree p; do
  [ -n "$tree" ] || continue
  case $tree in gcc) d=$GS ;; binutils) d=$BS ;; *) echo "series: no tree $tree"; exit 1 ;; esac
  ( cd "$d" && patch -p1 -s -F0 -f --dry-run < "$R/patches/$p" > /dev/null ) || { echo "does not apply: patches/$p"; exit 1; }
  ( cd "$d" && patch -p1 -s -F0 -f --no-backup-if-mismatch < "$R/patches/$p" )
  echo "applied $p"
done

SL=$B/static-libs; mkdir -p "$SL"
for l in gmp mpfr mpc; do
  a=$(${HOST_CC:-cc} -print-file-name=lib$l.a)
  [ -f "$a" ] || { echo "no lib$l.a on this host (libgmp-dev, libmpfr-dev, libmpc-dev)"; exit 1; }
  ln -sf "$a" "$SL/lib$l.a"
done

say "binutils (logs in $LOGS)"
mkdir -p "$B/binutils"
( cd "$B/binutils" && "$BS/configure" --prefix="$DEST/prefix" --target=$T \
    --disable-werror --disable-nls --disable-gdb --disable-gdbserver --disable-sim --disable-gprofng --without-zstd \
  && make -j"$JOBS" && make install DESTDIR="$STAGE" ) > "$LOGS/binutils.log" 2>&1 || { echo "binutils failed (see $LOGS/binutils.log)"; tail -30 "$LOGS/binutils.log"; exit 1; }
echo "MILESTONE binutils: $("$P/bin/$T-ld" --version | head -1)"

say "gcc (logs in $LOGS)"
export PATH="$P/bin:$PATH"
mkdir -p "$B/gcc"
( cd "$B/gcc" && "$GS/configure" --prefix="$DEST/prefix" --target=$T \
    --enable-languages=c --without-headers --with-newlib --disable-shared --disable-threads \
    --disable-bootstrap --disable-nls --disable-multilib --disable-libssp --disable-libgomp \
    --disable-libquadmath --disable-libatomic --disable-libitm --disable-libsanitizer --disable-libvtv \
    --disable-libcc1 --disable-decimal-float --without-isl --without-zstd \
    --with-gmp-lib="$SL" --with-mpfr-lib="$SL" --with-mpc-lib="$SL" \
    --with-pkgversion="$ID" ) > "$LOGS/gcc-configure.log" 2>&1 || { echo "gcc configure failed (see $LOGS/gcc-configure.log)"; tail -30 "$LOGS/gcc-configure.log"; exit 1; }
( cd "$B/gcc" && make -j"$JOBS" all-gcc all-target-libgcc && make -j1 install-gcc install-target-libgcc DESTDIR="$STAGE" ) > "$LOGS/gcc.log" 2>&1 \
  || { echo "gcc failed (see $LOGS/gcc.log)"; tail -40 "$LOGS/gcc.log"; exit 1; }
echo "MILESTONE gcc: $("$P/bin/$T-gcc" --version | head -1)"

say "checks"
sh "$HERE/check.sh" "$P" "$T" "$ID"

say "archive and STOVE.json"
ARCH=$NAME-x86_64-linux.tar.xz
( cd "$STAGE$DEST" && tar --sort=name --owner=0 --group=0 --numeric-owner --mtime=@0 -cJf "$WORK/$ARCH" prefix )
ASHA=$(sha "$WORK/$ARCH"); echo "$ASHA  $ARCH" > "$WORK/$ARCH.sha256"
mkdir -p "$STAGE$DEST/dist"; cp "$WORK/$ARCH" "$WORK/$ARCH.sha256" "$STAGE$DEST/dist/"
cat > "$STAGE$DEST/STOVE.json" <<JSON
{
  "schema": 1,
  "id": "$NAME",
  "name": "68k ELF programs and objects (m68k-linux-gnu, freestanding), $ID",
  "release": "$ID",
  "status": "installed",
  "target": "$T",
  "use": "freestanding 68k ELF: System V ABI, -fPIC/-pie/-shared, ld -r, readelf, objcopy elf32-m68k; libgcc, no C library (gfopenelflibrary)",
  "prefix": "$DEST/prefix",
  "compilers": {"c": "$DEST/prefix/bin/$T-gcc"},
  "binutils": "$("$P/bin/$T-ld" --version | head -1)",
  "sources": {"$gcc_file": "$gcc_sha", "$binutils_file": "$binutils_sha"},
  "recipe": {"repository": "DalsinAI/gfopengcc", "commit": "$GFC", "series": "patches/linux/series", "lock": "scripts/linux.lock",
             "how": "amicradle-stoves m68kelf-gcc16/build.sh (gfopengcc scripts/build-linux.sh's configure for $T)"},
  "compilerArchive": {"archive": "$ARCH", "sha256": "$ASHA", "published": "not yet: the archive and its .sha256 are in $DEST/dist"},
  "built": "$(date -u +%Y%m%dT%H%M%SZ)"
}
JSON
mv "$STAGE$DEST" "$DEST"
echo "$NAME: $("$DEST/prefix/bin/$T-gcc" --version | head -1) in $DEST; archive $WORK/$ARCH ($ASHA)"
