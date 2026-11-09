#!/usr/bin/env python3
"""Make the open6 recipe's parts: what the os32-gcc16 open6 stove holds beyond the
gfopengcc v16.2.0-open6 release archive, packed as small archives of their own in
the stove store, so recipe.json never needs an older stove.

    python3 make-parts.py STOVE RELEASE-TARBALL [--store DIR] [--version 1]
    python3 make-parts.py STOVE RELEASE-TARBALL --only kits --version 2 --from TEXT [--store DIR]

STOVE is the assembled open6 stove (the 6 Nov 2026 one, which carried these files
from the retired local open6 build); RELEASE-TARBALL the release archive. Every
file under STOVE that the release lacks goes into one part, by where it lives:

  ndk       NDK 3.2 and the open NDK: ndk/, OPENNDK.json, prefix/m68k-amigaos/ndk*,
            prefix/m68k-amigaos/openndk-fd
  port-deps prefix/m68k-amigaos/port-deps (zlib, png and the rest; its manifest.json
            records each file's SHA-256 and where it was taken from)
  kits      the OpenGPU 0.6/0.7 and GFOpenGPU 0.8 kits: kits/ (their archives and
            file lists) and every file a kits/*.files list names
  opensdk   the Open SDK kit (kits/opensdk-kit.sh): kits/GFOpenSDK-*, and every
            file kits/GFOpenSDK-*.files names (kept apart from the GPU kits, as
            it moves with every SDK release; its recipe step replaces the two
            gfopengpu headers it shares with the GPU kit, newer in the SDK)
  extras    the rest: compat/, patches/, tools/, tests/ and the remaining headers

Each part is packed with amicradle-ci stove pack --kind part; parts.json (here)
records name, version, SHA-256 and file count, which recipe.json pins.

--only GROUP packs that one part again (a new --version) from a stove that has
changed only there, e.g. a kit swapped by os32_stove.py --kit, and replaces
that part's entry in parts.json, keeping the others; --from says which stove.
kits/replaced-*/ (the kit installer's backups) are never packed.
MIT, Copyright (c) 2026 AmiCradle Team.
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SKIP = ("STOVE.json", "STOVE-MANIFEST.json", ".amicradle-fetched.json")


def group(rel: str, kit_files: set[str], sdk_files: set[str] = frozenset()) -> str:
    top = rel.split("/", 1)[0]
    if top == "kits" and rel.split("/")[1].startswith("GFOpenSDK-"):
        return "opensdk"
    if rel.startswith("prefix/") and (rel[len("prefix/"):] in sdk_files
                                      or rel.startswith("prefix/m68k-amigaos/share/GFOpenSDK/")):
        return "opensdk"
    if top in ("ndk", "OPENNDK.json"):
        return "ndk"
    if top == "kits":
        return "skip" if rel.split("/")[1].startswith("replaced-") else "kits"
    if top in ("compat", "patches", "tools", "tests", "README.txt"):
        return "extras"
    p = rel[len("prefix/"):]
    if p.startswith(("m68k-amigaos/ndk", "m68k-amigaos/openndk-fd")):
        return "ndk"
    if p.startswith("m68k-amigaos/port-deps/"):
        return "port-deps"
    if p in kit_files or p.startswith(("m68k-amigaos/share/OpenGPU-SDK", "m68k-amigaos/share/GFOpenGPU-SDK")):
        return "kits"
    return "extras"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("stove")
    ap.add_argument("release")
    ap.add_argument("--store")
    ap.add_argument("--version", default="1")
    ap.add_argument("--only", choices=("ndk", "port-deps", "kits", "opensdk", "extras"))
    ap.add_argument("--from", dest="from_", default="the os32-gcc16 open6 stove assembled 6 Nov 2026 on amigachromebuild")
    ap.add_argument("--tool", default=os.environ.get("AMICRADLE_CI", "amicradle-ci"))
    a = ap.parse_args()
    stove = Path(a.stove).resolve()
    with tarfile.open(a.release) as tf:
        names = tf.getnames()
    top = names[0].split("/", 1)[0]
    release = {n[len(top) + 1:] for n in names if n.startswith(top + "/")}
    kit_files, sdk_files = set(), set()
    for f in (stove / "kits").glob("*.files"):
        into = sdk_files if f.name.startswith("GFOpenSDK-") else kit_files
        into |= {l.strip() for l in f.read_text().splitlines() if l.strip()}
    sys.path.insert(0, str(Path(a.tool).resolve().parent))
    from amicradle_ci import store as st  # the same walk (and exclusions) pack uses
    items, skipped = st.walk(stove, [])
    groups: dict[str, list[str]] = {}
    for rel, p in items:
        if p.is_dir() and not p.is_symlink():
            continue
        if rel in SKIP:
            continue
        if rel.startswith("prefix/") and rel[len("prefix/"):] in release:
            continue
        groups.setdefault(group(rel, kit_files, sdk_files), []).append(rel)
    groups.pop("skip", None)
    old = json.loads((HERE / "parts.json").read_text()) if a.only else None
    out = {"schema": 1, "from": a.from_, "release": Path(a.release).name, "left_out": skipped, "parts": []}
    if old:
        out = dict(old)
        out["parts"] = [p for p in old["parts"] if not p["part"].startswith(f"os32-gcc16-open6-{a.only}@")]
        out.setdefault("remade", []).append({"part": f"os32-gcc16-open6-{a.only}@{a.version}", "from": a.from_})
    for g, files in sorted(groups.items()):
        if a.only and g != a.only:
            continue
        with tempfile.TemporaryDirectory() as td:
            for rel in files:
                q = Path(td) / rel
                q.parent.mkdir(parents=True, exist_ok=True)
                src = stove / rel
                if src.is_symlink():
                    os.symlink(os.readlink(src), q)
                else:
                    shutil.copy2(src, q)
            name = f"os32-gcc16-open6-{g}"
            src_note = json.dumps({"made_by": "amicradle-stoves os32-gcc16/open6/make-parts.py",
                                   "from": a.from_, "group": g})
            subprocess.run([sys.executable, a.tool, "stove", "pack", td, "--name", name, "--version", a.version,
                            "--kind", "part", "--source", src_note, "--replace"]
                           + (["--store", a.store] if a.store else []), check=True)
        idx = st.load_index(Path(a.store).expanduser() if a.store else st.store_dir())
        e = [e for e in idx["entries"] if e["name"] == name and e["version"] == a.version][0]
        out["parts"].append({"part": f"{name}@{a.version}", "sha256": e["sha256"], "files": e["files"],
                             "size": e["size"]})
        print(f"{name}@{a.version}: {len(files)} files, sha256 {e['sha256']}")
    (HERE / "parts.json").write_text(json.dumps(out, indent=2) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
