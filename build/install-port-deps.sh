#!/bin/sh
# Copyright (c) 2026 AmiCradle Team. MIT licence.
# install-port-deps.sh [--check-only] STOVE GAMEPORTS [SOURCE]
# Stages the codec inventory the game ports link (zlib, PNG, JPEG, FreeType:
# archives and their headers) into an AmigaOS 3.x stove, at
# prefix/m68k-amigaos/port-deps/ with its manifest.json. amicradle-gameports
# recipes (AstroMenace, AssaultCube, UQM, NXEngine) refuse to build without it
# (DEPENDENCY_GATE_FAILED).
# GAMEPORTS is a checkout of DalsinAI/amicradle-gameports: its
# toolchain/port-dependencies.lock.json pins every file by SHA-256 and its
# scripts/port_dependencies.py does the staging and checking, so the lock has
# one home. SOURCE holds the locked include/ and lib/ files (on Daletop,
# $AMICRADLE_DEV/webkit-os32-040/m68k-amigaos); nothing is searched for or
# downloaded. Every hash is checked before anything is written, and only
# port-deps/ is written. A stove whose port-deps/ already verifies is left as
# it is; one that does not verify is not overwritten (move it aside first).
# --check-only only checks.
# A stove under ~/AmiCradle/stoves is in use: set LIVE_OK=1 to write there. (~/AmigaChrome/stoves too:
# on a machine set up before the rename the folder is still there, with ~/AmiCradle a link to it.)
# Undo: remove prefix/m68k-amigaos/port-deps/.
set -eu
CHECK_ONLY=0
[ "${1:-}" = "--check-only" ] && { CHECK_ONLY=1; shift; }
[ $# -ge 2 ] || { echo "usage: $0 [--check-only] STOVE GAMEPORTS [SOURCE]" >&2; exit 2; }
STOVE=$(cd "$1" && pwd)
GP=$(cd "$2" && pwd)
PD="$GP/scripts/port_dependencies.py"
[ -f "$PD" ] || { echo "no $PD (is $GP an amicradle-gameports checkout?)" >&2; exit 2; }
[ -d "$STOVE/prefix/m68k-amigaos" ] || { echo "no $STOVE/prefix/m68k-amigaos" >&2; exit 2; }
DEST="$STOVE/prefix/m68k-amigaos/port-deps"

if python3 -I "$PD" verify --stove "$STOVE" >/dev/null 2>&1; then
    echo "ok: $DEST matches $GP's lock"
    exit 0
fi
if [ $CHECK_ONLY = 1 ]; then
    python3 -I "$PD" verify --stove "$STOVE"
    exit 1
fi
[ $# -eq 3 ] || { echo "$DEST does not verify; give SOURCE to stage it" >&2; exit 2; }
SRC=$(cd "$3" && pwd)
case "$STOVE/" in
    "$HOME/AmiCradle/stoves/"* | "$HOME/AmigaChrome/stoves/"*) [ "${LIVE_OK:-0}" = 1 ] || { echo "$STOVE is a live stove: set LIVE_OK=1 to stage its port-deps" >&2; exit 3; } ;;
esac
[ -e "$DEST" ] && { echo "$DEST exists but does not verify; not overwritten (move it aside first)" >&2; exit 4; }
python3 -I "$PD" stage --stove "$STOVE" --source "$SRC"
python3 -I "$PD" verify --stove "$STOVE" >/dev/null
echo "ok: staged $DEST from $SRC, verified against $GP's lock"
