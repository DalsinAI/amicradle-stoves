#!/usr/bin/env bash
# Build the os4-gcc16 stove: GCC 16.2.0 and binutils 2.47 for AmigaOS 4.1 on
# the PowerPC (ppc-amigaos), from pinned GNU sources and our patches, on this
# machine. No Docker and no prebuilt compilers.
#
#   ./build.sh [--stove DIR] [--work DIR] [--sdk FILE] [--jobs N]
#              [--until STEP] [--verify-only]
#
#   --stove DIR    the stove folder (default: WORK/stove). The compiler goes in
#                  DIR/prefix and the identity in DIR/stove.json. The compiler
#                  keeps this path for its SDK, so build it where it will live:
#                  on a Cradle machine, ~/AmiCradle/stoves/os4.
#   --work DIR     sources, build trees and logs (default: ./work). Keep it off
#                  /tmp where /tmp is RAM.
#   --sdk FILE     Hyperion's AmigaOS 4.1 SDK archive (SDK_54.25.lha). Without
#                  it the SDK is downloaded from Hyperion into WORK/ports.
#   --jobs N       parallel make jobs (default: every CPU)
#   --until STEP   stop after STEP: sources, binutils, sdk, xgcc, clib2, clib4,
#                  gcc or test
#   --verify-only  fetch nothing; check the sources in WORK/ports and stop
#
# Each step leaves a stamp in WORK/stamps/<recipe hash>, so running the script
# again carries on from the step that failed. A changed recipe starts over; the
# smoke tests and stove.json (steps 8 and 9) are not part of the hash, so a fix
# to them reruns only them.
#
# Host needs: git curl xz bzip2 make gcc g++ bison flex gawk m4 perl python3
# texinfo patch lhasa (for lha), and gpgv to check the GNU signatures.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$HERE/work"; STOVE=""; SDK_FILE=""; JOBS="$(nproc 2>/dev/null || echo 4)"; UNTIL=""; VERIFY_ONLY=0
while [ $# -gt 0 ]; do
    case "$1" in
        --work) WORK="$2"; shift 2 ;;
        --stove) STOVE="$2"; shift 2 ;;
        --sdk) SDK_FILE="$2"; shift 2 ;;
        --jobs) JOBS="$2"; shift 2 ;;
        --until) UNTIL="$2"; shift 2 ;;
        --verify-only) VERIFY_ONLY=1; shift ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done
STEPS="sources binutils sdk xgcc clib2 clib4 gcc test"
case " $STEPS " in *" ${UNTIL:-test} "*) ;; *) echo "--until takes one of: $STEPS" >&2; exit 2 ;; esac
WORK="$(realpath -m "$WORK")"
STOVE="$(realpath -m "${STOVE:-$WORK/stove}")"
[ -z "$SDK_FILE" ] || SDK_FILE="$(realpath "$SDK_FILE")"
PREFIX="$STOVE/prefix"
TARGET=ppc-amigaos
GCC_VERSION=16.2.0
BINUTILS_VERSION=2.47
# The C libraries, built from source. clib2 is static and runs on a bare
# OS 4.1 FE; clib4 needs clib4.library (built here too) in LIBS:.
CLIB2_REPOSITORY=https://github.com/sodero/clib2
CLIB2_REF=1a42c693e03881f6f969c43ab36ce20d2569751d
CLIB4_REPOSITORY=https://github.com/AmigaLabs/clib4
CLIB4_REF=30e487d28f9b3d12fc9e4adb641aeff84050de3b
# Hyperion's SDK, as adtools fetches it (54.25 is file 137, 54.16 is 127).
SDK_VERSION=54.25
SDK_URL='https://www.hyperion-entertainment.biz/index.php?option=com_registration&amp;view=download&amp;format=raw&amp;file=137'

PORTS="$WORK/ports"; SRC="$WORK/src"; BUILD="$WORK/build"; LOGS="$WORK/logs"
# The hash covers build.sh up to the "# 8. Smoke tests" line, which must stay.
RECIPE_HASH="$( { sed '/^# 8\. Smoke tests/,$d' "$HERE/build.sh"; cat "$HERE/sources.lock" "$HERE"/patches/*.patch; } | sha256sum | cut -c1-16)"
STAMPS="$WORK/stamps/$RECIPE_HASH"
mkdir -p "$PORTS" "$LOGS"

done_step() { [ -f "$STAMPS/$1" ]; }
mark() { mkdir -p "$STAMPS"; date -u +%Y-%m-%dT%H:%M:%SZ > "$STAMPS/$1"; }
stop_after() { if [ "$UNTIL" = "$1" ]; then echo "stopped after $1 (--until)"; exit 0; fi; }
# Runs a command with its output in a log; on failure shows the log's end.
logged() {
    local log="$LOGS/$1.log"; shift
    if ! "$@" > "$log" 2>&1; then
        echo "failed: $* (log: $log)" >&2
        tail -n 40 "$log" >&2
        exit 1
    fi
}

# 1. Sources: GNU tarballs checked against sources.lock and their signatures;
#    the C libraries at their pinned commits.
if [ "$VERIFY_ONLY" = 1 ] || ! done_step sources; then
    while read -r sha name url; do
        case "$sha" in ''|'#'*) continue ;; esac
        # "-": not pinned (GNU's keyring), so fetched fresh every time.
        [ "$sha" = - ] && [ "$VERIFY_ONLY" != 1 ] && rm -f "$PORTS/$name"
        if [ ! -f "$PORTS/$name" ]; then
            [ "$VERIFY_ONLY" = 1 ] && { echo "missing: $name" >&2; exit 3; }
            echo "fetching $name"
            curl -fsSL -o "$PORTS/$name.part" "$url"
            mv "$PORTS/$name.part" "$PORTS/$name"
        fi
        [ "$sha" = - ] || echo "$sha  $PORTS/$name" | sha256sum -c --quiet - || { echo "checksum mismatch: $name" >&2; exit 4; }
    done < "$HERE/sources.lock"
    sigs="$(awk '$2 ~ /\.sig$/ { print $2 }' "$HERE/sources.lock")"
    if [ -n "$sigs" ] && command -v gpgv >/dev/null 2>&1; then
        for sig in $sigs; do
            gpgv --keyring "$PORTS/gnu-keyring.gpg" "$PORTS/$sig" "$PORTS/${sig%.sig}" 2>&1 | grep -q "Good signature" \
                || { echo "bad GNU signature: ${sig%.sig}" >&2; exit 4; }
        done
        echo "GNU signatures good"
    elif [ -n "$sigs" ]; then
        echo "gpgv not found: checksums checked, GNU signatures not" >&2
    fi
    for lib in clib2 clib4; do
        if [ "$lib" = clib2 ]; then repo="$CLIB2_REPOSITORY"; ref="$CLIB2_REF"; else repo="$CLIB4_REPOSITORY"; ref="$CLIB4_REF"; fi
        if [ "$(git -C "$PORTS/$lib" rev-parse HEAD 2>/dev/null)" != "$ref" ]; then
            [ "$VERIFY_ONLY" = 1 ] && { echo "missing: $lib at $ref" >&2; exit 3; }
            echo "fetching $lib at $ref"
            rm -rf "$PORTS/$lib"
            git init -q "$PORTS/$lib"
            git -C "$PORTS/$lib" fetch -q --depth 1 "$repo" "$ref"
            git -C "$PORTS/$lib" checkout -q --detach FETCH_HEAD
        fi
        [ "$(git -C "$PORTS/$lib" rev-parse HEAD)" = "$ref" ] || { echo "$lib is not at $ref" >&2; exit 4; }
    done
    echo "sources verified"
    [ "$VERIFY_ONLY" = 1 ] && exit 0
    mark sources
fi
stop_after sources

# The stove folder. A build of a new recipe gets an empty prefix: whatever is
# there from before (another os4 stove, or a build of an earlier recipe) is
# moved to STOVE/replaced-<time>/, never deleted. STOVE/.recipe says which
# recipe the prefix belongs to.
if [ "$(cat "$STOVE/.recipe" 2>/dev/null)" != "$RECIPE_HASH" ]; then
    if [ -d "$STOVE" ] && [ -n "$(ls -A "$STOVE" | grep -v '^replaced-' || true)" ]; then
        old="$STOVE/replaced-$(date -u +%Y%m%dT%H%M%SZ)"
        mkdir -p "$old"
        for entry in "$STOVE"/* "$STOVE"/.[!.]*; do
            [ -e "$entry" ] || continue
            case "$(basename "$entry")" in replaced-*) continue ;; esac
            mv "$entry" "$old/"
        done
        echo "the stove folder's earlier contents are in $old"
    fi
    rm -rf "$STAMPS"/binutils "$STAMPS"/sdk "$STAMPS"/xgcc "$STAMPS"/clib2 "$STAMPS"/clib4 "$STAMPS"/gcc "$STAMPS"/test
    mkdir -p "$PREFIX"
    echo "$RECIPE_HASH" > "$STOVE/.recipe"
fi
SDK="$PREFIX/$TARGET/SDK"

# 2. binutils: the pinned GNU release with our AmigaOS patch.
unpack() {   # unpack <tarball> <folder>: a fresh copy of the sources
    rm -rf "$2" && mkdir -p "$2"
    tar -xf "$1" -C "$2" --strip-components=1
}
if ! done_step binutils; then
    echo "binutils $BINUTILS_VERSION"
    unpack "$PORTS/binutils-$BINUTILS_VERSION.tar.bz2" "$SRC/binutils"
    logged binutils-patch patch -d "$SRC/binutils" -p1 -F0 --no-backup-if-mismatch -i "$HERE/patches/binutils-$BINUTILS_VERSION-amigaos.patch"
    rm -rf "$BUILD/binutils" && mkdir -p "$BUILD/binutils"
    logged binutils-configure sh -c "cd '$BUILD/binutils' && '$SRC/binutils/configure' --target=$TARGET --prefix='$PREFIX' \
        --disable-nls --disable-werror --disable-gdb --disable-gdbserver --disable-sim --disable-readline \
        --disable-libdecnumber --disable-gprofng"
    logged binutils-make make -C "$BUILD/binutils" -j"$JOBS"
    logged binutils-install make -C "$BUILD/binutils" install
    mark binutils
fi
stop_after binutils
export PATH="$PREFIX/bin:$PATH"

# 3. The SDK: Hyperion's headers and newlib, unpacked as adtools does. It is
#    not ours to redistribute: it stays in WORK/ports and in the stove.
if ! done_step sdk; then
    archive="$PORTS/SDK_$SDK_VERSION.lha"
    if [ -n "$SDK_FILE" ]; then
        cp "$SDK_FILE" "$archive.part" && mv "$archive.part" "$archive"
    elif [ ! -f "$archive" ]; then
        echo "downloading the AmigaOS 4.1 SDK $SDK_VERSION from Hyperion"
        curl -fsSL -o "$archive.part" "$SDK_URL"
        mv "$archive.part" "$archive"
    fi
    # An LhA archive has "-lh" at offset 2; a web page instead means the download failed.
    [ "$(head -c 5 "$archive" | tail -c 3)" = "-lh" ] \
        || { echo "$archive is not an LhA archive: download the SDK from Hyperion and pass --sdk FILE" >&2; exit 5; }
    rm -rf "$WORK/sdk-unpack" && mkdir -p "$WORK/sdk-unpack"
    ( cd "$WORK/sdk-unpack" && lha xqf "$archive" \
      && cd SDK_Install && for a in newlib*.lha base.lha execsg*.lha; do [ -f "$a" ] && lha xqf "$a"; done ) \
        > "$LOGS/sdk.log" 2>&1 || { echo "could not unpack $archive (log: $LOGS/sdk.log)" >&2; exit 5; }
    [ -d "$WORK/sdk-unpack/SDK_Install/Include/include_h" ] && [ -d "$WORK/sdk-unpack/SDK_Install/newlib" ] \
        || { echo "$archive has no Include/include_h or newlib: is it the AmigaOS 4.1 SDK?" >&2; exit 5; }
    rm -rf "$SDK/newlib" "$SDK/include"
    mkdir -p "$SDK/include"
    mv "$WORK/sdk-unpack/SDK_Install/newlib" "$SDK/newlib"
    mv "$WORK/sdk-unpack/SDK_Install/Include/"* "$SDK/include/"
    [ -f "$WORK/sdk-unpack/SDK_Install/SDK-Version.txt" ] && cp "$WORK/sdk-unpack/SDK_Install/SDK-Version.txt" "$SDK/"
    rm -rf "$WORK/sdk-unpack"
    sha256sum "$archive" | cut -d' ' -f1 > "$SDK/.archive-sha256"
    echo "SDK $SDK_VERSION unpacked into $SDK"
    mark sdk
fi
stop_after sdk

# 4. GCC, first only the compiler (xgcc), which builds the C libraries.
#    gmp, mpfr, mpc and isl are built in the tree, so the host needs no -dev packages.
GCC_SRC="$SRC/gcc"; GCC_BUILD="$BUILD/gcc"; XGCC_DIR="$GCC_BUILD/gcc"
# libstdc++ would hand the amigaos thread model's native condition variables
# to pthread_cond_clockwait() wherever that links (clib4); adtools presets the
# probe the same way.
export glibcxx_cv_PTHREAD_COND_CLOCKWAIT=no
if ! done_step xgcc; then
    echo "GCC $GCC_VERSION: the compiler"
    unpack "$PORTS/gcc-$GCC_VERSION.tar.xz" "$GCC_SRC"
    logged gcc-patch patch -d "$GCC_SRC" -p1 -F0 --no-backup-if-mismatch -i "$HERE/patches/gcc-$GCC_VERSION-amigaos.patch"
    for lib in gmp-6.3.0.tar.bz2:gmp mpfr-4.2.2.tar.bz2:mpfr mpc-1.4.1.tar.xz:mpc isl-0.27.tar.xz:isl; do
        unpack "$PORTS/${lib%%:*}" "$GCC_SRC/${lib##*:}"
    done
    rm -rf "$GCC_BUILD" && mkdir -p "$GCC_BUILD"
    logged gcc-configure sh -c "cd '$GCC_BUILD' && '$GCC_SRC/configure' --target=$TARGET --prefix='$PREFIX' \
        --with-pkgversion='AmiCradle os4-gcc16' --with-bugurl=https://github.com/DalsinAI/amigachrome-stoves/issues \
        --enable-languages=c,c++ --enable-threads=amigaos --enable-lto --disable-tls --with-dwarf2 \
        --disable-libstdcxx-pch --disable-c++tools --disable-nls --disable-werror"
    logged gcc-make-xgcc make -C "$GCC_BUILD" -j"$JOBS" all-gcc
    mark xgcc
fi
stop_after xgcc
XGCC="$XGCC_DIR/xgcc -B$XGCC_DIR/"

# 5. clib2, from a fresh copy (its build writes into its tree).
if ! done_step clib2; then
    echo "clib2"
    rm -rf "$BUILD/clib2" && cp -a "$PORTS/clib2" "$BUILD/clib2"
    logged clib2-make make -C "$BUILD/clib2/library" -f GNUmakefile.os4 -j"$JOBS" \
        CC="$XGCC -Wno-error=int-conversion -Wno-error=incompatible-pointer-types -Wno-error=implicit-function-declaration" \
        AR="$PREFIX/bin/$TARGET-ar -q" RANLIB="$PREFIX/bin/$TARGET-ranlib"
    rm -rf "$SDK/clib2" && mkdir -p "$SDK/clib2"
    cp -Rp "$BUILD/clib2/library/include" "$BUILD/clib2/library/lib" "$BUILD/clib2/library/lib.threadsafe" "$SDK/clib2/"
    cp "$BUILD/clib2/LICENSE" "$SDK/clib2/"
    mark clib2
fi
stop_after clib2

# 6. clib4 and its clib4.library. The compiler does not depend on it, so a
#    clib4 that will not build is reported and the stove carries on without it.
if ! done_step clib4; then
    echo "clib4"
    rm -rf "$BUILD/clib4" "$SDK/clib4" && cp -a "$PORTS/clib4" "$BUILD/clib4"
    if make -C "$BUILD/clib4" -f GNUmakefile.os4 -j"$JOBS" CC="$XGCC" \
           AR="$PREFIX/bin/$TARGET-ar -q" RANLIB="$PREFIX/bin/$TARGET-ranlib" STRIP="$PREFIX/bin/$TARGET-strip" \
           INSTALL_PREFIX="$SDK/clib4" SDK_INCLUDE="$SDK/include" > "$LOGS/clib4-make.log" 2>&1 \
       && mkdir -p "$SDK/clib4/include" "$SDK/clib4/lib/baserel" \
       && make -C "$BUILD/clib4" -f GNUmakefile.os4 install INSTALL_PREFIX="$SDK/clib4" > "$LOGS/clib4-install.log" 2>&1; then
        # clib4 carries a prebuilt libauto.a (GCC 4.2.4, 2008); we take no prebuilt binaries.
        rm -f "$SDK/clib4/lib/libauto.a" "$SDK/clib4/lib/baserel/libauto.a"
        cp "$BUILD/clib4"/LICENSE* "$SDK/clib4/"
        echo "built" > "$STOVE/.clib4"
    else
        echo "clib4 did not build (log: $LOGS/clib4-make.log); the stove carries on without it" >&2
        tail -n 15 "$LOGS/clib4-make.log" >&2
        rm -rf "$SDK/clib4"
        echo "failed" > "$STOVE/.clib4"
    fi
    mark clib4
fi
stop_after clib4

# 7. The rest of GCC (libgcc, libstdc++, libatomic, libssp for each C library),
#    then install.
if ! done_step gcc; then
    echo "GCC $GCC_VERSION: the libraries"
    logged gcc-make make -C "$GCC_BUILD" -j"$JOBS"
    logged gcc-install make -C "$GCC_BUILD" install
    mark gcc
fi
stop_after gcc

# 8. Smoke tests with the installed compiler: big-endian PowerPC ELF
#    executables that keep their relocations (OS 4.1's loader needs them).
CC="$PREFIX/bin/$TARGET-gcc"; CXX="$PREFIX/bin/$TARGET-g++"; READELF="$PREFIX/bin/$TARGET-readelf"
T="$WORK/tests"; rm -rf "$T" && mkdir -p "$T"
is_ppc_exe() {   # a big-endian 32-bit PowerPC ELF executable
    [ "$(head -c 6 "$1" | od -An -tx1 | tr -d ' \n')" = "7f454c460102" ] &&
    [ "$(head -c 20 "$1" | tail -c 4 | od -An -tx1 | tr -d ' \n')" = "00020014" ]
}
results=""; failed=0
check() {   # check <name> <output> <compile command...>: a program that keeps its relocations
    local name="$1" out="$2"; shift 2
    if "$@" > "$T/$name.log" 2>&1 && is_ppc_exe "$out" && { [ "$name" = device ] || "$READELF" -S "$out" | grep '\.rela\.text' >/dev/null; }; then
        results="$results$name: ok\n"
    else
        results="$results$name: FAILED (see $T/$name.log)\n"; failed=1
    fi
}
SMOKE="$HERE/tests/smoke"
check c-newlib "$T/hello-newlib" "$CC" -O2 -o "$T/hello-newlib" "$SMOKE/hello.c"
check c-clib2 "$T/hello-clib2" "$CC" -mcrt=clib2 -O2 -o "$T/hello-clib2" "$SMOKE/hello.c"
[ "$(cat "$STOVE/.clib4" 2>/dev/null)" = built ] && check c-clib4 "$T/hello-clib4" "$CC" -mcrt=clib4 -O2 -o "$T/hello-clib4" "$SMOKE/hello.c"
check cxx-newlib "$T/hello-cxx" "$CXX" -athread=native -O2 -o "$T/hello-cxx" "$SMOKE/hello.cpp"
check cxx-clib2 "$T/hello-cxx-clib2" "$CXX" -mcrt=clib2 -athread=native -O2 -o "$T/hello-cxx-clib2" "$SMOKE/hello.cpp"
check device "$T/device" "$CC" -O2 -fno-builtin -nostartfiles -nostdlib -o "$T/device" "$SMOKE/device.c" -lgcc
# The SDK's newlib has no base-relative libc.a, so -mbaserel is tested with clib2, which builds one.
check baserel "$T/hello-baserel" "$CC" -mcrt=clib2 -mbaserel -O2 -o "$T/hello-baserel" "$SMOKE/hello.c"
printf "$results" | tee "$LOGS/smoke-tests.txt"
[ "$failed" = 0 ] || { echo "smoke tests failed" >&2; exit 6; }
mark test

# 9. Identity: what this stove is, so it is never mistaken for another compiler.
python3 - "$STOVE" "$HERE" "$GCC_VERSION" "$BINUTILS_VERSION" "$SDK_VERSION" "$CLIB2_REF" "$CLIB4_REF" <<'PY'
import hashlib, json, subprocess, sys, time
from pathlib import Path
stove, here, gcc, binutils, sdk_version, clib2, clib4 = Path(sys.argv[1]), Path(sys.argv[2]), *sys.argv[3:]
prefix = stove / "prefix"
cc = prefix / "bin" / "ppc-amigaos-gcc"
sdk = prefix / "ppc-amigaos" / "SDK"
commit = subprocess.run(["git", "-C", str(here), "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
clib4_built = (stove / ".clib4").read_text().strip() == "built"
identity = {
    "schema": 1, "id": "os4-gcc16", "name": "AmigaOS 4.1 PowerPC, GCC 16.2",
    "target": "ppc-amigaos", "gcc": gcc, "binutils": binutils,
    "compilerVersion": subprocess.run([str(cc), "--version"], capture_output=True, text=True).stdout.splitlines()[0],
    "recipe": {"repository": "DalsinAI/amigachrome-stoves", "commit": commit or None,
               "patches": {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((here / "patches").glob("*.patch"))}},
    "prefix": "prefix",
    "sdk": {"owner": "Hyperion Entertainment", "version": sdk_version, "path": "prefix/ppc-amigaos/SDK",
            "archiveSha256": (sdk / ".archive-sha256").read_text().strip(), "redistributable": False},
    "cLibraries": {"default": "newlib", "newlib": "from the SDK",
                   "clib2": {"ref": clib2, "built": True},
                   "clib4": {"ref": clib4, "built": clib4_built}},
    "builtAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
}
(stove / "stove.json").write_text(json.dumps(identity, indent=2) + "\n")
print(identity["compilerVersion"])
PY
echo "done: $PREFIX/bin/$TARGET-gcc"
