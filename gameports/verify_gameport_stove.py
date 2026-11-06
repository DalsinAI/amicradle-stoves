#!/usr/bin/env python3
"""Fail closed unless a game-port build uses an approved compiler stove.

    python3 scripts/verify_gameport_stove.py --stove STOVE [--min open3]
    python3 scripts/verify_gameport_stove.py --self-test

Prints "RELEASE ARCHIVE-SHA256" on stdout (e.g. "16.2.0-open6 65f2...") and
exits 0 when ALL of these hold; otherwise prints "STOVE_GATE_FAILED: ..." on
stderr and exits 2:

  1. the stove names its compiler archive's SHA-256: STOVE.json's
     compilerArchive.sha256 (Cradle's stoves) or provenance.json's
     archive_sha256 (a staged stove). A published release has one; a locally
     built stove has none and is refused. The one exception is
     GFOpenAmigaGCC 16.2.0-open5, which has no published archive: it is taken
     by STOVE.json's release and the compiler's own --version, and
     ARCHIVE-SHA256 is "unpublished".
  2. the release is OpenAmigaGCC/GFOpenAmigaGCC 16.2.0-openN, from
     STOVE.json's (or provenance.json's) "release"; for open3/open4 stoves
     that do not record one, from KNOWN below (by archive SHA-256).
  3. the first line of the stove's own prefix/bin/m68k-amigaos-gcc --version
     names that same release (catches a mislabelled folder).
  4. N is at least --min (default open3).
  5. an archive SHA-256 listed in KNOWN is never accepted as another release.

A new GFOpenAmigaGCC release (open7, open8, ...) whose stove records its
archive passes with no change here. --release (one release) and --accept
(a list) narrow it further. When provenance.json carries
compiler_runtime_sha256 (the SHA-256 of every compiler/runtime file), every
file is checked; --require-file-receipt refuses a provenance.json without it.
What was accepted, and why, goes to stderr.

The canonical copy lives in DalsinAI/amicradle-stoves
(gameports/verify_gameport_stove.py); game ports carry a copy in
scripts/verify_gameport_stove.py.
MIT, Copyright (c) 2026 AmiCradle Team.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

# compiler archives by SHA-256: only needed for stoves whose STOVE.json or
# provenance.json does not say its release (open3, open4), and to refuse an
# archive that claims to be another release. New releases need no entry.
KNOWN = {
    "5ece099a6fb8923a35eacf420bfa5fced06546ac1822714c76a2ae52466c978c": "16.2.0-open2",
    "9fcc136ab59e3bb5b91d2764d0bf290b709d72d7380be4ce0cdf005edf8eff21": "16.2.0-open3",
    "495319a2ffd803278f8827cad70074029c7aa9ecbe05d037e8646ba43ab94ab2": "16.2.0-open4",
    "65f284476ec20cdf7851475d91d2c18d77fa6f2a0eb0f844b6ca23dbfa57eaa7": "16.2.0-open6",   # GFOpenAmigaGCC, v16.2.0-open6's x86-64 archive
}
OPEN5 = "GFOpenAmigaGCC 16.2.0-open5"
DEFAULT_MIN = "16.2.0-open3"

RELEASE_RE = re.compile(r"^(?:((?:GF)?OpenAmigaGCC) )?(16\.2\.0-open(\d+))$")
VERSION_RE = re.compile(r"\(((?:GF)?OpenAmigaGCC) (16\.2\.0-open(\d+))\)")
SHA_RE = re.compile(r"^[0-9a-f]{64}$")


class GateError(ValueError):
    pass


def release_number(text: str) -> int:
    """'open7', '16.2.0-open7' or 'GFOpenAmigaGCC 16.2.0-open7' -> 7"""
    m = re.fullmatch(r"(?:(?:GF)?OpenAmigaGCC )?(?:16\.2\.0-)?open(\d+)", text.strip())
    if not m:
        raise argparse.ArgumentTypeError(f"not a release: {text!r} (want e.g. open6 or 16.2.0-open6)")
    return int(m.group(1))


def full_release(text: str) -> str:
    return f"16.2.0-open{release_number(text)}"


def digest(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def compiler_first_line(stove: Path) -> str:
    cc = stove / "prefix/bin/m68k-amigaos-gcc"
    if not cc.is_file():
        raise GateError(f"{cc} is missing")
    run = subprocess.run([str(cc), "--version"], capture_output=True, text=True, timeout=60)
    lines = run.stdout.splitlines()
    if run.returncode != 0 or not lines:
        raise GateError(f"{cc} --version failed (exit {run.returncode})")
    return lines[0]


def check_file_receipt(stove: Path, files: dict) -> int:
    if "bin/m68k-amigaos-g++" not in files or len(files) < 100:
        raise GateError("provenance.json: incomplete compiler/runtime receipt")
    prefix = (stove / "prefix").resolve()
    for name, expected in files.items():
        path = (prefix / name).resolve()
        if not path.is_relative_to(prefix) or not path.is_file() or digest(path) != expected:
            raise GateError(f"provenance.json: compiler/runtime changed: {name}")
    return len(files)


def verify(stove: Path, minimum: int = 3, release_only: str | None = None,
           accept: list[str] | None = None, require_file_receipt: bool = False) -> tuple[str, str, list[str]]:
    """Returns (release, archive sha256 or "unpublished", reasons)."""
    why: list[str] = []
    archive = named = None
    source = None
    receipt = None
    if (stove / "STOVE.json").is_file():
        info = json.loads((stove / "STOVE.json").read_text())
        archive = (info.get("compilerArchive") or {}).get("sha256")
        named = info.get("release")
        source = "STOVE.json"
    if archive is None and (stove / "provenance.json").is_file():
        receipt = json.loads((stove / "provenance.json").read_text())
        archive = receipt.get("archive_sha256")
        named = named or receipt.get("release")
        source = "provenance.json"
    if source is None:
        raise GateError(f"{stove} has neither STOVE.json nor provenance.json")

    first = compiler_first_line(stove)
    said = VERSION_RE.search(first)

    # rule 1, open5's exception: no published archive, taken by STOVE.json's
    # release and the compiler's own --version (as before)
    if archive is None and named == OPEN5:
        if f"({OPEN5})" not in first:
            raise GateError(f"STOVE.json says {named}, the compiler says {first!r}")
        release, archive = "16.2.0-open5", "unpublished"
        why.append(f"{source} release {named!r} with no published archive (the open5 exception)")
        why.append(f"compiler --version: {first!r}")
    else:
        # rule 1: a published archive's SHA-256
        if archive is None:
            raise GateError(f"{stove}: {source} names no compiler archive SHA-256 "
                            f"(release {named!r}); a locally built stove is not accepted")
        if not isinstance(archive, str) or not SHA_RE.match(archive):
            raise GateError(f"{stove}: {source} compiler archive SHA-256 {archive!r} is not a SHA-256")
        why.append(f"{source} compiler archive SHA-256 {archive}")
        # rule 2: the release, from the stove, or from KNOWN when it has none
        if named is not None:
            m = RELEASE_RE.match(str(named).strip())
            if not m:
                raise GateError(f"{stove}: {source} release {named!r} is not "
                                f"OpenAmigaGCC/GFOpenAmigaGCC 16.2.0-openN")
            vendor, release = m.group(1), m.group(2)
            why.append(f"{source} release {named!r}")
            # rule 5: a known archive is never another release
            if archive in KNOWN and KNOWN[archive] != release:
                raise GateError(f"{stove}: {source} says {named!r} but archive {archive} is {KNOWN[archive]}")
            if archive in KNOWN:
                why.append(f"archive is the known {KNOWN[archive]} archive")
        elif archive in KNOWN:
            vendor, release = None, KNOWN[archive]
            why.append(f"no release recorded; archive is the known {release} archive")
        else:
            raise GateError(f"{stove}: {source} records no release and archive {archive} is not a known one")
        # rule 3: the compiler itself says the same release
        if not said or said.group(2) != release or (vendor and said.group(1) != vendor):
            want = f"({vendor} {release})" if vendor else f"(OpenAmigaGCC/GFOpenAmigaGCC {release})"
            raise GateError(f"{stove}: the stove says {release}, the compiler says {first!r} (want {want})")
        why.append(f"compiler --version: {first!r}")
        # uqm's rule: a staged stove's receipt of every compiler/runtime file
        if source == "provenance.json":
            files = receipt.get("compiler_runtime_sha256")
            if files is not None:
                why.append(f"provenance.json: {check_file_receipt(stove, files)} compiler/runtime files match")
            elif require_file_receipt:
                raise GateError("provenance.json has no compiler_runtime_sha256 receipt")

    # rule 4 and the narrowing options
    n = release_number(release)
    if n < minimum:
        raise GateError(f"{stove} is {release}; this port needs 16.2.0-open{minimum} or later")
    why.append(f"{release} >= minimum 16.2.0-open{minimum}")
    if release_only and release != release_only:
        raise GateError(f"the stove is {release}, not {release_only}")
    if accept and release not in accept:
        raise GateError(f"the stove is {release}; accepted: {', '.join(accept)}")
    return release, archive, why


def self_test() -> int:
    import os
    import tempfile

    root = Path(tempfile.mkdtemp(prefix="stove-gate-test-", dir="/tmp"))

    def stove(name, stove_json=None, version=None, provenance=None):
        s = root / name
        (s / "prefix/bin").mkdir(parents=True)
        if stove_json is not None:
            (s / "STOVE.json").write_text(json.dumps(stove_json))
        if provenance is not None:
            (s / "provenance.json").write_text(json.dumps(provenance))
        if version is not None:
            cc = s / "prefix/bin/m68k-amigaos-gcc"
            cc.write_text(f"#!/bin/sh\necho 'm68k-amigaos-gcc ({version}) 16.2.0b 20260930174807'\n")
            os.chmod(cc, 0o755)
        return s

    open6 = "65f284476ec20cdf7851475d91d2c18d77fa6f2a0eb0f844b6ca23dbfa57eaa7"
    open3 = "9fcc136ab59e3bb5b91d2764d0bf290b709d72d7380be4ce0cdf005edf8eff21"
    open4 = "495319a2ffd803278f8827cad70074029c7aa9ecbe05d037e8646ba43ab94ab2"
    fake7 = "7" * 64
    cases = [
        # (name, stove, kwargs, expected (release, archive) or None for refused)
        ("release open6 stove accepted",
         stove("open6", {"release": "GFOpenAmigaGCC 16.2.0-open6", "compilerArchive": {"sha256": open6}},
               "GFOpenAmigaGCC 16.2.0-open6"), {}, ("16.2.0-open6", open6)),
        ("locally built open6 (no archive) refused",
         stove("local6", {"release": "GFOpenAmigaGCC 16.2.0-open6"}, "GFOpenAmigaGCC 16.2.0-open6"), {}, None),
        ("open3 by KNOWN archive, no release field, accepted",
         stove("open3", {"compilerArchive": {"sha256": open3}}, "OpenAmigaGCC 16.2.0-open3"), {},
         ("16.2.0-open3", open3)),
        ("open3 with release field accepted",
         stove("open3r", {"release": "OpenAmigaGCC 16.2.0-open3", "compilerArchive": {"sha256": open3}},
               "OpenAmigaGCC 16.2.0-open3"), {}, ("16.2.0-open3", open3)),
        ("open4 staged stove by provenance.json accepted",
         stove("open4p", None, "OpenAmigaGCC 16.2.0-open4", {"archive_sha256": open4}), {},
         ("16.2.0-open4", open4)),
        ("fake open7 (unknown archive, recorded) accepted",
         stove("open7", {"release": "GFOpenAmigaGCC 16.2.0-open7", "compilerArchive": {"sha256": fake7}},
               "GFOpenAmigaGCC 16.2.0-open7"), {}, ("16.2.0-open7", fake7)),
        ("STOVE.json open7 but compiler open6 refused",
         stove("lie7", {"release": "GFOpenAmigaGCC 16.2.0-open7", "compilerArchive": {"sha256": fake7}},
               "GFOpenAmigaGCC 16.2.0-open6"), {}, None),
        ("vendor mismatch (STOVE GFOpenAmigaGCC, compiler OpenAmigaGCC) refused",
         stove("vendor", {"release": "GFOpenAmigaGCC 16.2.0-open7", "compilerArchive": {"sha256": fake7}},
               "OpenAmigaGCC 16.2.0-open7"), {}, None),
        ("known open4 archive labelled open6 refused",
         stove("relabel", {"release": "GFOpenAmigaGCC 16.2.0-open6", "compilerArchive": {"sha256": open4}},
               "GFOpenAmigaGCC 16.2.0-open6"), {}, None),
        ("open3 below --min open6 refused", root / "open3", {"minimum": 6}, None),
        ("open6 at --min open6 accepted", root / "open6", {"minimum": 6}, ("16.2.0-open6", open6)),
        ("open2 below default minimum refused",
         stove("open2", {"compilerArchive": {"sha256": "5ece099a6fb8923a35eacf420bfa5fced06546ac1822714c76a2ae52466c978c"}},
               "OpenAmigaGCC 16.2.0-open2"), {}, None),
        ("open5 special case accepted",
         stove("open5", {"release": OPEN5}, OPEN5), {}, ("16.2.0-open5", "unpublished")),
        ("open5 STOVE.json with open6 compiler refused",
         stove("open5lie", {"release": OPEN5}, "GFOpenAmigaGCC 16.2.0-open6"), {}, None),
        ("unknown archive without release refused",
         stove("anon", {"compilerArchive": {"sha256": fake7}}, "GFOpenAmigaGCC 16.2.0-open7"), {}, None),
        ("--release 16.2.0-open6 refuses open7", root / "open7", {"release_only": "16.2.0-open6"}, None),
        ("--accept open3 open4 refuses open6", root / "open6", {"accept": ["16.2.0-open3", "16.2.0-open4"]}, None),
        ("provenance.json without file receipt refused when required",
         root / "open4p", {"require_file_receipt": True}, None),
        ("no compiler refused",
         stove("nocc", {"release": "GFOpenAmigaGCC 16.2.0-open6", "compilerArchive": {"sha256": open6}}), {}, None),
    ]
    failed = 0
    for name, path, kwargs, expected in cases:
        try:
            release, archive, _ = verify(path, **kwargs)
            got = (release, archive)
        except (OSError, ValueError, KeyError, TypeError) as exc:
            got, err = None, exc
        ok = got == expected
        failed += not ok
        detail = f"{got[0]} {got[1][:12]}" if got else f"refused: {err}"
        print(f"{'ok  ' if ok else 'FAIL'} {name}: {detail}")
    print(f"{len(cases) - failed}/{len(cases)} passed")
    import shutil
    shutil.rmtree(root, ignore_errors=True)
    return 1 if failed else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--stove", type=Path)
    parser.add_argument("--min", type=release_number, default=release_number(DEFAULT_MIN),
                        help="the oldest release this port takes (e.g. open6; default open3)")
    parser.add_argument("--release", type=full_release, help="take this one release only (e.g. 16.2.0-open6)")
    parser.add_argument("--accept", nargs="+", type=full_release,
                        help="take only these releases (e.g. 16.2.0-open3 16.2.0-open4)")
    parser.add_argument("--require-file-receipt", action="store_true",
                        help="refuse a staged stove whose provenance.json lacks compiler_runtime_sha256")
    parser.add_argument("--self-test", action="store_true", help="run the gate's own tests on fake stoves in /tmp")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    if args.stove is None:
        parser.error("--stove is required")
    try:
        release, archive, why = verify(args.stove.resolve(), args.min, args.release, args.accept,
                                       args.require_file_receipt)
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as exc:
        parser.exit(2, f"STOVE_GATE_FAILED: {exc}\n")
    print(f"stove gate: accepted {args.stove} as {release}:", file=sys.stderr)
    for line in why:
        print(f"  - {line}", file=sys.stderr)
    print(release, archive)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
