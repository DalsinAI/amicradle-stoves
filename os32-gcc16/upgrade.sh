#!/bin/sh
# Builds the next os32-gcc16 stove from the release in toolchain.lock, beside the live one, never in place of it
# (README: "a stove is added beside the ones that work, never in place of them").
#
#   os32-gcc16/upgrade.sh STOVES ARCHIVE
#
# STOVES is the stoves folder (~/AmiCradle/stoves, Settings > Folders' "Stoves"); ARCHIVE the release's
# x86-64 toolchain (toolchain.lock's archive_url). It:
#   1. refuses an archive whose SHA-256 isn't toolchain.lock's;
#   2. makes STOVES/.next/os32-gcc16 (a stoves folder of its own, so the AmiCradle scripts below can work on
#      it by --stoves / path): everything of the live STOVES/os32-gcc16 but its prefix, copied; the release
#      unpacked as the new prefix; and, from the live prefix's m68k-amigaos, the parts that aren't the
#      compiler's and that the release doesn't have (ndk, ndk-include and its .vendor, ndk13-include,
#      openndk-fd, port-deps), copied as they are (links stay links);
#   3. writes STOVE.json's release and compilerArchive, keeping its kits, and puts a note on README.txt;
#   4. checks the new compiler says the release, and that a C program builds and links with it.
# The live stove is only read. What to run next (kits, OpenNDK, the swap) is printed at the end, and in
# os32-gcc16/README.md.
# MIT, Copyright (c) 2026 AmiCradle Team.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
LOCK=${OS32_GCC16_LOCK:-"$HERE/toolchain.lock"}   # the variable only for tests/upgrade
STOVES=${1:?usage: upgrade.sh STOVES ARCHIVE}
ARCHIVE=${2:?usage: upgrade.sh STOVES ARCHIVE}
lock() { sed -n "s/^$1=//p" "$LOCK"; }
release=$(lock release); want=$(lock identity); top=$(lock top)
# The name the release goes by, from its identity: "GFOpenAmigaGCC" from open5, "OpenAmigaGCC" up to open4.
name=$(printf %s "$want" | sed -n 's/^(\(.*\) [^ ]*)$/\1/p'); name=${name:-GFOpenAmigaGCC}
LIVE="$STOVES/os32-gcc16"
NEXT_ROOT="$STOVES/.next"
NEXT="$NEXT_ROOT/os32-gcc16"
[ -d "$LIVE/prefix" ] || { echo "no live stove at $LIVE (prefix/ missing)"; exit 2; }
[ ! -e "$NEXT" ] || { echo "$NEXT is there already: move it away first"; exit 2; }

echo "== 1. the archive"
got=$(sha256sum "$ARCHIVE" | cut -d' ' -f1)
if [ "$got" != "$(lock archive_sha256)" ]; then
    echo "$ARCHIVE: SHA-256 $got is not $release's ($(lock archive_sha256)): refused"
    exit 1
fi
echo "$ARCHIVE: $release ($got)"

echo "== 2. $NEXT"
mkdir -p "$NEXT_ROOT"
TMP=$(mktemp -d "$NEXT_ROOT/.unpack.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
tar -C "$TMP" -xJf "$ARCHIVE"
# Its folder is toolchain.lock's top; a release named the other way (openamigagcc- up to open4,
# gfopenamigagcc- from open5) is taken too.
if [ ! -x "$TMP/$top/bin/m68k-amigaos-gcc" ]; then
    for t in "gfopenamigagcc-$release-x86_64-linux" "openamigagcc-$release-x86_64-linux"; do
        [ -x "$TMP/$t/bin/m68k-amigaos-gcc" ] && { top=$t; break; }
    done
fi
[ -x "$TMP/$top/bin/m68k-amigaos-gcc" ] || { echo "the archive has no $top/bin/m68k-amigaos-gcc"; exit 1; }
mkdir "$NEXT"
for f in "$LIVE"/* "$LIVE"/.[!.]*; do
    [ -e "$f" ] || [ -L "$f" ] || continue
    case "$(basename "$f")" in prefix) continue ;; esac
    cp -a "$f" "$NEXT/"
done
mv "$TMP/$top" "$NEXT/prefix"
carried=""
for d in ndk ndk-include ndk-include.vendor ndk13-include openndk-fd port-deps; do
    src="$LIVE/prefix/m68k-amigaos/$d"
    dst="$NEXT/prefix/m68k-amigaos/$d"
    if { [ -e "$src" ] || [ -L "$src" ]; } && [ ! -e "$dst" ] && [ ! -L "$dst" ]; then
        cp -a "$src" "$dst"
        carried="$carried $d"
    fi
done
echo "carried from the live prefix:${carried:- nothing}"

echo "== 3. STOVE.json and README.txt"
python3 - "$NEXT" "$release" "$(lock archive)" "$(lock archive_sha256)" "$(lock tag)" "$(lock commit)" "$name" <<'PY'
import json, sys, time
from pathlib import Path
stove, release, archive, sha, tag, commit, name = sys.argv[1:]
p = Path(stove) / "STOVE.json"
d = json.loads(p.read_text(encoding="utf-8")) if p.is_file() else {"schema": 1, "id": "os32-gcc16"}
before = d.get("release")
d["release"] = name + " " + release
d["compilerArchive"] = {"name": archive, "sha256": sha, "tag": tag, "commit": commit}
d["upgraded"] = {"from": before, "at": time.strftime("%Y%m%dT%H%M%SZ", time.gmtime()), "by": "amicradle-stoves os32-gcc16/upgrade.sh"}
p.write_text(json.dumps(d, indent=2) + "\n", encoding="utf-8")
r = Path(stove) / "README.txt"
old = r.read_text(encoding="utf-8") if r.is_file() else ""
head = (f"OS 3.2 stove, {name} {release} ({time.strftime('%d %B %Y')})\n"
        + "=" * 60 + "\n\n"
        + f"Made by amicradle-stoves os32-gcc16/upgrade.sh from DalsinAI/gfopengcc {tag} ({commit[:7]}),\n"
        + f"{archive} (sha256 {sha[:8]}...{sha[-5:]}), with everything else carried from the\n"
        + f"stove before it ({before}). Its kits and OpenNDK are put back by os32_stove.py --reapply-kits and\n"
        + "stove_openndk.py use (os32-gcc16/README.md). The stove before it is in stoves/archive/.\n\n"
        + "-" * 67 + "\n\n")
r.write_text(head + old, encoding="utf-8")
PY
echo "STOVE.json: $name $release"

echo "== 4. the new compiler"
STOVE="$NEXT" OUT="$TMP/identity" sh "$HERE/identity/build-amiga.sh"

cat <<EOF

The next stove is in $NEXT; the live one is untouched. Then, on this machine
(AMICRADLE: the AmiCradle install or checkout with scripts/):
  python3 \$AMICRADLE/scripts/os32_stove.py --reapply-kits --stoves "$NEXT_ROOT" --stove os32-gcc16
  python3 \$AMICRADLE/scripts/stove_openndk.py use "$NEXT"
  mkdir -p "$STOVES/archive"
  mv "$LIVE" "$STOVES/archive/os32-gcc16-before-$release-\$(date +%Y%m%dT%H%M%S)" && mv "$NEXT" "$LIVE"
and prove it with Cradle's stove_build: os32-gcc16, DalsinAI/amicradle-stoves, target os32-gcc16/identity.
EOF
