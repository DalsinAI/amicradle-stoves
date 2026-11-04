#!/bin/sh
# install-gfopenasm.sh on a pretend stove: install, the names work and are gfasm, README.txt and STOVE.json
# say so, the backup holds what was there; installing again over gfopenasm (an update) says it replaced
# gfopenasm; --revert of each install puts back what was there byte for byte.
#   sh os32-gcc16/asm/test_install.sh [TARBALL]     (downloads the lock's release when not given)
# The pretend vasm is a shell script: no vasm is needed. MIT, Copyright (c) 2026 AmiCradle Team.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
S=$T/stove; mkdir -p "$S/prefix/bin"
printf '#!/bin/sh\necho "pretend vasm"\n' > "$S/prefix/bin/vasmm68k_mot"; chmod 755 "$S/prefix/bin/vasmm68k_mot"
printf 'A stove\n\nvasmm68k_mot (prefix/bin): vasm 2.0f from somewhere, built by\nbuild-vasm.sh. vasm is free for non-commercial use, not open\nsource: a build tool here only, never in a release.\n' > "$S/README.txt"
printf '{\n  "schema": 1,\n  "id": "pretend"\n}\n' > "$S/STOVE.json"
cp -rp "$S" "$T/before"
A=${1:-}
if [ -z "$A" ]; then A=$T/gfopenasm.tar.xz; curl -fsSL -o "$A" "$(sed -n 's/^url=//p' "$HERE/gfopenasm.lock")"; fi
ORACLE=$T/no-oracle sh "$HERE/install-gfopenasm.sh" "$S" "$A"
fail() { echo "FAIL: $*"; exit 1; }
want=$(sed -n 's/^gfasm_sha256=//p' "$HERE/gfopenasm.lock")
for n in gfasm vasmm68k_mot; do [ "$(sha256sum < "$S/prefix/bin/$n" | cut -d' ' -f1)" = "$want" ] || fail "$n is not the lock's gfasm"; done
printf ' moveq #1,d0\n rts\n' > "$T/a.s"
"$S/prefix/bin/vasmm68k_mot" -quiet -Fbin -o "$T/a.bin" "$T/a.s"
[ "$(od -An -tx1 "$T/a.bin" | tr -d ' \n')" = 70014e75 ] || fail "vasmm68k_mot -Fbin gave $(od -An -tx1 "$T/a.bin")"
grep -q '^Assembler (prefix/bin): gfopenasm' "$S/README.txt" || fail "README.txt has no gfopenasm note"
! grep -q 'vasmm68k_mot (prefix/bin): vasm' "$S/README.txt" || fail "README.txt still says vasm"
python3 -c "import json,sys; d=json.load(open(sys.argv[1])); assert d['assembler']['name']=='gfopenasm', d" "$S/STOVE.json" || fail "STOVE.json"
python3 -c "import json,sys; d=json.load(open(sys.argv[1])); assert d['assembler']['replaced'].startswith('vasm'), d" "$S/STOVE.json" || fail "STOVE.json replaced"
BAK=$(ls -d "$S"/asm-before-gfopenasm-*.bak)
cmp -s "$BAK/bin/vasmm68k_mot" "$T/before/prefix/bin/vasmm68k_mot" || fail "the backup has not the old vasmm68k_mot"
# an update: install again over the gfopenasm just installed
mkdir "$T/mid"; cp -p "$S/README.txt" "$S/STOVE.json" "$T/mid/"; cp -p "$S/prefix/bin/gfasm" "$S/prefix/bin/vasmm68k_mot" "$T/mid/"
sleep 1
ORACLE=$T/no-oracle sh "$HERE/install-gfopenasm.sh" "$S" "$A"
ver=$(sed -n 's/^version=//p' "$HERE/gfopenasm.lock")
python3 -c "import json,sys; d=json.load(open(sys.argv[1])); assert d['assembler']['replaced']=='gfopenasm '+sys.argv[2], d" "$S/STOVE.json" "$ver" || fail "STOVE.json after an update"
grep -q "It replaced gfopenasm $ver;" "$S/README.txt" || fail "README.txt after an update"
[ "$(grep -c '^Assembler (prefix/bin): gfopenasm' "$S/README.txt")" = 1 ] || fail "README.txt has more than one gfopenasm note"
BAK2=$(ls -d "$S"/asm-before-gfopenasm-*.bak | grep -v "^$BAK\$")
for n in gfasm vasmm68k_mot; do cmp -s "$BAK2/bin/$n" "$T/mid/$n" || fail "the update's backup has not the old $n"; done
sh "$HERE/install-gfopenasm.sh" --revert "$S" "$BAK2"
for n in gfasm vasmm68k_mot; do cmp -s "$S/prefix/bin/$n" "$T/mid/$n" || fail "$n not put back after the update"; done
for f in README.txt STOVE.json; do cmp -s "$S/$f" "$T/mid/$f" || fail "$f not put back after the update"; done
sh "$HERE/install-gfopenasm.sh" --revert "$S" "$BAK"
[ ! -e "$S/prefix/bin/gfasm" ] || fail "gfasm left after --revert"
for f in prefix/bin/vasmm68k_mot README.txt STOVE.json; do cmp -s "$S/$f" "$T/before/$f" || fail "$f not put back"; done
echo "test_install: all passed"
