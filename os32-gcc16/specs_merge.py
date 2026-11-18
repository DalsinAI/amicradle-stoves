#!/usr/bin/env python3
"""Carry a live stove's own specs blocks into the next stove's specs.

    python3 os32-gcc16/specs_merge.py LIVE_SPECS NEXT_SPECS [--check]

A GCC specs file is blocks: a "*name:" line, the block's lines, a blank line. The live stove's specs is the
release's plus blocks the Cradle machine added (open8's "*gfmalloc:" and "*lib_libnix:", README: "the live open6
specs file's *gfmalloc: and *lib_libnix: blocks appended"). Every block the live specs has and the next one
hasn't is appended to the next one, as it is; the next specs is written only if that changes it, and the old one
kept as specs.before-merge. A block both have with different text is the release's to decide: it is listed and
the next one's text stays. --check writes nothing.
MIT, Copyright (c) 2026 AmiCradle Team.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path


def blocks(text: str) -> dict[str, str]:
    """{name: its block's text, "*name:" line and its lines, without the blank line after it}. A name defined
    more than once (a later "*lib:" whose text starts with "+" adds to the first) maps to all its blocks, in
    order, joined by a blank line."""
    out, name, lines = {}, None, []

    def end():
        out[name] = out[name] + "\n\n" + "\n".join(lines) if name in out else "\n".join(lines)
    for line in text.splitlines():
        if name is None:
            if line.startswith("*") and line.rstrip().endswith(":"):
                name, lines = line.rstrip()[1:-1], [line.rstrip()]
        elif line.strip() == "":
            end()
            name, lines = None, []
        else:
            lines.append(line.rstrip("\n"))
    if name is not None:
        end()
    return out


def merge(live: str, nxt: str) -> tuple[str, list[str], list[str]]:
    """(the next specs with the live-only blocks appended, the names appended, the names that differ)."""
    lb, nb = blocks(live), blocks(nxt)
    added = [n for n in lb if n not in nb]
    differ = [n for n in lb if n in nb and lb[n] != nb[n]]
    text = nxt
    if added:
        text = nxt.rstrip("\n") + "\n\n" + "".join(lb[n] + "\n\n" for n in added)
    return text, added, differ


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("live", type=Path)
    ap.add_argument("next", type=Path)
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args(argv)
    text, added, differ = merge(a.live.read_text(encoding="utf-8"), a.next.read_text(encoding="utf-8"))
    print("carried from the live specs:", " ".join("*" + n for n in added) or "nothing")
    if differ:
        print("in both, the release's kept:", " ".join("*" + n for n in differ))
    if added and not a.check:
        a.next.with_name(a.next.name + ".before-merge").write_text(a.next.read_text(encoding="utf-8"), encoding="utf-8")
        a.next.write_text(text, encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
