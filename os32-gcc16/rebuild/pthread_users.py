#!/usr/bin/env python3
"""Find the DalsinAI programs that carry libpthread, and rebuild them on a new os32-gcc16 stove.

Programs link libpthread statically: a fix in it (GFOpenAmigaGCC open9's pthread_cond_signal, aros-stuff
0011) reaches a program only when it is linked again. libpthread is one object (pthread.o), so a program that
calls any pthread function carries all of it, and its text "pthread thread #%ld" (the name pthread_create gives
a new task). That text is how this script tells, from what was really shipped, which programs carry it.

    pthread_users.py scan    [--owner DalsinAI] [--repos FILE] [--work DIR] [--out pthread-users.tsv]
    pthread_users.py rebuild --stove STOVE [--list pthread-users.tsv] [--recipes recipes.tsv]
                             [--work DIR] [--report rebuild-report.tsv] [--only REPO ...] [--again]

scan: for every repo of the owner (or the names in --repos), downloads its newest release's archives (.lha,
.zip, .tar.*, .tgz), unpacks them and looks in every file for the text. Writes one line per repo: repo, tag,
"yes"/"no"/"no-release"/"error", the files that carry it. Downloads are removed as it goes.

rebuild: for every "yes" repo of the list (or --only), clones or updates it under WORK, runs its build recipe
with STOVE and OUT set (the output must land in OUT; recipes.tsv: repo <TAB> command, run in the clone; the default is
package/build-amiga.sh, then build-amiga.sh, when the repo has one), and checks the build used STOVE's
compiler and that the output still carries libpthread. A repo with no recipe is reported, never guessed.
Nothing is published: the outputs stay in WORK/<repo>/out for each repo's own release route.
Each line of the report: repo, result (built / failed / no-recipe / no-libpthread), seconds, out folder, log.

Runs unattended: no prompts, one log per repo, the report rewritten after every repo so a stopped run shows
where it got to, and a repo already "built" in the report with the same head and stove is skipped (--again
builds it anyway). Needs gh (signed in), git, python3, and lha or 7z for .lha archives.
MIT, Copyright (c) 2026 AmiCradle Team.
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time
import zipfile
from pathlib import Path

MARKER = b"pthread thread #"
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


def users(list_rows: list[list[str]]) -> list[str]:
    """The repos a scan found carrying libpthread, in the list's order."""
    return [r[0] for r in list_rows if len(r) > 2 and r[2] == "yes"]


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


def newest_release(owner: str, repo: str):
    """(tag, [asset names]) of the newest release, pre-releases included; None when there is none."""
    try:
        rel = gh_json(["api", f"repos/{owner}/{repo}/releases?per_page=1"])
    except subprocess.CalledProcessError:
        return None
    if not rel:
        return None
    return rel[0]["tag_name"], [a["name"] for a in rel[0].get("assets", [])]


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
            rows.append([repo, "", "no-release", ""])
        else:
            tag, assets = rel
            arcs = [n for n in assets if is_archive(n)]
            with tempfile.TemporaryDirectory(dir=work) as tmp:
                t = Path(tmp)
                try:
                    hits = []
                    for n in arcs:
                        subprocess.run(["gh", "release", "download", tag, "-R", f"{owner}/{repo}", "-p", n,
                                        "-D", str(t / "dl")], check=True, capture_output=True)
                        unpack(t / "dl" / n, t / "x" / n)
                        hits += [f"{n}:{h}" for h in carries_libpthread(t / "x" / n)]
                        (t / "dl" / n).unlink(missing_ok=True)
                        shutil.rmtree(t / "x" / n, ignore_errors=True)
                    rows.append([repo, tag, "yes" if hits else "no", " ".join(hits)])
                except Exception as e:  # one repo's trouble never stops the scan
                    rows.append([repo, tag, "error", str(e)[:200]])
        print(f"[{i}/{len(names)}] {repo}: {rows[-1][2]}", flush=True)
        write_tsv(out, "repo\ttag\tcarries libpthread\tfiles", rows)
    print(f"{len(users(rows))} of {len(rows)} repos carry libpthread: {out}")
    return 0


def _fetch(owner: str, repo: str, clone: Path, lf) -> int:
    """Clones repo (depth 1), or brings an earlier clone to the remote's head; output into lf."""
    def run(cmd):
        lf.write("$ " + " ".join(cmd) + "\n"); lf.flush()
        return subprocess.run(cmd, stdout=lf, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL).returncode
    if (clone / ".git").is_dir():
        return run(["git", "-C", str(clone), "fetch", "-q", "--depth", "1", "origin", "HEAD"]) or \
            run(["git", "-C", str(clone), "reset", "-q", "--hard", "FETCH_HEAD"]) or \
            run(["git", "-C", str(clone), "clean", "-qfdx"])
    return run(["gh", "repo", "clone", f"{owner}/{repo}", str(clone), "--", "-q", "--depth", "1"])


def rebuild(a) -> int:
    owner, work, stove = a.owner, Path(a.work), Path(a.stove).expanduser().resolve()
    stove_id = stove_identity(stove)
    if not stove_id:
        print(f"{stove}: not a stove (no STOVE.json release, no prefix/bin/m68k-amigaos-gcc)")
        return 2
    repos = a.only or users(read_tsv(Path(a.list)))
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
            rc = _fetch(owner, repo, clone, lf)
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
            env = dict(os.environ, STOVE=str(stove), OUT=str(out), OS32_GCC16=str(stove),
                       PATH=f"{stove}/prefix/bin:{os.environ.get('PATH', '')}")
            with open(log, "w", encoding="utf-8") as lf:
                lf.write(f"$ {cmd}   (STOVE={stove} OUT={out})\n"); lf.flush()
                rc = subprocess.run(cmd, cwd=clone, env=env, shell=True, stdout=lf, stderr=subprocess.STDOUT,
                                    stdin=subprocess.DEVNULL).returncode
            if rc != 0:
                result = "failed"
            elif not carries_libpthread(out):
                result = "no-libpthread"
            else:
                result = "built"
        secs = str(int(time.time() - t0))
        report = [r for r in report if r[0] != repo] + [[repo, result, secs, str(out), str(log), head, stove_id]]
        write_tsv(report_path, "repo\tresult\tseconds\tout\tlog\thead\tstove", report)
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
    r.add_argument("--again", action="store_true")
    a = p.parse_args(argv)
    return scan(a) if a.cmd == "scan" else rebuild(a)


if __name__ == "__main__":
    sys.exit(main())
