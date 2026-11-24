#!/bin/sh
# A rebuild recipe for a repo whose build wants another repository checked out beside it:
#   sh "$REBUILD/recipes/beside.sh" URL DIR [FILE] -- COMMAND [ARG ...]
# clones URL as ../DIR (kept between rebuilds; fetched again each time), puts it at the commit it had when the
# clone's own HEAD was committed (so a release tag gets the sibling its build had then, not today's), checks that
# FILE (when given) is there, then runs COMMAND in the clone. An address of a mirrored organisation goes to the git
# mirror by the rebuild's insteadOf settings. MIT, Copyright (c) 2026 AmiCradle Team.
set -eu
URL=${1:?usage: beside.sh URL DIR [FILE] -- COMMAND [ARG ...]}; DIR=${2:?usage: beside.sh URL DIR [FILE] -- COMMAND}
shift 2
FILE=
[ "${1:-}" = -- ] || { FILE=${1:-}; shift; }
[ "${1:-}" = -- ] && shift
[ $# -gt 0 ] || { echo "beside.sh: no COMMAND" >&2; exit 2; }
S=$(cd .. && pwd)/$DIR
if [ -d "$S/.git" ]; then git -C "$S" fetch -q origin; else git clone -q --no-checkout "$URL" "$S"; fi
AT=$(git log -1 --format=%cI HEAD)
C=$(git -C "$S" log -1 --format=%H --before="$AT" origin/HEAD)
[ -n "$C" ] || { echo "beside.sh: $URL has no commit before $AT" >&2; exit 2; }
git -C "$S" -c advice.detachedHead=false checkout -q -f --detach "$C"
[ -z "$FILE" ] || [ -e "$S/$FILE" ] || { echo "beside.sh: $URL at $C has no $FILE" >&2; exit 2; }
echo "beside.sh: $URL at $(git -C "$S" log -1 --format='%h %cI' "$C") as ../$DIR (this clone's HEAD: $AT)"
exec "$@"
