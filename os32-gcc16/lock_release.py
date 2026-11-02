#!/usr/bin/env python3
"""Write toolchain.lock for a GFOpenAmigaGCC release, from the release's own files.

    python3 os32-gcc16/lock_release.py VERSION SHA256SUMS ARCHIVE COMMIT [--lock FILE]

VERSION is the release (16.2.0-open5), SHA256SUMS and ARCHIVE the release's checksums and x86-64 toolchain as
downloaded, and COMMIT the full commit its tag v<VERSION> points at (gh api
repos/DalsinAI/gfopengcc/git/ref/tags/v<VERSION>). The release's names follow from SHA256SUMS: from open5 the
files are gfopenamigagcc-VERSION-*.tar.xz and the compiler says "GFOpenAmigaGCC VERSION"; open1 to open4 are
openamigagcc-VERSION-*.tar.xz and "OpenAmigaGCC VERSION". It refuses an archive whose SHA-256 or name isn't the
one SHA256SUMS lists. Then upgrade.sh and identity/build-amiga.sh take that release.
MIT, Copyright (c) 2026 AmiCradle Team.
"""
from __future__ import annotations

import argparse
import hashlib
import re
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = "https://github.com/DalsinAI/gfopengcc"
NAMES = (("gfopenamigagcc", "GFOpenAmigaGCC"), ("openamigagcc", "OpenAmigaGCC"))   # from open5; open1 to open4


def sums(path: Path) -> dict:
    out = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        m = re.fullmatch(r"([0-9a-f]{64})\s+\*?(\S+)", line.strip())
        if m:
            out[m.group(2)] = m.group(1)
    return out


def lock_text(version: str, listed: dict, archive: Path, commit: str) -> str:
    for prefix, name in NAMES:
        binary, source = f"{prefix}-{version}-x86_64-linux.tar.xz", f"{prefix}-{version}-src.tar.xz"
        if binary in listed:
            break
    else:
        raise SystemExit(f"SHA256SUMS lists no {NAMES[0][0]}-{version}-x86_64-linux.tar.xz "
                         f"or {NAMES[1][0]}-{version}-x86_64-linux.tar.xz")
    if archive.name != binary:
        raise SystemExit(f"{archive.name} is not the release's toolchain, {binary}")
    data = archive.read_bytes()
    got = hashlib.sha256(data).hexdigest()
    if got != listed[binary]:
        raise SystemExit(f"{archive.name}: SHA-256 {got} is not SHA256SUMS' {listed[binary]}")
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise SystemExit("COMMIT: the tag's full 40-character commit")
    tag = f"v{version}"
    return "\n".join([
        f"# os32-gcc16's compiler: the GFOpenAmigaGCC release the stove carries. Read by upgrade.sh (which refuses an",
        f"# archive whose SHA-256 isn't the one here) and by identity/build-amiga.sh (which fails on a stove whose",
        f"# compiler doesn't say this release). Written by lock_release.py on {time.strftime('%d %B %Y')}.",
        f"# Release: {REPO}/releases/tag/{tag} (tag at {commit[:8]}); the hashes are the release's own SHA256SUMS,",
        f"# checked against the downloaded toolchain.",
        f"release={version}",
        f"identity=({name} {version})",
        f"tag={tag}",
        f"commit={commit}",
        f"archive={binary}",
        f"archive_sha256={got}",
        f"archive_bytes={len(data)}",
        f"archive_url={REPO}/releases/download/{tag}/{binary}",
        f"source={source}",
        f"source_sha256={listed.get(source, '')}",
        f"top={binary.removesuffix('.tar.xz')}",
        "",
    ])


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("version")
    ap.add_argument("sums", type=Path)
    ap.add_argument("archive", type=Path)
    ap.add_argument("commit")
    ap.add_argument("--lock", type=Path, default=HERE / "toolchain.lock")
    a = ap.parse_args(argv)
    text = lock_text(a.version, sums(a.sums), a.archive, a.commit)
    a.lock.write_text(text, encoding="utf-8")
    print(text, end="")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
