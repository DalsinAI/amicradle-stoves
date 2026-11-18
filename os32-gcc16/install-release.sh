#!/bin/bash
# Puts toolchain.lock's release in as a machine's os32-gcc16 stove, every step of README.md's recipe in one go,
# and keeps the stove it replaces beside it.
#
#   os32-gcc16/install-release.sh HOST STOVES APP [--swap]
#
# HOST is the machine this is meant for (the script stops on any other: `hostname -s` must say it); STOVES the
# stoves folder (~/AmiCradle/kitchen/stoves on daletop, ~/AmiCradle/stoves on amigachromebuild); APP an
# amicradle checkout or installed app (its scripts/kitchen/os32_stove.py and stove_openndk.py).
#
#   1. downloads the lock's archive into STOVES/.downloads (kept for the next time), unless it is there;
#   2. upgrade.sh: STOVES/.next/os32-gcc16 from the verified archive and everything of the live stove but its
#      compiler (the live stove is only read);
#   3. copies over what the live prefix has and the release hasn't (rsync --ignore-existing: the network, AHI
#      and CGX headers, gfmalloc, port libraries), and the live specs' own blocks (specs_merge.py);
#   4. puts the recorded kits back (os32_stove.py --reapply-kits) and the OpenNDK (stove_openndk.py use);
#   5. checks the new compiler says the lock's release and builds and links a C program (identity/build-amiga.sh),
#      and that its libpthread.a is the release's;
# and, only with --swap and only while no m68k-amigaos compiler is running on the machine:
#   6. moves the live stove to STOVES/os32-gcc16-<its release>-kept-<UTC date>, the next one in its place, points
#      the old release's name links (os32-gcc16-open8, os32-gcc16-16.2.0-open8) at the kept folder, and makes the
#      new release's (os32-gcc16-open9, os32-gcc16-16.2.0-open9) point at os32-gcc16.
# To go back: `mv os32-gcc16 os32-gcc16-failed && mv os32-gcc16-<old>-kept-<date> os32-gcc16`.
# Without --swap it stops after 5, the next stove ready in .next. Run again after a failure: it starts over.
# MIT, Copyright (c) 2026 AmiCradle Team.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
LOCK=${OS32_GCC16_LOCK:-"$HERE/toolchain.lock"}
HOST=${1:?usage: install-release.sh HOST STOVES APP [--swap]}
STOVES=${2:?usage: install-release.sh HOST STOVES APP [--swap]}
APP=${3:?usage: install-release.sh HOST STOVES APP [--swap]}
SWAP=${4:-}
lock() { sed -n "s/^$1=//p" "$LOCK"; }
[ "$(hostname -s)" = "$HOST" ] || { echo "this is $(hostname -s), not $HOST: stopped"; exit 2; }
STOVES=$(cd "$STOVES" && pwd)
LIVE="$STOVES/os32-gcc16"; NEXT="$STOVES/.next/os32-gcc16"
release=$(lock release); n=${release##*-}            # 16.2.0-open9, open9
archive=$(lock archive); url=$(lock archive_url)
OS32=$APP/scripts/kitchen/os32_stove.py; NDK=$APP/scripts/kitchen/stove_openndk.py
[ -f "$OS32" ] && [ -f "$NDK" ] || { echo "$APP has no scripts/kitchen/os32_stove.py and stove_openndk.py"; exit 2; }
old=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("release",""))' "$LIVE/STOVE.json")
old=${old##* }                                         # 16.2.0-open8
[ "$old" != "$release" ] || { echo "$LIVE is $release already"; exit 0; }
echo "$HOST: $LIVE is $old; installing $release ($(lock tag))"

echo "== 1. the archive"
mkdir -p "$STOVES/.downloads"
A="$STOVES/.downloads/$archive"
if [ ! -f "$A" ] || [ "$(sha256sum "$A" | cut -d' ' -f1)" != "$(lock archive_sha256)" ]; then
    curl -fsSL -o "$A.part" "$url" && mv "$A.part" "$A"
fi

echo "== 2. upgrade.sh"
rm -rf "$STOVES/.next/os32-gcc16"
OS32_GCC16_LOCK="$LOCK" sh "$HERE/upgrade.sh" "$STOVES" "$A"

echo "== 3. what the live prefix adds"
rsync -a --ignore-existing "$LIVE/prefix/" "$NEXT/prefix/"
SPECS=prefix/lib/gcc/m68k-amigaos/16.2.0b/specs
[ -f "$LIVE/$SPECS" ] && [ -f "$NEXT/$SPECS" ] && python3 "$HERE/specs_merge.py" "$LIVE/$SPECS" "$NEXT/$SPECS"

echo "== 4. kits and OpenNDK"
python3 "$OS32" --reapply-kits --live-stove --stoves "$STOVES/.next" --stove os32-gcc16   # .next is under STOVES
NDKCO="$STOVES/openndk"                          # daletop's checkout; else stove_openndk.py's own default
if [ -d "$NDKCO/OpenNDK" ]; then python3 "$NDK" --checkout "$NDKCO" use "$NEXT"; else python3 "$NDK" use "$NEXT"; fi

echo "== 5. checks"
OS32_GCC16_LOCK="$LOCK" STOVE="$NEXT" OUT="$STOVES/.next/identity-out" sh "$HERE/identity/build-amiga.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
tar -C "$T" -xJf "$A" "$(lock top)/m68k-amigaos/lib/libpthread.a"
cmp "$T/$(lock top)/m68k-amigaos/lib/libpthread.a" "$NEXT/prefix/m68k-amigaos/lib/libpthread.a" \
    || { echo "the next stove's libpthread.a is not the release's"; exit 1; }
echo "libpthread.a is the release's"
diff <(cd "$LIVE/prefix/m68k-amigaos" && find include lib | sort) \
     <(cd "$NEXT/prefix/m68k-amigaos" && find include lib | sort) | grep '^<' || echo "nothing of the live prefix is missing"

[ "$SWAP" = --swap ] || { echo "ready in $NEXT; run again with --swap to put it in"; exit 0; }
echo "== 6. the swap"
if pgrep -f 'm68k-amigaos-(gcc|g\+\+|cc1|cc1plus|ld|as)( |$)' > /dev/null; then
    echo "a compiler of a stove is running: not swapped (run again with --swap when the builds are done)"; exit 3
fi
KEPT="os32-gcc16-$old-kept-$(date -u +%Y%m%d)"
[ ! -e "$STOVES/$KEPT" ] || KEPT="$KEPT-$(date -u +%H%M%S)"
mv "$LIVE" "$STOVES/$KEPT"
mv "$NEXT" "$LIVE"
for l in "os32-gcc16-${old##*-}" "os32-gcc16-$old"; do
    if [ -L "$STOVES/$l" ]; then ln -sfn "$KEPT" "$STOVES/$l"; echo "$l -> $KEPT"; fi
done
for l in "os32-gcc16-$n" "os32-gcc16-$release"; do
    [ -e "$STOVES/$l" ] && [ ! -L "$STOVES/$l" ] && { echo "$l is a folder, left alone"; continue; }
    ln -sfn os32-gcc16 "$STOVES/$l"; echo "$l -> os32-gcc16"
done
"$LIVE/prefix/bin/m68k-amigaos-gcc" --version | sed -n 1p
echo "$HOST: os32-gcc16 is $release; $old kept as $KEPT"
