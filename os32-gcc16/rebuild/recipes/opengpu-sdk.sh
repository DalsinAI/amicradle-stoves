#!/bin/sh
# A rebuild recipe for a port built against GFOpenGPU (SDL2 and GL):
#   sh "$REBUILD/recipes/opengpu-sdk.sh" COMMAND [ARG ...]
# runs COMMAND with the SDK variables the ports' build scripts ask for, all from the stove the rebuild gives
# (its prefix carries GFOpenGPU's SDK, kits/GFOpenGPU-SDK-*, so the headers and the libraries are one release):
#   OPENUP_SDK   the stove's prefix (bin/sdl2-config; amiganeverball, as its validation built it: OPENUP_SDK=$STOVE)
#   OPENGL_KIT   the stove's prefix/m68k-amigaos (lib/libSDL2.a, lib/libGL.a; amigaserioussam's KIT)
#   OPENGPU_SDK  a folder in the shape of a GFOpenGPU SDK build (build/include/SDL2, build/libSDL2.a), made beside
#                the clone of links into that kit (amigaserioussam's SDK)
# Each is kept when it is already set. MIT, Copyright (c) 2026 AmiCradle Team.
set -eu
[ $# -gt 0 ] || { echo "usage: opengpu-sdk.sh COMMAND [ARG ...]" >&2; exit 2; }
P=$STOVE; [ -x "$STOVE/prefix/bin/m68k-amigaos-gcc" ] && P=$STOVE/prefix
K=$P/m68k-amigaos
for f in "$P/bin/sdl2-config" "$K/include/SDL2/SDL.h" "$K/lib/libSDL2.a" "$K/lib/libGL.a"; do
    [ -e "$f" ] || { echo "opengpu-sdk.sh: the stove has no $f (GFOpenGPU's SDK is not in it)" >&2; exit 2; }
done
if [ -z "${OPENGPU_SDK:-}" ]; then
    OPENGPU_SDK=$(cd .. && pwd)/opengpu-sdk
    mkdir -p "$OPENGPU_SDK/build/include"
    ln -sfn "$K/include/SDL2" "$OPENGPU_SDK/build/include/SDL2"
    ln -sfn "$K/lib/libSDL2.a" "$OPENGPU_SDK/build/libSDL2.a"
fi
OPENUP_SDK=${OPENUP_SDK:-$P}
OPENGL_KIT=${OPENGL_KIT:-$K}
export OPENUP_SDK OPENGL_KIT OPENGPU_SDK
echo "opengpu-sdk.sh: OPENUP_SDK=$OPENUP_SDK OPENGL_KIT=$OPENGL_KIT OPENGPU_SDK=$OPENGPU_SDK"
exec "$@"
