# Game-port stove recorder

`record_stove.py` is the one compiler-stove step every AmiCradle game port
runs before it builds. It records which compiler builds the port; it does not
check the stove against a list of releases, a minimum release or a receipt,
and it refuses a stove only when the stove has no compiler at all. The
canonical copy is this one; each port carries a copy in
`scripts/record_stove.py`, and its `build-amiga.sh` calls it:

    COMPILER=$(python3 "$HERE/scripts/record_stove.py" --stove "$STOVE")
    RELEASE=${COMPILER% *}      # e.g. 16.2.0-open9, or "unknown"
    ARCHIVE=${COMPILER#* }      # the compiler archive's SHA-256, or "unpublished"

It prints `RELEASE ARCHIVE-SHA256` on stdout and the compiler's own
`--version` line on stderr:

- `RELEASE` is the `16.2.0-openN` that `prefix/bin/m68k-amigaos-gcc --version`
  names, else the one the stove's `STOVE.json` or `provenance.json` names,
  else `unknown`;
- `ARCHIVE` is the compiler archive SHA-256 that `STOVE.json`
  (`compilerArchive.sha256`) or `provenance.json` (`archive_sha256`) names,
  else `unpublished`. A port's receipt then records the SHA-256 of the
  compiler's own programs instead.

`--out DIR` also writes `DIR/build-info.json` with the stove's folder, the
compiler line, the release and the archive. It exits 2 only when the stove
has no compiler.

The ports keep their other inputs as they are: pinned sources and the locked
codec inventory (`port_dependencies.py`).

To bring a port up to date, from the port's checkout:

    cp ../amicradle-stoves/gameports/record_stove.py scripts/record_stove.py
