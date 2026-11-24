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
  runs its recipe there with `STOVE`, `OS32_GCC16`, `OUT` and `REBUILD` (this folder) set: `recipes.tsv`'s line for the repo, else
  `package/build-amiga.sh`, else `build-amiga.sh`. A repo with neither is `no-recipe` (add a line to
  `recipes.tsv`), never guessed. A build that leaves no AmigaOS program in `OUT` is `no-output`: loose files count, and so do the
  members of every archive the build packed there (most `package/build-amiga.sh` leave only
  `NAME-VERSION-68040.lha`, and keep the drawer they packed in their own `build/` or `dist/`); libpthread is looked
  for in both. The report
  (`repo, result, seconds, out, log, head, stove, libpthread`) is rewritten after every repo; a repo already `built` at the
  same head on the same stove is skipped, so a stopped run carries on where it was (`--again` rebuilds).
- Nothing is published. Each rebuilt program goes out through its own repo's release route.

## Recipes

`recipes.tsv` holds a line for each listed repo whose release tag has no `package/build-amiga.sh` or
`build-amiga.sh` (18 Nov: 16 of the 33). `recipes/amiga-makefile.sh MAKEFILE [TARGET] [NAME=VALUE ...]` builds a
port with its own Amiga makefile: those makefiles default `STOVE` to the old `os32-gcc16-open6` path, so it puts
the rebuild's stove on make's command line, then copies the makefile's `$(OUT)` folder (else `dist/`, or
`FROM=DIR`) into `$OUT`. `recipes/opengpu-sdk.sh COMMAND` runs a GFOpenGPU port's build with `OPENUP_SDK`,
`OPENGL_KIT` and `OPENGPU_SDK` made from the stove's own GFOpenGPU SDK (amigaserioussam, amiganeverball).
`recipes/neverball.sh` gathers what amiganeverball's README gathers by hand: Neverball at `build.sh`'s pin, cloned
beside the clone, and the official `data-1.6.0.pk3` (`NEVERBALL_DATA_PK3`, else `$HOME/.cache/neverball/`).
`recipes/beside.sh URL DIR [FILE] -- COMMAND` clones another repository beside the clone as it was when the
clone's HEAD was committed (gfopenputty's `../openamigatls`, now DalsinAI/gfopentls, from before its headers were
renamed gfopencrypto).

24 Nov (open9 rebuild, GF-109): recipes for amicradle-guest (its listed tag, acfind-1.4, is ACFind 1.4 and
GFOpenIndex: tools/openindex/build-amiga.sh), gfopenevent, gfopenprefs (GFOpenBlanker-1.6-rc1: the Blanker),
gfopentata (with a gfopengadtools checkout for Tata-Prefs), gfosfonts (tools/amigafont.py) and gfopengnustep (its
native probes; ffi_smoke_68040 is left out, as the stove has no libffi).

Still without a recipe, each for its own reason:
- 24 Nov, later: amigafreeciv (v3.3.90-amigaos3-rc2) and amigagrafx2 (v2.9-openup-rc2) build on `STOVE` instead of
  their pinned open3 compiler; amigafreeciv has a recipe here, amigagrafx2's tag has build-amiga.sh. The OpenSurge
  content ports (standalone-rc3) pin amigaopensurge v0.6.1.3-amigaos3-rc5, built on open9, and have recipes here.
- amigaliquidwar5 (v5.6.7-open9-rc1-test): its build-amiga.sh builds gfopenallegro's allegro4 on `STOVE` as the
  Allegro 4 SDK and the game without autotools; liquidwar.dat, which isn't compiled, comes from the open8 release
  made from the same data/ (no host Allegro 4 `dat` here), checked by SHA-256.
- amigaas2r: no compile of its own (a content port for amigaopensurge's engine), like the three OpenSurge content ports.
- amigaastromenace: its build refuses any stove but a verified 16.2.0-open8 one (scripts/verify_open8_stove.py),
  so it needs that guard moved on to open9 in the repo first. amigaopenloco: Team 1's staged stove and SDL3 SDK
  (OPENLOCO_STOVE, OPENLOCO_SDL3_SDK) and a build that runs over several calls.
  (Their tags had looked gone: `scan` took a draft release, which has no tag. It skips drafts now.)
- gfopenbrowser, gfopenasm: large or multi-part builds with their own release route; rebuild them there.

`python3 -m unittest test_pthread_users.py` (no network, no gh, no stove): 25 tests.
