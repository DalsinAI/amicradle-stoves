#!/bin/bash
# make-relocatable.sh SRC DEST: a copy of the aros68k-gcc16 open6 stove that works from
# any folder, ready for amicradle-ci stove pack. SRC is not changed.
#
# The stove as built (gfopengcc scripts/build-aros.sh, 3 Nov 2026) names its own folder
# in three places that a move breaks, and which still "work" on the machine it was
# built on because the old folder is there:
#   1. GCC's sysroot (--with-sysroot=SRC/sdk/Developer, not under the prefix, so GCC
#      does not relocate it): the drivers m68k-aros-gcc, -g++, -c++, -cpp and
#      -gcc-16.2.0 become small scripts that run the real program (NAME.real, beside
#      it, so GCC's own relocation of its prefix still holds) with
#      --sysroot=<the script's folder>/../sdk/Developer. A --sysroot given after it wins.
#   2. collect-aros (GCC's linker on AROS) runs ld, strip, nm and objdump, and takes
#      libpthread.a from the SDK, by absolute paths: rebuilt from AROS's own source at the
#      stove's AROS commit (collect-aros.lock, every file's SHA-256) with reloc.c, which
#      finds them from collect-aros's own folder.
#   3. libtool's .la files and GCC's install-tools/ (mkheaders) name the build folder;
#      nothing compiles through them here, so they are left out.
# logs/ is left out; toolchain/, sdk/ (the sysroot) and sdk-build/ are kept.
# STOVE.json's paths become relative to the stove.
# m68k-aros-ld run by hand (not through gcc) still has the build's sysroot as its
# default: give it --sysroot=STOVE/sdk/Developer.
# MIT, Copyright (c) 2026 AmiCradle Team.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$(cd "${1:?usage: make-relocatable.sh SRC DEST}" && pwd)
DEST=${2:?usage: make-relocatable.sh SRC DEST}
[ -e "$DEST" ] && { echo "$DEST exists"; exit 1; }
D=$DEST.tmp
rm -rf "$D"; mkdir -p "$D"
cp -a "$SRC/toolchain" "$SRC/sdk" "$SRC/sdk-build" "$SRC/README.txt" "$SRC/STOVE.json" "$D/"
TC=$D/toolchain

# 2. collect-aros from source
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
COMMIT=$(sed -n 's/^commit //p' "$HERE/collect-aros.lock")
grep -v -e '^#' -e '^commit ' "$HERE/collect-aros.lock" | while read -r f sha; do
  curl -fsSL -o "$W/$f" "https://raw.githubusercontent.com/aros-development-team/AROS/$COMMIT/tools/collect-aros/$f"
  echo "$sha  $W/$f" | sha256sum -c --quiet - || { echo "$f: wrong SHA-256"; exit 1; }
done
sed -e 's|@AROS_CROSSTOOLSDIR@/||g; s|@aros_toolchain_ld@|m68k-aros-ld|; s|@aros_target_cpu@|m68k|g; s|@aros_toolchain@|gnu|g' \
    -e 's|@orig_target_ld@|m68k-aros-ld|; s|@aros_target_strip@|m68k-aros-strip|' \
    -e 's|@aros_target_nm@|m68k-aros-nm --demangle --undefined-only --line-numbers|; s|@aros_target_objdump@|m68k-aros-objdump|' \
    "$W/env.h.in" > "$W/env.h"
! grep -q '@' "$W/env.h" || { echo "env.h.in has a setting this script does not fill"; exit 1; }
cp "$HERE/reloc.c" "$HERE/reloc.h" "$W/"
( cd "$W" && ${HOST_CC:-cc} -o collect-aros -Wall -O2 -D_CROSS_ -DOBJLIBDIR='reloc_objlibdir()' -include reloc.h -I . \
    collect-aros.c gensets.c misc.c backend-generic.c docommand-exec.c reloc.c )
strip "$W/collect-aros"
strings "$W/collect-aros" | grep -q -e /home/ -e "$SRC" && { echo "collect-aros still names a folder"; exit 1; }
install -m 755 "$W/collect-aros" "$TC/m68k-aros/bin/collect-aros"
install -m 755 "$W/collect-aros" "$TC/m68k-aros-collect-aros"

# 1. the drivers find the sysroot beside the toolchain
for n in m68k-aros-gcc m68k-aros-g++ m68k-aros-c++ m68k-aros-cpp m68k-aros-gcc-16.2.0; do
  [ -f "$TC/$n" ] || continue
  mv "$TC/$n" "$TC/$n.real"
  cat > "$TC/$n" <<SH
#!/bin/sh
# $n of a relocatable stove (amicradle-stoves aros68k-gcc16/open6/make-relocatable.sh):
# the real program is $n.real; the sysroot is found from this script's folder.
self=\$0
while [ -L "\$self" ]; do
    link=\$(readlink "\$self")
    case \$link in /*) self=\$link ;; *) self=\$(dirname "\$self")/\$link ;; esac
done
here=\$(CDPATH= cd -- "\$(dirname -- "\$self")" && pwd)
exec "\$here/$n.real" --sysroot="\$here/../sdk/Developer" "\$@"
SH
  chmod 755 "$TC/$n"
done

# 3. what names the build folder and is not needed to compile
find "$D" -name '*.la' -delete
rm -rf "$TC/libexec/gcc/m68k-aros/16.2.0/install-tools"

python3 - "$D/STOVE.json" "$SRC" <<'PY'
import json, sys
p, src = sys.argv[1], sys.argv[2]
d = json.load(open(p))
alt = src.replace("/AmigaChrome/", "/AmiCradle/")
def rel(v):
    if isinstance(v, str):
        for s in (src, alt, src.replace("/AmiCradle/", "/AmigaChrome/")):
            if v.startswith(s + "/"):
                return v[len(s) + 1:]
    return v
for k in ("prefix", "sysroot"):
    d[k] = rel(d.get(k))
d["compilers"] = {k: rel(v) for k, v in d.get("compilers", {}).items()}
d["relocatable"] = ("made by amicradle-stoves aros68k-gcc16/open6/make-relocatable.sh: drivers pass "
                    "--sysroot=<stove>/sdk/Developer, collect-aros rebuilt to find its tools from its own "
                    "folder, .la files and install-tools left out; paths here are relative to the stove")
json.dump(d, open(p, "w"), indent=2)
open(p, "a").write("\n")
PY
printf '\nRelocatable copy: made by amicradle-stoves aros68k-gcc16/open6/make-relocatable.sh\n(see that script and STOVE.json "relocatable"); it works from any folder.\n' >> "$D/README.txt"
mv "$D" "$DEST"
echo "made $DEST: $("$DEST/toolchain/m68k-aros-gcc" -print-sysroot)"
