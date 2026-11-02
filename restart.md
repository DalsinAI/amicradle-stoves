# Restart: AmiCradle stoves

_Written 6 October 2026 at about 23:55 UTC, while all work is paused on @SacredTrees's word (23:28 UTC). Read this first when work resumes; the newest capsule and the live PR list win if they disagree._

## What this repo is

The "stoves" that cook builds inside AmiCradle's Kitchen: GCC, binutils and the libraries each target needs (the os32 stove is bebbo gcc 6.5 plus NDK 3.2; os32-gcc16 is GCC 16).

## Where it stands

Stable. The m68k stoves live on the home PC under ~/AmiCradle/stoves and are what Main Discourse builds every Open app with. Nothing open.

## Merged lately

- #2 (4fa740f, 2026-10-06): Credit who made AmiCradle stoves: CONTRIBUTORS.md
- #1 (24813f5, 2026-10-04): Say "we" in the repository's text, not a person's name

## Open pull requests

- None.

## Next step

1. None queued. Keep the stove recipes in step with what Main Discourse actually uses.

## Waiting on @SacredTrees

- Nothing.

## Who owns it

Main Discourse (home PC builds).

## Capsules

Restart capsules for this repo's workstreams, in amicradle's `capjumps/` shelf:

- [`20261006_AmiCradle_Pause_Restart_Capsule.zip`](https://github.com/DalsinAI/amicradle/tree/main/capjumps)

Team rules that still hold: commits as SacredTrees with no co-author lines; third-party code only on "yes with review" (licence checked, commit and sha256 pinned, fetched at build, never committed); deploys with deploy_dev.py only, on a typed line.
