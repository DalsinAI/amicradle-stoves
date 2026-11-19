#!/bin/sh
# linux-glibc-gcc16/install.sh with made-up releases, no network: a real gfopengcc userland toolchain
# when USERLAND_X86_64 / USERLAND_AARCH64 names one (its folder), else wrappers around the host's gcc
# (x86_64) and aarch64-linux-gnu-gcc that say the lock's identity, with a sysroot folder inside the prefix.
# Checks the install, STOVE.json, the link, a second run, and the refusals.
# MIT, Copyright (c) 2026 AmiCradle Team.
set -u
HERE=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails+1)); }
# fake ARCH HOSTCC: a release tarball W/ARCH.tar.xz and its lock W/ARCH.lock
fake() {
  a=$1; hcc=$2; t=gfopenamigagcc-16.2.0-open9-$a-linux-gnu-glibc2.35-x86_64-linux
  real=$(eval echo "\${USERLAND_$(echo "$a" | tr a-z A-Z):-}")
  if [ -n "$real" ]; then
    mkdir -p "$W/$a"; cp -a "$real" "$W/$a/$t"
  else
    mkdir -p "$W/$a/$t/bin" "$W/$a/$t/sysroot"
    for p in gcc g++; do
      h=$( [ "$p" = gcc ] && echo "$hcc" || echo "${hcc%gcc}g++")
      printf '#!/bin/sh\nD=$(cd "$(dirname "$0")/.." && pwd)\ncase "${1:-}" in --version) echo "%s-linux-gnu-%s (GFOpenAmigaGCC 16.2.0-open9) 16.2.0"; exit 0 ;; -print-sysroot) echo "$D/sysroot"; exit 0 ;; esac\nexec %s "$@"\n' "$a" "$p" "$h" > "$W/$a/$t/bin/$a-linux-gnu-$p"
    done
    ln -s "$(command -v "${hcc%gcc}objdump" || command -v objdump)" "$W/$a/$t/bin/$a-linux-gnu-objdump"
    chmod +x "$W/$a/$t/bin/"*
  fi
  tar -C "$W/$a" -cJf "$W/$a.tar.xz" "$t"
  sed -e "s/^archive_sha256=.*/archive_sha256=$(sha256sum "$W/$a.tar.xz" | cut -d' ' -f1)/" "$HERE/$a.lock" > "$W/$a.lock"
}
run() { lockf=$1; a=$2; shift 2; LINUX_GLIBC_LOCK=$lockf "$HERE/install.sh" "$a" "$@" > "$W/out" 2>&1; }

if [ "$(uname -m)" = x86_64 ] && command -v gcc > /dev/null; then
  fake x86_64 gcc
  S=$W/stoves; D=$S/linux-x86_64-glibc-gcc16-16.2.0-open9
  if run "$W/x86_64.lock" x86_64 "$S" "$W/x86_64.tar.xz"; then ok "x86_64 installs"; else bad "x86_64 installs: $(cat "$W/out")"; fi
  grep -q "a C program runs, needs GLIBC_2" "$W/out" && ok "x86_64: a C program runs within the floor" || bad "x86_64 run: $(cat "$W/out")"
  python3 - "$D/STOVE.json" "$(sha256sum "$W/x86_64.tar.xz" | cut -d' ' -f1)" <<'PY' && ok "STOVE.json" || bad "STOVE.json"
import json, sys
s = json.load(open(sys.argv[1]))
assert s["id"] == "linux-x86_64-glibc-gcc16" and s["release"] == "GFOpenAmigaGCC 16.2.0-open9" and s["glibc"] == "2.35", s
assert s["compilers"]["c"].endswith("/prefix/bin/x86_64-linux-gnu-gcc") and s["compilers"]["c++"].endswith("/prefix/bin/x86_64-linux-gnu-g++"), s
assert s["compilerArchive"]["archiveSha256"] == sys.argv[2] and s["compilerArchive"]["tag"] == "v16.2.0-open9-x86_64-glibc-rc1", s
PY
  [ "$(readlink "$S/linux-x86_64-glibc-gcc16")" = linux-x86_64-glibc-gcc16-16.2.0-open9 ] && ok "linux-x86_64-glibc-gcc16 links to it" || bad "link"
  if run "$W/x86_64.lock" x86_64 "$S" "$W/x86_64.tar.xz" && grep -q "is there already: checking it" "$W/out"; then ok "a second run checks and keeps it"; else bad "second run: $(cat "$W/out")"; fi
  sed 's/^archive_sha256=.*/archive_sha256=00/' "$W/x86_64.lock" > "$W/sha.lock"
  if run "$W/sha.lock" x86_64 "$W/s2" "$W/x86_64.tar.xz"; then bad "takes another SHA-256"; else grep -q refused "$W/out" && ok "refuses another SHA-256" || bad "sha: $(cat "$W/out")"; fi
  [ ! -e "$W/s2/linux-x86_64-glibc-gcc16-16.2.0-open9" ] && ok "nothing left after a refusal" || bad "left a folder after a refusal"
  sed 's/^identity=.*/identity=(GFOpenAmigaGCC 16.2.0-open8)/' "$W/x86_64.lock" > "$W/id.lock"
  if run "$W/id.lock" x86_64 "$W/s3" "$W/x86_64.tar.xz"; then bad "takes a compiler that says another release"; else ok "refuses a compiler that says another release"; fi
  mkdir -p "$W/s4/linux-x86_64-glibc-gcc16-16.2.0-open9"
  if run "$W/x86_64.lock" x86_64 "$W/s4" "$W/x86_64.tar.xz"; then bad "takes over a folder that is not a stove"; else ok "leaves a folder that is not this stove"; fi
  mkdir -p "$W/s5"; ln -s elsewhere "$W/s5/linux-x86_64-glibc-gcc16"
  KEEP_LINK=1 run "$W/x86_64.lock" x86_64 "$W/s5" "$W/x86_64.tar.xz"
  [ "$(readlink "$W/s5/linux-x86_64-glibc-gcc16")" = elsewhere ] && ok "KEEP_LINK keeps the link" || bad "KEEP_LINK"
  if run "$W/x86_64.lock" aarch64 "$W/s6" "$W/x86_64.tar.xz"; then bad "aarch64 takes the x86_64 lock"; else ok "refuses a lock for another target"; fi
  if LINUX_GLIBC_LOCK="$W/x86_64.lock" "$HERE/install.sh" powerpc "$W/s7" > "$W/out" 2>&1; then bad "takes powerpc"; else ok "refuses an ARCH it has no stove for"; fi
else
  echo "SKIP x86_64: not an x86-64 host with gcc"
fi
if [ -n "${USERLAND_AARCH64:-}" ] || command -v aarch64-linux-gnu-gcc > /dev/null; then
  fake aarch64 aarch64-linux-gnu-gcc
  NO_RUN=$( [ -n "${USERLAND_AARCH64:-}" ] && command -v qemu-aarch64 > /dev/null && echo "" || echo 1 )
  if NO_RUN=$NO_RUN run "$W/aarch64.lock" aarch64 "$W/sa" "$W/aarch64.tar.xz"; then ok "aarch64 installs ($(grep 'a C program' "$W/out"))"; else bad "aarch64: $(cat "$W/out")"; fi
  [ "$(readlink "$W/sa/linux-aarch64-glibc-gcc16")" = linux-aarch64-glibc-gcc16-16.2.0-open9 ] && ok "linux-aarch64-glibc-gcc16 links to it" || bad "aarch64 link"
fi
# the shipped locks: each names its own target, release, tag and archive
for a in x86_64 aarch64; do
  L="$HERE/$a.lock"; g() { sed -n "s/^$1=//p" "$L"; }
  if [ "$(g target)" = "$a-linux-gnu" ] && [ "$(g release)" = 16.2.0-open9 ] && [ "$(g identity)" = "(GFOpenAmigaGCC 16.2.0-open9)" ] \
     && [ "$(g tag)" = "v16.2.0-open9-$a-glibc-rc1" ] && [ "$(g archive)" = "gfopenamigagcc-16.2.0-open9-$a-linux-gnu-glibc2.35-x86_64-linux.tar.xz" ] \
     && [ "$(g top)" = "gfopenamigagcc-16.2.0-open9-$a-linux-gnu-glibc2.35-x86_64-linux" ] \
     && [ "$(g archive_url)" = "https://github.com/DalsinAI/gfopengcc/releases/download/$(g tag)/$(g archive)" ] \
     && echo "$(g archive_sha256)" | grep -qE '^[0-9a-f]{64}$' && echo "$(g commit)" | grep -qE '^[0-9a-f]{40}$'; then
    ok "$a.lock names $a's release"
  else
    bad "$a.lock does not name $a's release as it should"
  fi
done
[ "$fails" -eq 0 ] && echo "linux-glibc-gcc16 install test: all passed" || { echo "linux-glibc-gcc16 install test: $fails failed"; exit 1; }
