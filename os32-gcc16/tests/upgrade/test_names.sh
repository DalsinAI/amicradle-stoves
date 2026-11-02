#!/bin/sh
# Host test, no download: lock_release.py, upgrade.sh and identity/build-amiga.sh take a GFOpenAmigaGCC release
# under either name. Open1 to open4 are openamigagcc-VERSION-*.tar.xz and say "OpenAmigaGCC VERSION"; from
# open5 they are gfopenamigagcc-VERSION-*.tar.xz and say "GFOpenAmigaGCC VERSION". Each is a pretend release
# (a compiler that only answers --version and writes a hunk header), locked into a scratch toolchain.lock
# (OS32_GCC16_LOCK), and moved onto a pretend live stove that says open3.
#   os32-gcc16/tests/upgrade/test_names.sh [SCRATCH]
# MIT, Copyright (c) 2026 AmiCradle Team.
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
S=${1:-$(mktemp -d)}
fails=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi; }
COMMIT=0123456789abcdef0123456789abcdef01234567

release() {   # release DIR PREFIX NAME VERSION: a pretend release's toolchain, source and SHA256SUMS in DIR
    d=$1; top="$2-$4-x86_64-linux"
    mkdir -p "$d/$top/bin" "$d/$top/m68k-amigaos/libnix" "$d/$top/m68k-amigaos/sys-include"
    cat > "$d/$top/bin/m68k-amigaos-gcc" <<G
#!/bin/sh
[ "\$1" = --version ] && { echo "m68k-amigaos-gcc ($3 $4) 16.2.0b 20260930174807"; exit 0; }
while [ \$# -gt 0 ]; do [ "\$1" = -o ] && { printf '\\000\\000\\003\\363' > "\$2"; exit 0; }; shift; done
exit 1
G
    chmod +x "$d/$top/bin/m68k-amigaos-gcc"
    ( cd "$d" && tar -cJf "$top.tar.xz" "$top" && rm -rf "$top" && echo src > "$2-$4-src.tar.xz" \
      && sha256sum "$top.tar.xz" "$2-$4-src.tar.xz" > SHA256SUMS )
}

live() {   # live STOVES: a pretend open3 stove
    L="$1/os32-gcc16"
    mkdir -p "$L/prefix/bin" "$L/prefix/m68k-amigaos/port-deps/lib" "$L/kits"
    printf '#!/bin/sh\necho "m68k-amigaos-gcc (OpenAmigaGCC 16.2.0-open3) 16.2.0b 20260930174807"\n' > "$L/prefix/bin/m68k-amigaos-gcc"
    chmod +x "$L/prefix/bin/m68k-amigaos-gcc"
    echo zlib > "$L/prefix/m68k-amigaos/port-deps/lib/libz.a"
    echo kit > "$L/kits/kit.tar.gz"
    printf '{"schema": 1, "id": "os32-gcc16", "release": "OpenAmigaGCC 16.2.0-open3", "kits": [{"name": "kit"}]}\n' > "$L/STOVE.json"
}

for case in "openamigagcc OpenAmigaGCC 16.2.0-open4" "gfopenamigagcc GFOpenAmigaGCC 16.2.0-open5"; do
    set -- $case; prefix=$1; name=$2; version=$3
    R="$S/$version/release"; T="$S/$version/stoves"; LOCK="$S/$version/toolchain.lock"
    rm -rf "$S/$version"; mkdir -p "$R" "$T"
    release "$R" "$prefix" "$name" "$version"; live "$T"
    archive="$R/$prefix-$version-x86_64-linux.tar.xz"

    out=$(python3 "$HERE/lock_release.py" "$version" "$R/SHA256SUMS" "$archive" "$COMMIT" --lock "$LOCK" 2>&1); rc=$?
    check "$version: lock_release.py writes the lock" '[ $rc -eq 0 ]'
    check "$version: the lock names $prefix-$version and ($name $version)" \
        'grep -qx "archive=$prefix-$version-x86_64-linux.tar.xz" "$LOCK" && grep -qx "identity=($name $version)" "$LOCK" && grep -qx "top=$prefix-$version-x86_64-linux" "$LOCK"'
    cp "$archive" "$S/$version/renamed.tar.xz"
    out=$(python3 "$HERE/lock_release.py" "$version" "$R/SHA256SUMS" "$S/$version/renamed.tar.xz" "$COMMIT" --lock "$S/$version/x.lock" 2>&1); rc=$?
    check "$version: lock_release.py refuses an archive of another name" '[ $rc -ne 0 ] && [ ! -e "$S/$version/x.lock" ]'

    out=$(OS32_GCC16_LOCK="$LOCK" STOVE="$T/os32-gcc16" OUT="$S/$version/id-old" sh "$HERE/identity/build-amiga.sh" 2>&1); rc=$?
    check "$version: identity fails on the open3 stove" '[ $rc -ne 0 ] && echo "$out" | grep -q "NOT $version"'

    out=$(OS32_GCC16_LOCK="$LOCK" sh "$HERE/upgrade.sh" "$T" "$archive" 2>&1); rc=$?
    N="$T/.next/os32-gcc16"
    check "$version: upgrade.sh takes the release" '[ $rc -eq 0 ]' || echo "$out" | tail -5
    check "$version: STOVE.json says $name $version, the kit kept" 'python3 -c "
import json,sys; d=json.load(open(sys.argv[1]))
assert d[\"release\"]==sys.argv[2], d; assert d[\"compilerArchive\"][\"name\"]==sys.argv[3], d; assert d[\"kits\"][0][\"name\"]==\"kit\"" \
        "$N/STOVE.json" "$name $version" "$prefix-$version-x86_64-linux.tar.xz"'
    check "$version: README.txt names it" 'head -1 "$N/README.txt" | grep -q "$name $version"'
    out=$(OS32_GCC16_LOCK="$LOCK" STOVE="$N" OUT="$S/$version/id-new" sh "$HERE/identity/build-amiga.sh" 2>&1); rc=$?
    check "$version: identity passes on the new stove" '[ $rc -eq 0 ] && echo "$out" | grep -q "identity: $version"'
done

# A stove whose compiler says the lock's release under the other name passes too (the name changed at open5;
# the release number is what is pinned).
LOCK="$S/16.2.0-open5/toolchain.lock"
mkdir -p "$S/other/prefix/bin"
printf '#!/bin/sh\n[ "$1" = --version ] && { echo "m68k-amigaos-gcc (OpenAmigaGCC 16.2.0-open5) 16.2.0b"; exit 0; }\nwhile [ $# -gt 0 ]; do [ "$1" = -o ] && { printf x > "$2"; exit 0; }; shift; done\n' > "$S/other/prefix/bin/m68k-amigaos-gcc"
chmod +x "$S/other/prefix/bin/m68k-amigaos-gcc"
out=$(OS32_GCC16_LOCK="$LOCK" STOVE="$S/other" OUT="$S/other/id" sh "$HERE/identity/build-amiga.sh" 2>&1); rc=$?
check "identity: the same release under the old name passes" '[ $rc -eq 0 ]'
printf '#!/bin/sh\necho "m68k-amigaos-gcc (GFOpenAmigaGCC 16.2.0-open4) 16.2.0b"\n' > "$S/other/prefix/bin/m68k-amigaos-gcc"
out=$(OS32_GCC16_LOCK="$LOCK" STOVE="$S/other" OUT="$S/other/id" sh "$HERE/identity/build-amiga.sh" 2>&1); rc=$?
check "identity: another release under the new name fails" '[ $rc -ne 0 ]'

[ $fails -eq 0 ] && echo PASS || { echo "FAIL ($fails)"; exit 1; }
