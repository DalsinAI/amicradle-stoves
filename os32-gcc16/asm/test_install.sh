#!/bin/sh
# install-gfopenasm.sh on a pretend stove: install, the names work and are gfasm, README.txt and STOVE.json
# say so, the backup holds what was there, --revert puts it back byte for byte.
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
ORACLE=$T/no-oracle sh "$HERE/install-gfopenasm.sh" "$S" ${1:+"$1"}
fail() { echo "FAIL: $*"; exit 1; }
want=$(sed -n 's/^gfasm_sha256=//p' "$HERE/gfopenasm.lock")
for n in gfasm vasmm68k_mot; do [ "$(sha256sum < "$S/prefix/bin/$n" | cut -d' ' -f1)" = "$want" ] || fail "$n is not the lock's gfasm"; done
printf ' moveq #1,d0\n rts\n' > "$T/a.s"
"$S/prefix/bin/vasmm68k_mot" -quiet -Fbin -o "$T/a.bin" "$T/a.s"
[ "$(od -An -tx1 "$T/a.bin" | tr -d ' \n')" = 70014e75 ] || fail "vasmm68k_mot -Fbin gave $(od -An -tx1 "$T/a.bin")"
grep -q '^Assembler (prefix/bin): gfopenasm' "$S/README.txt" || fail "README.txt has no gfopenasm note"
! grep -q 'vasmm68k_mot (prefix/bin): vasm' "$S/README.txt" || fail "README.txt still says vasm"
python3 -c "import json,sys; d=json.load(open(sys.argv[1])); assert d['assembler']['name']=='gfopenasm', d" "$S/STOVE.json" || fail "STOVE.json"
BAK=$(ls -d "$S"/asm-before-gfopenasm-*.bak)
cmp -s "$BAK/bin/vasmm68k_mot" "$T/before/prefix/bin/vasmm68k_mot" || fail "the backup has not the old vasmm68k_mot"
sh "$HERE/install-gfopenasm.sh" --revert "$S" "$BAK"
[ ! -e "$S/prefix/bin/gfasm" ] || fail "gfasm left after --revert"
for f in prefix/bin/vasmm68k_mot README.txt STOVE.json; do cmp -s "$S/$f" "$T/before/$f" || fail "$f not put back"; done
echo "test_install: all passed"
