#!/bin/sh
# Host test for os32-gcc16/upgrade.sh and identity/build-amiga.sh, on a pretend live stove (an open3 one as the
# Cradle machine's is laid out: STOVE.json with a kit, README.txt, kits/, compat/, and a prefix whose compiler
# says open3, with ndk-include as a link, ndk13-include, openndk-fd and port-deps).
#   os32-gcc16/tests/upgrade/test_upgrade.sh ARCHIVE [SCRATCH]
# ARCHIVE: the release's x86-64 toolchain (toolchain.lock's archive_url).
# MIT, Copyright (c) 2026 AmiCradle Team.
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
ARCHIVE=${1:?the release archive}
S=${2:-$(mktemp -d)}
fails=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi; }

rm -rf "$S/stoves"; mkdir -p "$S/stoves/os32-gcc16/prefix/bin" "$S/stoves/os32-gcc16/prefix/m68k-amigaos" "$S/stoves/openndk/Include_H"
L="$S/stoves/os32-gcc16"
cat > "$L/prefix/bin/m68k-amigaos-gcc" <<'G'
#!/bin/sh
echo "m68k-amigaos-gcc (OpenAmigaGCC 16.2.0-open3) 16.2.0b 20260930174807"
G
chmod +x "$L/prefix/bin/m68k-amigaos-gcc"
ln -s ../../../openndk/Include_H "$L/prefix/m68k-amigaos/ndk-include"
mkdir -p "$L/prefix/m68k-amigaos/ndk13-include/exec" "$L/prefix/m68k-amigaos/openndk-fd" "$L/prefix/m68k-amigaos/port-deps/lib" "$L/kits" "$L/compat" "$L/ndk"
echo "zlib" > "$L/prefix/m68k-amigaos/port-deps/lib/libz.a"
echo "kit" > "$L/kits/OpenGPU-SDK-0.7.tar.gz"
echo "compat" > "$L/compat/libos32compat.a"
cat > "$L/STOVE.json" <<'J'
{"schema": 1, "id": "os32-gcc16", "release": "OpenAmigaGCC 16.2.0-open3",
 "compilerArchive": {"name": "openamigagcc-16.2.0-open3-x86_64-linux.tar.xz", "sha256": "9fcc136ab59e3bb5b91d2764d0bf290b709d72d7380be4ce0cdf005edf8eff21"},
 "kits": [{"name": "OpenGPU-SDK", "version": "0.7", "archive": "kits/OpenGPU-SDK-0.7.tar.gz"}]}
J
echo "OS 3.2 stove, OpenAmigaGCC 16.2.0-open3 (19 October 2026)" > "$L/README.txt"
before=$(cd "$L" && find . | sort | md5sum)

# the identity check on the open3 stove: it fails, saying so
out=$(STOVE="$L" OUT="$S/id-old" sh "$HERE/identity/build-amiga.sh" 2>&1); rc=$?
check "identity: an open3 stove fails the check" '[ $rc -ne 0 ] && echo "$out" | grep -q "NOT 16.2.0-open4"'

# a wrong archive is refused, and nothing is made
printf 'not the release' > "$S/wrong.tar.xz"
out=$(sh "$HERE/upgrade.sh" "$S/stoves" "$S/wrong.tar.xz" 2>&1); rc=$?
check "upgrade: an archive with another SHA-256 is refused" '[ $rc -ne 0 ] && echo "$out" | grep -q refused && [ ! -e "$S/stoves/.next/os32-gcc16" ]'

# the release
out=$(sh "$HERE/upgrade.sh" "$S/stoves" "$ARCHIVE" 2>&1); rc=$?
echo "$out" | sed 's/^/     /' | tail -16
N="$S/stoves/.next/os32-gcc16"
check "upgrade: done" '[ $rc -eq 0 ]'
check "the new compiler says open4" '"$N/prefix/bin/m68k-amigaos-gcc" --version | head -1 | grep -qF "(OpenAmigaGCC 16.2.0-open4)"'
check "the live stove is untouched" '[ "$(cd "$L" && find . | sort | md5sum)" = "$before" ]'
check "ndk-include carried as the same link" '[ "$(readlink "$N/prefix/m68k-amigaos/ndk-include")" = "../../../openndk/Include_H" ]'
check "ndk13-include, openndk-fd and port-deps carried" '[ -d "$N/prefix/m68k-amigaos/ndk13-include/exec" ] && [ -d "$N/prefix/m68k-amigaos/openndk-fd" ] && [ -f "$N/prefix/m68k-amigaos/port-deps/lib/libz.a" ]'
check "the release's own files kept (libnix, sys-include)" '[ -d "$N/prefix/m68k-amigaos/libnix" ] && [ -d "$N/prefix/m68k-amigaos/sys-include" ]'
check "kits, compat and ndk carried" '[ -f "$N/kits/OpenGPU-SDK-0.7.tar.gz" ] && [ -f "$N/compat/libos32compat.a" ] && [ -d "$N/ndk" ]'
check "STOVE.json: open4, its archive and hash, the kit kept" 'python3 -c "
import json,sys; d=json.load(open(sys.argv[1]))
assert d[\"release\"]==\"OpenAmigaGCC 16.2.0-open4\", d
assert d[\"compilerArchive\"][\"sha256\"]==\"495319a2ffd803278f8827cad70074029c7aa9ecbe05d037e8646ba43ab94ab2\"
assert d[\"kits\"][0][\"name\"]==\"OpenGPU-SDK\" and d[\"upgraded\"][\"from\"]==\"OpenAmigaGCC 16.2.0-open3\"" "$N/STOVE.json"'
check "README.txt: the note on top, the old one kept" 'head -1 "$N/README.txt" | grep -q "16.2.0-open4" && grep -q "16.2.0-open3 (19 October 2026)" "$N/README.txt"'
out=$(STOVE="$N" OUT="$S/id-new" sh "$HERE/identity/build-amiga.sh" 2>&1); rc=$?
check "identity: the new stove passes and builds a hunk program" '[ $rc -eq 0 ] && [ "$(head -c 4 "$S/id-new/identity" | od -An -tx1 | tr -d " ")" = "000003f3" ]'
out=$(sh "$HERE/upgrade.sh" "$S/stoves" "$ARCHIVE" 2>&1); rc=$?
check "upgrade: a second run with .next there refuses" '[ $rc -ne 0 ] && echo "$out" | grep -q "there already"'
[ $fails -eq 0 ] && echo PASS || { echo "FAIL ($fails)"; exit 1; }
