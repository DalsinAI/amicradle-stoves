#!/usr/bin/env python3
"""stove-json.py STOVE: the open6 stove's STOVE.json, from recipe.json's own record
(release, archive) and kits.json (the kits the parts carry). No time stamp, so the
same recipe gives the same file. MIT, Copyright (c) 2026 AmiCradle Team."""
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
stove = Path(sys.argv[1])
r = json.loads((HERE / "recipe.json").read_text())
rel = [s for s in r["steps"] if s.get("extract", "").startswith("gfopenamigagcc@")][0]
d = {
    "schema": 1,
    "id": "os32-gcc16",
    "release": "GFOpenAmigaGCC 16.2.0-open6",
    "compilerArchive": {"name": rel["gh"]["asset"], "sha256": rel["sha256"],
                        "from": f"https://github.com/{rel['gh']['repo']}/releases/tag/{rel['gh']['tag']}"},
    "kits": json.loads((HERE / "kits.json").read_text()),
    "recipe": "amicradle-stoves os32-gcc16/open6/recipe.json (amicradle-ci stove assemble)",
    "parts": [s["part"] + " " + s["sha256"] for s in r["steps"] if "part" in s],
    "vasm": "vasmm68k_mot and vobjdump 2.0f in prefix/bin, built from vasm2_0f.tar.gz "
            "(c84b2de1...); free for non-commercial use: never in a release",
    "libnix": "qsort.o in every libnix.a replaced by amicradle-stoves os32-gcc16/libnix/qsort.c "
              "(install-qsort.sh, 7 Nov 2026): libnix's own never returned, or read outside the array, "
              "when the comparison function never returns 0 (libwebp's sorts)",
    "how": "prefix = the release archive; NDK 3.2, the open NDK, port-deps, the GPU kits and the "
           "stove's own extras from the store's parts (made once from the 6 Nov 2026 stove by "
           "make-parts.py); vasm built from source; libnix's qsort fixed; no link leaves the stove",
}
(stove / "STOVE.json").write_text(json.dumps(d, indent=2) + "\n")
