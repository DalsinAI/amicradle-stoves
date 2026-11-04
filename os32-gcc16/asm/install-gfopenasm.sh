#!/bin/sh
# Puts gfopenasm (gfasm) into a stove in place of vasm: gfasm and, for each of gfopenasm.lock's names
# (vasmm68k_mot), a copy of it in STOVE/prefix/bin. gfasm takes its CPU and syntax from the name it is
# called by, so the stove's builds call it as they called vasm.
#
#   os32-gcc16/asm/install-gfopenasm.sh STOVE [TARBALL]     install
#   os32-gcc16/asm/install-gfopenasm.sh --revert STOVE BAK  put back what an install moved to BAK
#
# TARBALL is the release archive, downloaded from the lock's url when not given; it must have the lock's
# SHA-256, and its gfasm the lock's gfasm_sha256. What the stove had under those names (vasm) is moved,
# with the stove's README.txt and STOVE.json as they were, to STOVE/asm-before-gfopenasm-<UTC time>.bak/.
# Then each name assembles a small 68k test in hunk, hunkexe and bin; when the vasm 2.0f oracle is
# there (ORACLE=, default ~/AmiCradle/stoves/vasm-oracles/2.0f/bin) its output must be the same bytes.
# The stove's README.txt and STOVE.json ("assembler") say what is installed and what it replaced: vasm,
# or the gfopenasm an earlier install put there (an update is the same command with a newer lock).
# vasm itself stays in vasm-oracles/ as the comparison oracle (../../vasm-oracles).
# This script is MIT, Copyright (c) 2026 AmiCradle Team.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
lock() { sed -n "s/^$1=//p" "$HERE/gfopenasm.lock"; }

if [ "${1:-}" = --revert ]; then
  STOVE=${2:?usage: install-gfopenasm.sh --revert STOVE BAK}; BAK=${3:?usage: install-gfopenasm.sh --revert STOVE BAK}
  [ -f "$BAK/MOVED" ] || { echo "$BAK has no MOVED list: not an install's backup"; exit 2; }
  rm -f "$STOVE/prefix/bin/gfasm"
  while read -r n; do rm -f "$STOVE/prefix/bin/$n"; [ ! -e "$BAK/bin/$n" ] || cp -p "$BAK/bin/$n" "$STOVE/prefix/bin/$n"; done < "$BAK/MOVED"
  for f in README.txt STOVE.json; do [ ! -f "$BAK/$f" ] || cp -p "$BAK/$f" "$STOVE/$f"; done
  echo "put back from $BAK: $(tr '\n' ' ' < "$BAK/MOVED")"
  exit 0
fi

STOVE=${1:?usage: install-gfopenasm.sh STOVE [TARBALL]}
B=$STOVE/prefix/bin
[ -d "$B" ] || { echo "$STOVE has no prefix/bin"; exit 2; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
A=${2:-}
if [ -z "$A" ]; then A=$T/gfopenasm.tar.xz; curl -fsSL -o "$A" "$(lock url)"; fi
got=$(sha256sum "$A" | cut -d' ' -f1)
[ "$got" = "$(lock sha256)" ] || { echo "$A: SHA-256 $got is not gfopenasm $(lock version)'s ($(lock sha256)): refused"; exit 1; }
tar -C "$T" -xJf "$A"
G=$(find "$T" -type f -name gfasm | head -n 1)
[ -n "$G" ] && [ "$(sha256sum "$G" | cut -d' ' -f1)" = "$(lock gfasm_sha256)" ] || { echo "the archive's gfasm is not the lock's"; exit 1; }
NAMES=$(lock names | tr ',' ' ')

# the test, assembled by every name before anything in the stove changes
cat > "$T/t.s" <<'EOF'
	section	code,code
start:	moveq	#0,d0
	lea	msg(pc),a0
	move.l	4.w,a6
	tst.b	(a0)+
	bne.s	start
	movem.l	d2-d7/a2-a6,-(sp)
	jsr	-552(a6)
	move.l	ptr,d1
	rts
msg:	dc.b	"gfopenasm",0
	even
	section	data,data
ptr:	dc.l	start,msg
EOF
cat > "$T/b.s" <<'EOF'
	org	$f80000
	dc.w	$1114,$4ef9
	dc.l	go
go:	lea	$dff000,a5
	move.w	#$7fff,$9a(a5)
	bra.s	go
EOF
ORACLE=${ORACLE:-$HOME/AmiCradle/stoves/vasm-oracles/2.0f/bin}
mkdir -p "$T/bin"
for n in $NAMES; do
  cp "$G" "$T/bin/$n"; chmod 755 "$T/bin/$n"
  for f in hunk hunkexe bin; do
    s=$T/t.s; [ $f != bin ] || s=$T/b.s
    "$T/bin/$n" -quiet -F$f -o "$T/$n.$f" "$s" || { echo "$n -F$f failed"; exit 1; }
    [ -s "$T/$n.$f" ] || { echo "$n -F$f made nothing"; exit 1; }
    if [ -x "$ORACLE/$n" ]; then
      "$ORACLE/$n" -quiet -F$f -o "$T/$n.$f.oracle" "$s" || { echo "the oracle $ORACLE/$n failed on -F$f"; exit 1; }
      cmp -s "$T/$n.$f" "$T/$n.$f.oracle" || { echo "$n -F$f differs from the oracle $ORACLE/$n: refused"; exit 1; }
    fi
  done
done

BAK=$STOVE/asm-before-gfopenasm-$(date -u +%Y%m%dT%H%M%SZ).bak
mkdir -p "$BAK/bin"; : > "$BAK/MOVED"
for f in README.txt STOVE.json; do [ ! -f "$STOVE/$f" ] || cp -p "$STOVE/$f" "$BAK/$f"; done
for n in gfasm $NAMES; do
  echo "$n" >> "$BAK/MOVED"
  [ ! -e "$B/$n" ] || mv "$B/$n" "$BAK/bin/$n"
done
install -m 755 "$G" "$B/gfasm"
for n in $NAMES; do install -m 755 "$G" "$B/$n"; done

python3 - "$STOVE" "$(lock version)" "$(lock tag)" "$(lock commit)" "$(lock url)" "$(lock sha256)" "$(lock gfasm_sha256)" "$NAMES" "$BAK" <<'EOF'
import json, os, re, sys, time
stove, version, tag, commit, url, sha, gsha, names, bak = sys.argv[1:]
j = os.path.join(stove, "STOVE.json")
old = (json.load(open(j)).get("assembler") or {}) if os.path.exists(j) else {}
replaced = f"gfopenasm {old['version']}" if old.get("name") == "gfopenasm" else "vasm 2.0f (vasmm68k_mot)"
note = (f"\nAssembler (prefix/bin): gfopenasm {version} (DalsinAI/gfopenasm {tag}, {commit[:7]}, MIT), the static\n"
        f"Linux x86-64 gfasm from {url}\n(SHA-256 {sha}), as gfasm and as {', '.join(names.split())},\n"
        f"installed by amicradle-stoves os32-gcc16/asm/install-gfopenasm.sh. It replaced {replaced}; what was\n"
        f"there is in {os.path.basename(bak)}/. vasm stays only as the test oracle in stoves/vasm-oracles/.\n")
r = os.path.join(stove, "README.txt")
if os.path.exists(r):
    t = open(r).read()
    t = re.sub(r"\nvasmm68k_mot \(prefix/bin\): vasm .*?never in a release\.\n", "\n", t, flags=re.S)
    t = re.sub(r"\nAssembler \(prefix/bin\): gfopenasm .*?test oracle in stoves/vasm-oracles/\.\n", "\n", t, flags=re.S)
    open(r, "w").write(t.rstrip("\n") + "\n" + note)
if os.path.exists(j):
    d = json.load(open(j))
    d["assembler"] = {"name": "gfopenasm", "version": version, "tag": tag, "commit": commit,
                      "archive": url, "sha256": sha, "gfasm_sha256": gsha, "names": ["gfasm"] + names.split(),
                      "replaced": replaced, "backup": os.path.basename(bak),
                      "installed": time.strftime("%Y%m%dT%H%M%SZ", time.gmtime()),
                      "by": "amicradle-stoves os32-gcc16/asm/install-gfopenasm.sh"}
    open(j, "w").write(json.dumps(d, indent=2) + "\n")
EOF
for n in $NAMES; do "$B/$n" -quiet -Fhunk -o "$T/check.o" "$T/t.s" && cmp -s "$T/check.o" "$T/$n.hunk" || { echo "$B/$n does not work"; exit 1; }; done
echo "gfopenasm $(lock version) in $B: gfasm $NAMES (backup: $BAK)"
