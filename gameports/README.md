# Game-port stove gate

`verify_gameport_stove.py` is the one compiler-stove check every AmiCradle
game port runs before it builds. The canonical copy is this one; each port
carries a copy in `scripts/verify_gameport_stove.py`, and its
`build-amiga.sh` calls it:

    COMPILER=$(python3 "$HERE/scripts/verify_gameport_stove.py" --stove "$STOVE")
    RELEASE=${COMPILER% *}      # e.g. 16.2.0-open6
    ARCHIVE=${COMPILER#* }      # the compiler archive's SHA-256, or "unpublished" (open5)

It prints `RELEASE ARCHIVE-SHA256` on stdout, says on stderr what it accepted
and why, and exits 2 with `STOVE_GATE_FAILED: ...` on stderr otherwise. A stove
is accepted when all of these hold:

1. its `STOVE.json` (`compilerArchive.sha256`) or, for a staged stove,
   `provenance.json` (`archive_sha256`) names the compiler archive's SHA-256,
   as a published release has. A locally built stove has none and is refused.
   GFOpenAmigaGCC 16.2.0-open5, which has no published archive, is the one
   exception: taken by `STOVE.json`'s release and the compiler's `--version`.
2. the release is OpenAmigaGCC/GFOpenAmigaGCC `16.2.0-openN`, from the
   stove's `release`, or for open3/open4 stoves that do not record one, from
   the script's `KNOWN` archive table.
3. `prefix/bin/m68k-amigaos-gcc --version` names that same release.
4. N is at least `--min` (default `open3`; a port that needs more passes e.g.
   `--min open6`).
5. an archive in `KNOWN` is never accepted as a different release.

A new release (open7, open8, ...) whose stove records its archive passes with
no change to the script or the ports. `--release` and `--accept` narrow it to
named releases; `--require-file-receipt` refuses a staged stove whose
`provenance.json` lacks the per-file `compiler_runtime_sha256` receipt (when
the receipt is there, every file is always checked).

`python3 gameports/verify_gameport_stove.py --self-test` builds fake stoves
under `/tmp` and checks the rules above.

To bring a port up to date, from the port's checkout:

    cp ../amicradle-stoves/gameports/verify_gameport_stove.py scripts/verify_gameport_stove.py
