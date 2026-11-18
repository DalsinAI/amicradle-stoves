# Rebuilding the programs that carry libpthread

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

- `scan` writes one line per repo: repo, newest release tag, `yes`/`no`/`no-release`/`error`, and the files
  in the release that carry libpthread. `--resume` keeps the repos already in the file.
- `rebuild` clones (or updates) each `yes` repo under `~/AmiCradle-dev/scratch/pthread-rebuild/<repo>/src` and
  runs its recipe there with `STOVE`, `OS32_GCC16` and `OUT` set: `recipes.tsv`'s line for the repo, else
  `package/build-amiga.sh`, else `build-amiga.sh`. A repo with neither is `no-recipe` (add a line to
  `recipes.tsv`), never guessed. A build whose `OUT` holds no libpthread is `no-libpthread`. The report
  (`repo, result, seconds, out, log, head, stove`) is rewritten after every repo; a repo already `built` at the
  same head on the same stove is skipped, so a stopped run carries on where it was (`--again` rebuilds).
- Nothing is published. Each rebuilt program goes out through its own repo's release route.

`python3 -m unittest test_pthread_users.py` (no network, no gh, no stove): 15 tests.
