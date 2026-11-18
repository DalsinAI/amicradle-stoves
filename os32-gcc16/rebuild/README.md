# Rebuilding the programs open9 has to rebuild

Two reasons a shipped program needs building again on the open9 stove:

- **libpthread** (open9's fix). See below.
- **fold-mem-offsets** (GCC 0019, fixed from open8 and kept in open9). open6 and open7 could put a
  memory-to-memory store (`move.b (a1),2(a0)`) 8 bytes early at `-O2`/`-O3` with `-m68040`/`-m68060`, in any
  68k program, threads or not. Cradle's stove has been open8 since 14 Nov 2026 18:55 UTC, so every release with
  AmigaOS programs published before then was built on open6 or open7. `scan` records each release's publish time
  whether it holds AmigaOS hunk programs, and whether its notes name open6 or open7 (a named old stove stays on the machines, so a later release can still have been built on one: the Atlas batch of 17 Nov says "native os32-gcc16-open6 build"); `rebuild --why both` (the default) takes both groups,
  `--why pthread` or `--why fmo` one of them.

## libpthread

Programs link libpthread statically, so a fix in it (GFOpenAmigaGCC 16.2.0-open9: every `pthread_cond_signal`
wakes a thread that is still waiting, aros-stuff 0011) reaches a program only when it is linked again on the new
stove. libpthread is one object, `pthread.o`: a program that calls any pthread function, or uses
`std::thread`, `std::condition_variable` or `std::async` (libstdc++ calls into it), carries all of it, and with
it the text `pthread thread #%ld`. `pthread_users.py` uses that text to tell from what was really shipped which
programs carry it, then rebuilds those. It needs no one watching.

On daletop (gh signed in), after the open9 stove is in:

```sh
cd ~/AmiCradle-dev/scratch/pthread-users
python3 pthread_users.py scan --out pthread-users.tsv          # every DalsinAI repo's newest release
python3 pthread_users.py rebuild --stove ~/AmiCradle/kitchen/stoves/os32-gcc16 \
    --list pthread-users.tsv --report rebuild-report.tsv
```

- `scan` writes one line per repo: repo, newest release tag, `yes`/`no`/`no-release`/`error`, the files
  in the release that carry libpthread, the release's publish time, and `yes`/`no` AmigaOS programs. `--resume` keeps the repos already in the file.
- `rebuild` builds what shipped: each repo at its scanned release's tag (many of those are on a branch not yet
  merged; `--head` takes the default branch instead). It clones (or updates) each repo under `~/AmiCradle-dev/scratch/pthread-rebuild/<repo>/src` and
  runs its recipe there with `STOVE`, `OS32_GCC16` and `OUT` set: `recipes.tsv`'s line for the repo, else
  `package/build-amiga.sh`, else `build-amiga.sh`. A repo with neither is `no-recipe` (add a line to
  `recipes.tsv`), never guessed. A build that leaves no AmigaOS program in `OUT` is `no-output`. The report
  (`repo, result, seconds, out, log, head, stove, libpthread`) is rewritten after every repo; a repo already `built` at the
  same head on the same stove is skipped, so a stopped run carries on where it was (`--again` rebuilds).
- Nothing is published. Each rebuilt program goes out through its own repo's release route.

`python3 -m unittest test_pthread_users.py` (no network, no gh, no stove): 18 tests.
