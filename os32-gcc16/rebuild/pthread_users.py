#!/usr/bin/env python3
"""Find the DalsinAI programs open9 has to rebuild, and rebuild them on the new os32-gcc16 stove, unattended.

Two reasons a shipped program needs building again:
- libpthread (open9, aros-stuff 0011, pthread_cond_signal). Programs link it statically, so the fix reaches a
  program only when it is linked again. libpthread is one object (pthread.o): a program that calls any pthread
  function, or uses std::thread / std::condition_variable, carries all of it, and its text "pthread thread #%ld"
  (the name pthread_create gives a new task). That text tells, from what was really shipped, who carries it.
- fold-mem-offsets (GCC 0019, fixed from open8, kept in open9): open6 and open7 could put a memory-to-memory
  store 8 bytes early at -O2/-O3 with -m68040/-m68060, in any 68k program. Cradle's stove has been open8 since
  14 Nov 2026 18:55 UTC, so a release published before then was built on open6 or open7.

    pthread_users.py scan    [--owner DalsinAI] [--repos FILE] [--work DIR] [--out pthread-users.tsv] [--resume]
    pthread_users.py rebuild --stove STOVE [--list pthread-users.tsv] [--why both|pthread|fmo]
                             [--recipes recipes.tsv] [--work DIR] [--report rebuild-report.tsv]
                             [--only REPO ...] [--again]

scan: for every repo of the owner (or the names in --repos), downloads its newest release's archives (.lha,
.zip, .tar.*, .tgz), unpacks them, looks in every file for libpthread's text and for AmigaOS hunk programs. One
line per repo: repo, tag, libpthread "yes"/"no"/"no-release"/"error", the files that carry it, the release's
publish time, "yes"/"no" AmigaOS programs. Downloads are removed as it goes.

rebuild: for every repo of the list that --why picks (default both: carries libpthread, or has AmigaOS programs
released before open8), or --only, clones or updates it under WORK and runs its build recipe in the clone with
STOVE, OS32_GCC16, OUT and REBUILD (this folder, for recipes/) set (the output must land in OUT): recipes.tsv's "repo <TAB> command", else
package/build-amiga.sh, else build-amiga.sh. A repo with none is "no-recipe", never guessed. A build that leaves
no AmigaOS program in OUT, loose or in an archive it packed there, is "no-output". Nothing is published: each output stays in WORK/<repo>/out for the
repo's own release route. Report lines: repo, result (built / failed / no-recipe / no-output), seconds, out,
log, head, stove, and whether OUT carries libpthread.

Runs unattended: no prompts, one log per repo, the report rewritten after every repo so a stopped run shows
where it got to, and a repo already "built" at the same head on the same stove is skipped (--again builds it
anyway). Needs gh (signed in), git, python3, and lha or 7z for .lha archives.
MIT, Copyright (c) 2026 AmiCradle Team.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
MARKER = b"pthread thread #"
HUNK = b"\x00\x00\x03\xf3"          # HUNK_HEADER: an AmigaOS executable or library
# GFOpenAmigaGCC 16.2.0-open8 (GCC 0019, the fold-mem-offsets wrong-code fix) became Cradle's os32-gcc16 at
# 14 Nov 2026 18:55 UTC (STOVE.json "upgraded" on daletop). A 68040/68060 program built at -O2 or -O3 before
# that, on open6 or open7, can carry the bad stores; one released before it was built before it.
FMO_FIXED = "2026-11-14T19:00:00Z"
ARCHIVES = (".lha", ".lzh", ".zip", ".tar.gz", ".tgz", ".tar.xz", ".tar.bz2", ".tar")
DEFAULT_RECIPES = ("package/build-amiga.sh", "build-amiga.sh")


# --- pure parts (tests/test_pthread_users.py) ------------------------------------------------------------

def carries_libpthread(folder: Path) -> list[str]:
    """The files under folder (relative paths, sorted) whose bytes hold libpthread's text."""
    hits = []
    for p in sorted(folder.rglob("*")):
        if p.is_file() and not p.is_symlink():
            try:
                if MARKER in p.read_bytes():
                    hits.append(str(p.relative_to(folder)))
            except OSError:
                pass
    return hits


def amiga_programs(folder: Path) -> list[str]:
    """The files under folder (relative paths, sorted) that are AmigaOS hunk executables or libraries."""
    hits = []
    for p in sorted(folder.rglob("*")):
        if p.is_file() and not p.is_symlink():
            try:
                with open(p, "rb") as f:
                    if f.read(4) == HUNK:
                        hits.append(str(p.relative_to(folder)))
            except OSError:
                pass
    return hits


def built_programs(out: Path) -> tuple[list[str], list[str]]:
    """What a build left in out: its AmigaOS programs, and those of them that carry libpthread. A package build
    leaves its programs packed (NAME-VERSION-68040.lha, a drawer .tar for a lab) with the drawer it packed
    elsewhere, so every archive under out (outside .git folders) is unpacked and its members counted too, as
    "ARCHIVE:member". An archive that can't be unpacked counts for nothing."""
    progs, pt = amiga_programs(out), carries_libpthread(out)
    arcs = [p for p in sorted(out.rglob("*")) if p.is_file() and not p.is_symlink() and is_archive(p.name)
            and ".git" not in p.relative_to(out).parts]
    if arcs:
        with tempfile.TemporaryDirectory(dir=out.parent) as tmp:
            for i, arc in enumerate(arcs):
                into, name = Path(tmp) / str(i), str(arc.relative_to(out))
                try:
                    unpack(arc, into)
                except Exception as e:  # noqa: BLE001 - a broken archive is not output, never a crash
                    print(f"  {name}: not unpacked ({e})", flush=True)
                    continue
                progs += [f"{name}:{h}" for h in amiga_programs(into)]
                pt += [f"{name}:{h}" for h in carries_libpthread(into)]
                shutil.rmtree(into, ignore_errors=True)
    return progs, pt


def is_archive(name: str) -> bool:
    n = name.lower()
    return any(n.endswith(s) for s in ARCHIVES)


def unpack(archive: Path, into: Path) -> None:
    """Unpacks archive into into; nothing is written outside it."""
    into.mkdir(parents=True, exist_ok=True)
    n = archive.name.lower()
    if n.endswith(".zip"):
        with zipfile.ZipFile(archive) as z:
            for m in z.infolist():
                target = (into / m.filename).resolve()
                if into.resolve() in target.parents or target == into.resolve():
                    z.extract(m, into)
    elif any(n.endswith(s) for s in (".tar.gz", ".tgz", ".tar.xz", ".tar.bz2", ".tar")):
        with tarfile.open(archive) as t:
            try:
                t.extractall(into, filter="data")
            except TypeError:  # Python before 3.12 without the filter backport
                base = into.resolve()
                t.extractall(into, members=[m for m in t.getmembers() if (m.isfile() or m.isdir())
                                            and base in (base / m.name).resolve().parents])
    elif n.endswith((".lha", ".lzh")):
        if shutil.which("lha"):
            cmd = ["lha", "-xqw=" + str(into), str(archive)]
        elif shutil.which("7z"):
            cmd = ["7z", "x", "-y", "-o" + str(into), str(archive)]
        else:
            raise RuntimeError("no lha or 7z to unpack " + archive.name)
        subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    else:
        raise ValueError("not an archive: " + archive.name)


def read_tsv(path: Path) -> list[list[str]]:
    if not path.is_file():
        return []
    rows = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.strip() and not line.startswith("#"):
            rows.append(line.split("\t"))
    return rows


def write_tsv(path: Path, header: str, rows: list[list[str]]) -> None:
    tmp = path.with_suffix(path.suffix + ".part")
    tmp.write_text("# " + header + "\n" + "".join("\t".join(r) + "\n" for r in rows), encoding="utf-8")
    tmp.replace(path)


def users(list_rows: list[list[str]], why: str = "both", fixed: str = FMO_FIXED) -> list[str]:
    """The repos to rebuild, in the list's order. why "pthread": the scan found libpthread in their release;
    "fmo": their release has AmigaOS programs and was published before open8 (fixed) or its notes name open6 or
    open7; "both": either."""
    out = []
    for r in list_rows:
        pt = len(r) > 2 and r[2] == "yes"
        old = (len(r) > 4 and r[4] != "" and r[4] < fixed) or (len(r) > 6 and r[6] == "yes")
        fmo = len(r) > 5 and r[5] == "yes" and old
        if (why in ("pthread", "both") and pt) or (why in ("fmo", "both") and fmo):
            out.append(r[0])
    return out


def recipe_for(repo: str, clone: Path, recipes: dict[str, str]) -> str | None:
    """The command that builds repo: recipes.tsv's, else the first default script the clone has."""
    if repo in recipes:
        return recipes[repo]
    for s in DEFAULT_RECIPES:
        if (clone / s).is_file():
            return "sh " + s
    return None


def stove_identity(stove: Path) -> str:
    """What the stove says it is: STOVE.json's release, else its compiler's --version line."""
    j = stove / "STOVE.json"
    if j.is_file():
        try:
            rel = json.loads(j.read_text(encoding="utf-8")).get("release")
            if rel:
                return rel
        except ValueError:
            pass
    gcc = stove / "prefix" / "bin" / "m68k-amigaos-gcc"
    if gcc.is_file():
        out = subprocess.run([str(gcc), "--version"], capture_output=True, text=True).stdout
        return out.splitlines()[0] if out else ""
    return ""


def already_built(report: list[list[str]], repo: str, head: str, stove_id: str) -> bool:
    return any(r[0] == repo and r[1] == "built" and len(r) > 6 and r[5] == head and r[6] == stove_id
               for r in report)


# --- GitHub and git ------------------------------------------------------------------------------------

def gh_json(args: list[str]):
    out = subprocess.run(["gh", *args], capture_output=True, text=True, check=True).stdout
    return json.loads(out) if out.strip() else None


def list_repos(owner: str) -> list[str]:
    data = gh_json(["repo", "list", owner, "--limit", "4000", "--no-archived", "--json", "name"])
    return sorted(d["name"] for d in data)


def newest_published(releases: list[dict]) -> dict | None:
    """The newest release that was published, pre-releases included, from GitHub's list (newest first). A draft
    is skipped: it has no git tag until it is published, so what it names can't be checked out (and nothing shipped
    from it). The list puts drafts first, so a repo with a draft in hand looked as if its tag had gone."""
    return next((r for r in releases or [] if not r.get("draft")), None)


def newest_release(owner: str, repo: str):
    """(tag, [asset names], published_at, notes) of the newest published release, pre-releases included; None
    when none."""
    try:
        rel = newest_published(gh_json(["api", f"repos/{owner}/{repo}/releases?per_page=30"]))
    except subprocess.CalledProcessError:
        return None
    if not rel:
        return None
    return (rel["tag_name"], [a["name"] for a in rel.get("assets", [])],
            rel.get("published_at") or rel.get("created_at") or "", rel.get("body") or "")


def names_old_stove(notes: str) -> bool:
    """The release's notes say it was built on open6 or open7 (a named old stove stays on the machines, so a
    release published after open8 can still have been built on one)."""
    return re.search(r"(?<![\w.])(?:16\.2\.0-)?open[67](?![\w])", notes) is not None


def scan(a) -> int:
    owner, work = a.owner, Path(a.work)
    work.mkdir(parents=True, exist_ok=True)
    names = [l.strip() for l in Path(a.repos).read_text().splitlines() if l.strip()] if a.repos else list_repos(owner)
    out = Path(a.out)
    rows = [r for r in read_tsv(out) if r[0] in names] if a.resume else []
    done = {r[0] for r in rows}
    for i, repo in enumerate(names, 1):
        if repo in done:
            continue
        rel = newest_release(owner, repo)
        if rel is None:
            rows.append([repo, "", "no-release", "", "", ""])
        else:
            tag, assets, published, notes = rel
            arcs = [n for n in assets if is_archive(n)]
            with tempfile.TemporaryDirectory(dir=work) as tmp:
                t = Path(tmp)
                try:
                    hits, progs = [], 0
                    for n in arcs:
                        subprocess.run(["gh", "release", "download", tag, "-R", f"{owner}/{repo}", "-p", n,
                                        "-D", str(t / "dl")], check=True, capture_output=True)
                        unpack(t / "dl" / n, t / "x" / n)
                        hits += [f"{n}:{h}" for h in carries_libpthread(t / "x" / n)]
                        progs += len(amiga_programs(t / "x" / n))
                        (t / "dl" / n).unlink(missing_ok=True)
                        shutil.rmtree(t / "x" / n, ignore_errors=True)
                    rows.append([repo, tag, "yes" if hits else "no", " ".join(hits), published,
                                 "yes" if progs else "no", "yes" if names_old_stove(notes) else "no"])
                except Exception as e:  # one repo's trouble never stops the scan
                    rows.append([repo, tag, "error", str(e)[:200], published, ""])
        print(f"[{i}/{len(names)}] {repo}: {rows[-1][2]}", flush=True)
        write_tsv(out, "repo\ttag\tcarries libpthread\tfiles\tpublished\thas AmigaOS programs\tnotes name open6/7", rows)
    print(f"{len(users(rows, 'pthread'))} of {len(rows)} repos carry libpthread; "
          f"{len(users(rows, 'fmo'))} have AmigaOS programs released before open8 ({FMO_FIXED}); "
          f"{len(users(rows))} to rebuild in all: {out}")
    return 0


def _fetch(owner: str, repo: str, clone: Path, lf, ref: str = "HEAD") -> int:
    """Clones repo (depth 1) if it isn't there, then puts the clone at ref (the release's tag, refs/tags/T, or
    the default branch's HEAD) with nothing left of an earlier build; output into lf."""
    def run(cmd):
        lf.write("$ " + " ".join(cmd) + "\n"); lf.flush()
        return subprocess.run(cmd, stdout=lf, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL).returncode
    if not (clone / ".git").is_dir():
        rc = run(["gh", "repo", "clone", f"{owner}/{repo}", str(clone), "--", "-q", "--depth", "1"])
        if rc:
            return rc
    return run(["git", "-C", str(clone), "fetch", "-q", "--depth", "1", "origin", ref]) or \
        run(["git", "-C", str(clone), "reset", "-q", "--hard", "FETCH_HEAD"]) or \
        run(["git", "-C", str(clone), "clean", "-qfdx"])


def release_ref(row: list[str] | None) -> str:
    """What to build: the scanned release's tag (what shipped, often on a branch not yet merged), else HEAD."""
    if row and len(row) > 1 and row[1]:
        return "refs/tags/" + row[1]
    return "HEAD"


def rebuild(a) -> int:
    owner, work, stove = a.owner, Path(a.work), Path(a.stove).expanduser().resolve()
    stove_id = stove_identity(stove)
    if not stove_id:
        print(f"{stove}: not a stove (no STOVE.json release, no prefix/bin/m68k-amigaos-gcc)")
        return 2
    listed = read_tsv(Path(a.list))
    by_repo = {r[0]: r for r in listed}
    repos = a.only or users(listed, a.why)
    recipes = {r[0]: r[1] for r in read_tsv(Path(a.recipes)) if len(r) > 1} if a.recipes else {}
    report_path = Path(a.report)
    report = read_tsv(report_path)
    work.mkdir(parents=True, exist_ok=True)
    print(f"stove {stove} ({stove_id}); {len(repos)} repos")
    failed = 0
    for i, repo in enumerate(repos, 1):
        clone, log = work / repo / "src", work / repo / "build.log"
        out = work / repo / "out"
        clone.parent.mkdir(parents=True, exist_ok=True)
        t0 = time.time()
        with open(work / repo / "fetch.log", "w", encoding="utf-8") as lf:
            rc = _fetch(owner, repo, clone, lf, "HEAD" if a.head else release_ref(by_repo.get(repo)))
        head = subprocess.run(["git", "-C", str(clone), "rev-parse", "HEAD"], capture_output=True,
                              text=True).stdout.strip() if rc == 0 else ""
        if rc == 0 and not a.again and already_built(report, repo, head, stove_id):
            print(f"[{i}/{len(repos)}] {repo}: built already at {head[:8]} on {stove_id}", flush=True)
            continue
        cmd = recipe_for(repo, clone, recipes) if rc == 0 else None
        if rc != 0:
            result, log = "failed", work / repo / "fetch.log"
        elif cmd is None:
            result = "no-recipe"
        else:
            shutil.rmtree(out, ignore_errors=True)
            out.mkdir(parents=True)
            env = dict(os.environ, STOVE=str(stove), OUT=str(out), OS32_GCC16=str(stove), REBUILD=str(HERE),
                       PATH=f"{stove}/prefix/bin:{os.environ.get('PATH', '')}")
            with open(log, "w", encoding="utf-8") as lf:
                lf.write(f"$ {cmd}   (STOVE={stove} OUT={out})\n"); lf.flush()
                rc = subprocess.run(cmd, cwd=clone, env=env, shell=True, stdout=lf, stderr=subprocess.STDOUT,
                                    stdin=subprocess.DEVNULL).returncode
            progs, pt_files = built_programs(out) if rc == 0 else ([], [])
            if rc != 0:
                result = "failed"
            elif not progs:
                result = "no-output"
            else:
                result = "built"
        secs = str(int(time.time() - t0))
        pt = "yes" if result == "built" and pt_files else "no"
        report = [r for r in report if r[0] != repo] + [[repo, result, secs, str(out), str(log), head, stove_id, pt]]
        write_tsv(report_path, "repo\tresult\tseconds\tout\tlog\thead\tstove\tlibpthread", report)
        failed += result != "built"
        print(f"[{i}/{len(repos)}] {repo}: {result} ({secs} s)", flush=True)
    print(f"report: {report_path}; {failed} not built")
    return 1 if failed else 0


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("scan")
    s.add_argument("--owner", default="DalsinAI")
    s.add_argument("--repos", help="file of repo names, one a line (default: every repo of the owner)")
    s.add_argument("--work", default=os.path.expanduser("~/AmiCradle-dev/scratch/pthread-users"))
    s.add_argument("--out", default="pthread-users.tsv")
    s.add_argument("--resume", action="store_true", help="keep the repos --out already has")
    r = sub.add_parser("rebuild")
    r.add_argument("--owner", default="DalsinAI")
    r.add_argument("--stove", required=True)
    r.add_argument("--list", default="pthread-users.tsv")
    r.add_argument("--recipes", default=str(Path(__file__).with_name("recipes.tsv")))
    r.add_argument("--work", default=os.path.expanduser("~/AmiCradle-dev/scratch/pthread-rebuild"))
    r.add_argument("--report", default="rebuild-report.tsv")
    r.add_argument("--only", nargs="*")
    r.add_argument("--why", choices=("both", "pthread", "fmo"), default="both",
                   help="which repos of the list: libpthread carriers, programs released before open8, or both")
    r.add_argument("--again", action="store_true")
    r.add_argument("--head", action="store_true",
                   help="build the default branch's head, not the release's tag the scan found")
    a = p.parse_args(argv)
    return scan(a) if a.cmd == "scan" else rebuild(a)


if __name__ == "__main__":
    sys.exit(main())
