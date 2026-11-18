#!/bin/sh
# linux-gcc16/install.sh aarch64 (and x86_64, whose test program runs natively) with a made-up release: a tarball whose aarch64-linux-gnu-gcc says the
# lock's identity and hands the work to the host's aarch64-linux-gnu-gcc (gcc-aarch64-linux-gnu), and a
# lock with that tarball's SHA-256. No network, no real stoves folder.
# MIT, Copyright (c) 2026 AmiCradle Team.
set -u
HERE=$(cd "$(dirname "$0")/.." && pwd)
command -v aarch64-linux-gnu-gcc > /dev/null || { echo "SKIP: needs aarch64-linux-gnu-gcc on this host"; exit 0; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails+1)); }
top=gfopenamigagcc-16.2.0-open9-aarch64-linux-gnu-x86_64-linux
mkdir -p "$W/a/$top/bin"
cat > "$W/a/$top/bin/aarch64-linux-gnu-gcc" <<'G'
#!/bin/sh
[ "${1:-}" = --version ] && { echo "aarch64-linux-gnu-gcc (GFOpenAmigaGCC 16.2.0-open9) 16.2.0"; exit 0; }
exec aarch64-linux-gnu-gcc "$@"
G
chmod +x "$W/a/$top/bin/aarch64-linux-gnu-gcc"
tar -C "$W/a" -cJf "$W/good.tar.xz" "$top"
mkdir -p "$W/b/other/bin"; tar -C "$W/b" -cJf "$W/nogcc.tar.xz" other
mklock() { sed -e "s/^archive_sha256=.*/archive_sha256=$(sha256sum "$1" | cut -d' ' -f1)/" "$HERE/aarch64.lock" > "$2"; }
mklock "$W/good.tar.xz" "$W/good.lock"; mklock "$W/nogcc.tar.xz" "$W/nogcc.lock"
run() { lockf=$1; shift; LINUX_GCC_LOCK=$lockf "$HERE/install.sh" aarch64 "$@" > "$W/out" 2>&1; }

S=$W/stoves
if run "$W/good.lock" "$S" "$W/good.tar.xz"; then ok "installs"; else bad "installs: $(cat "$W/out")"; fi
D=$S/linux-aarch64-gcc16-16.2.0-open9
[ -x "$D/prefix/bin/aarch64-linux-gnu-gcc" ] && ok "prefix/bin/aarch64-linux-gnu-gcc" || bad "no prefix/bin/aarch64-linux-gnu-gcc"
python3 - "$D/STOVE.json" "$(sha256sum "$W/good.tar.xz" | cut -d' ' -f1)" <<'PY' && ok "STOVE.json" || bad "STOVE.json"
import json, sys
s = json.load(open(sys.argv[1]))
assert s["id"] == "linux-aarch64-gcc16" and s["release"] == "GFOpenAmigaGCC 16.2.0-open9", s
assert s["target"] == "aarch64-linux-gnu" and s["compilers"]["c"].endswith("/prefix/bin/aarch64-linux-gnu-gcc"), s
assert s["compilerArchive"]["archiveSha256"] == sys.argv[2] and s["compilerArchive"]["tag"] == "v16.2.0-open9-aarch64-rc1", s
PY
[ "$(readlink "$S/linux-aarch64-gcc16")" = linux-aarch64-gcc16-16.2.0-open9 ] && ok "linux-aarch64-gcc16 links to it" || bad "link"
grep -q "a freestanding program" "$W/out" && ok "the freestanding check ran" || bad "no freestanding check: $(cat "$W/out")"
if run "$W/good.lock" "$S" "$W/good.tar.xz" && grep -q "is there already: checking it" "$W/out"; then ok "a second run checks and keeps it"; else bad "second run: $(cat "$W/out")"; fi
# refusals
if run "$W/nogcc.lock" "$W/s2" "$W/good.tar.xz"; then bad "takes an archive with another SHA-256"; else grep -q refused "$W/out" && ok "refuses another SHA-256" || bad "sha: $(cat "$W/out")"; fi
[ ! -e "$W/s2/linux-aarch64-gcc16-16.2.0-open9" ] && ok "nothing left after a refusal" || bad "left a folder after a refusal"
if run "$W/nogcc.lock" "$W/s3" "$W/nogcc.tar.xz"; then bad "takes an archive without the compiler"; else ok "refuses an archive without $top/bin/aarch64-linux-gnu-gcc"; fi
sed 's/^identity=.*/identity=(GFOpenAmigaGCC 16.2.0-open8)/' "$W/good.lock" > "$W/id.lock"
if run "$W/id.lock" "$W/s4" "$W/good.tar.xz"; then bad "takes a compiler that says another release"; else ok "refuses a compiler that says another release"; fi
mkdir -p "$W/s5/linux-aarch64-gcc16-16.2.0-open9"
if run "$W/good.lock" "$W/s5" "$W/good.tar.xz"; then bad "takes over a folder that is not a stove"; else ok "leaves a folder that is not this stove"; fi
mkdir -p "$W/s6"; ln -s elsewhere "$W/s6/linux-aarch64-gcc16"
KEEP_LINK=1 run "$W/good.lock" "$W/s6" "$W/good.tar.xz"
[ "$(readlink "$W/s6/linux-aarch64-gcc16")" = elsewhere ] && ok "KEEP_LINK keeps the link" || bad "KEEP_LINK"
mkdir -p "$W/s7/linux-aarch64-gcc16"
run "$W/good.lock" "$W/s7" "$W/good.tar.xz"
[ -d "$W/s7/linux-aarch64-gcc16" ] && [ ! -L "$W/s7/linux-aarch64-gcc16" ] && ok "a real folder by the name is left" || bad "replaced a folder"
# x86_64: a made-up release from the host's own gcc (its programs run here)
if [ "$(uname -m)" = x86_64 ]; then
  xt=gfopenamigagcc-16.2.0-open9-x86_64-linux-gnu-x86_64-linux
  mkdir -p "$W/x/$xt/bin"
  printf '#!/bin/sh\n[ "${1:-}" = --version ] && { echo "x86_64-linux-gnu-gcc (GFOpenAmigaGCC 16.2.0-open9) 16.2.0"; exit 0; }\nexec gcc "$@"\n' > "$W/x/$xt/bin/x86_64-linux-gnu-gcc"
  chmod +x "$W/x/$xt/bin/x86_64-linux-gnu-gcc"; tar -C "$W/x" -cJf "$W/x.tar.xz" "$xt"
  sed -e "s/^archive_sha256=.*/archive_sha256=$(sha256sum "$W/x.tar.xz" | cut -d' ' -f1)/" -e "s/^target=.*/target=x86_64-linux-gnu/" -e "s/^top=.*/top=$xt/" "$HERE/aarch64.lock" > "$W/x.lock"
  if LINUX_GCC_LOCK="$W/x.lock" "$HERE/install.sh" x86_64 "$W/sx" "$W/x.tar.xz" > "$W/out" 2>&1 && grep -q "a freestanding program runs$" "$W/out"; then ok "x86_64: installs, its program runs"; else bad "x86_64: $(cat "$W/out")"; fi
  [ "$(readlink "$W/sx/linux-x86_64-gcc16")" = linux-x86_64-gcc16-16.2.0-open9 ] && ok "x86_64: linux-x86_64-gcc16 links to it" || bad "x86_64 link"
  if LINUX_GCC_LOCK="$W/good.lock" "$HERE/install.sh" x86_64 "$W/sy" "$W/good.tar.xz" > "$W/out" 2>&1; then bad "x86_64 takes the aarch64 lock"; else ok "refuses a lock for another target"; fi
fi
# powerpc: from the host's powerpc-linux-gnu-gcc, run under qemu-ppc
if command -v powerpc-linux-gnu-gcc > /dev/null; then
  pt=gfopenamigagcc-16.2.0-open9-powerpc-linux-gnu-x86_64-linux
  mkdir -p "$W/p/$pt/bin"
  printf '#!/bin/sh\n[ "${1:-}" = --version ] && { echo "powerpc-linux-gnu-gcc (GFOpenAmigaGCC 16.2.0-open9) 16.2.0"; exit 0; }\nexec powerpc-linux-gnu-gcc "$@"\n' > "$W/p/$pt/bin/powerpc-linux-gnu-gcc"
  chmod +x "$W/p/$pt/bin/powerpc-linux-gnu-gcc"; tar -C "$W/p" -cJf "$W/p.tar.xz" "$pt"
  sed -e "s/^archive_sha256=.*/archive_sha256=$(sha256sum "$W/p.tar.xz" | cut -d' ' -f1)/" -e "s/^target=.*/target=powerpc-linux-gnu/" -e "s/^top=.*/top=$pt/" "$HERE/aarch64.lock" > "$W/p.lock"
  if LINUX_GCC_LOCK="$W/p.lock" "$HERE/install.sh" powerpc "$W/sp" "$W/p.tar.xz" > "$W/out" 2>&1 && grep -q "a freestanding program" "$W/out"; then ok "powerpc: installs ($(grep 'freestanding' "$W/out"))"; else bad "powerpc: $(cat "$W/out")"; fi
fi
# the shipped locks: each names its own target, release, tag and archive
for a in aarch64 x86_64 powerpc; do
  L="$HERE/$a.lock"; g() { sed -n "s/^$1=//p" "$L"; }
  ar=$(g archive); t=$(g tag)
  if [ "$(g target)" = "$a-linux-gnu" ] && [ "$(g release)" = 16.2.0-open9 ] && [ "$(g identity)" = "(GFOpenAmigaGCC 16.2.0-open9)" ] \
     && [ "$t" = "v16.2.0-open9-$a-rc1" ] && [ "$ar" = "gfopenamigagcc-16.2.0-open9-$a-linux-gnu-x86_64-linux.tar.xz" ] \
     && [ "$(g top)" = "${ar%.tar.xz}" ] && [ "$(g archive_url)" = "https://github.com/DalsinAI/gfopengcc/releases/download/$t/$ar" ] \
     && g archive_sha256 | grep -qE '^[0-9a-f]{64}$' && g source_sha256 | grep -qE '^[0-9a-f]{64}$' && g commit | grep -qE '^[0-9a-f]{40}$'
  then ok "$a.lock"; else bad "$a.lock"; fi
done
if "$HERE/install.sh" ppc "$W/sz" > "$W/out" 2>&1; then bad "takes ARCH ppc"; else ok "refuses another ARCH"; fi
[ $fails -eq 0 ] && echo "test_install: all passed" || { echo "test_install: $fails failed"; exit 1; }
