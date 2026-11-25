#!/usr/bin/env python3
"""Record which compiler builds this port; never refuse a stove.

    python3 scripts/record_stove.py --stove STOVE [--out DIR]
    python3 scripts/record_stove.py STOVE [DIR]

Prints "RELEASE ARCHIVE" on stdout (e.g. "16.2.0-open9 4855...", or
"16.2.0-open9 unpublished" when the stove names no compiler archive) and the
compiler's own --version line on stderr. With DIR it also writes
DIR/build-info.json: the stove's folder, that line, the release and the
archive. RELEASE is the 16.2.0-openN the compiler's --version names, else the
one STOVE.json or provenance.json names, else "unknown"; ARCHIVE is the
compiler archive SHA-256 STOVE.json or provenance.json names, else
"unpublished". Nothing is checked against a list, a minimum or a receipt:
the port builds with the stove it is given. Exits 2 only when the stove has
no compiler at all.

It replaces the old stove certificate gate in the game ports; the copy in
DalsinAI/amicradle-stoves gameports/ is the canonical one.
MIT, Copyright (c) 2026 AmiCradle Team.
"""
from __future__ import annotations

import json
import re
import subprocess
import sys
import time
from pathlib import Path

RELEASE_RE = re.compile(r"16\.2\.0-open\d+")
SHA_RE = re.compile(r"^[0-9a-f]{64}$")


def compiler(stove: Path) -> Path:
    for name in ("m68k-amigaos-gcc", "m68k-amigaos-g++"):
        path = stove / "prefix/bin" / name
        if path.is_file():
            return path
    raise FileNotFoundError(f"no compiler in the stove: {stove / 'prefix/bin/m68k-amigaos-gcc'}")


def compiler_line(stove: Path) -> str:
    cc = compiler(stove)
    try:
        out = subprocess.run([str(cc), "--version"], text=True, capture_output=True, timeout=60).stdout
    except (OSError, subprocess.SubprocessError) as exc:
        return f"unknown ({exc})"
    return (out.splitlines() or ["unknown"])[0].strip()


def stove_files(stove: Path) -> tuple[str | None, str | None]:
    """(release, archive SHA-256) as STOVE.json or provenance.json name them, if they do."""
    release = archive = None
    for name in ("STOVE.json", "provenance.json"):
        try:
            data = json.loads((stove / name).read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        if not isinstance(data, dict):
            continue
        if release is None and isinstance(data.get("release"), str):
            release = data["release"]
        sha = (data.get("compilerArchive") or {}).get("sha256") if isinstance(data.get("compilerArchive"), dict) \
            else data.get("archive_sha256")
        if archive is None and isinstance(sha, str) and SHA_RE.match(sha):
            archive = sha
    return release, archive


def record(stove: Path, out: Path | None = None) -> dict:
    stove = Path(stove)
    line = compiler_line(stove)
    named, archive = stove_files(stove)
    m = RELEASE_RE.search(line) or RELEASE_RE.search(named or "")
    info = {"schema": 1, "stove": stove.name, "stove_path": str(stove), "compiler": line,
            "release": m.group(0) if m else "unknown", "stove_release": named,
            "archive_sha256": archive or "unpublished",
            "built": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
    if out is not None:
        out.mkdir(parents=True, exist_ok=True)
        (out / "build-info.json").write_text(json.dumps(info, indent=1) + "\n", encoding="utf-8")
    return info


def main(argv: list[str]) -> int:
    args = list(argv)
    stove = out = None
    if args and args[0] == "--stove":
        if len(args) not in (2, 4) or (len(args) == 4 and args[2] != "--out"):
            print("usage: record_stove.py --stove STOVE [--out DIR]", file=sys.stderr)
            return 64
        stove, out = args[1], (args[3] if len(args) == 4 else None)
    elif len(args) in (1, 2) and not args[0].startswith("-"):
        stove, out = args[0], (args[1] if len(args) == 2 else None)
    else:
        print("usage: record_stove.py --stove STOVE [--out DIR] | record_stove.py STOVE [DIR]", file=sys.stderr)
        return 64
    try:
        info = record(Path(stove), Path(out) if out else None)
    except FileNotFoundError as exc:
        print(f"record_stove: {exc}", file=sys.stderr)
        return 2
    print(f"compiler: {info['compiler']} (stove {info['stove']}, release {info['release']}, "
          f"archive {info['archive_sha256']})", file=sys.stderr)
    print(info["release"], info["archive_sha256"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
