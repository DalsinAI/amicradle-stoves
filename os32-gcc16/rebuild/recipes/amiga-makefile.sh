#!/bin/sh
# A rebuild recipe for a port built by its own Amiga makefile (amiga/Makefile.amigaos and the like):
#   sh "$REBUILD/recipes/amiga-makefile.sh" MAKEFILE [TARGET] [NAME=VALUE ...]
# runs `make -f MAKEFILE TARGET` with the stove the rebuild gives (STOVE=$STOVE on make's command line: these
# makefiles default to the old os32-gcc16-open6 path), then copies the folder the makefile calls $(OUT) (else
# dist/; FROM=DIR names it for a makefile with neither) into the rebuild's $OUT. STOVE_ARG=prefix passes
# $STOVE/prefix for a makefile whose STOVE is the prefix.
# MIT, Copyright (c) 2026 AmiCradle Team.
set -eu
MF=${1:?usage: amiga-makefile.sh MAKEFILE [TARGET] [NAME=VALUE ...]}; shift
T=${1:-}; [ $# -gt 0 ] && shift
case $T in *=*) set -- "$T" "$@"; T= ;; esac
S=$STOVE; [ "${STOVE_ARG:-}" = prefix ] && S=$STOVE/prefix
make -f "$MF" -j"${JOBS:-4}" $T STOVE="$S" "$@"
dir=$(make -f "$MF" -s --no-print-directory --eval 'rebuild-out: ; @echo $(OUT)' rebuild-out STOVE="$S" "$@" 2>/dev/null || true)
[ -z "${FROM:-}" ] || dir=$FROM
[ -n "$dir" ] && [ -d "$dir" ] || dir=dist
[ -d "$dir" ] || { echo "amiga-makefile.sh: no \$(OUT) folder and no dist/ after make"; exit 1; }
cp -R "$dir" "$OUT/"
echo "amiga-makefile.sh: $dir copied into $OUT"
