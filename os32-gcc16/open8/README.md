# os32-gcc16 open8: the recipe

The os32-gcc16 16.2.0-open8 stove, made again from recorded inputs on any machine:

```sh
amicradle-ci stove assemble os32-gcc16/open8/recipe.json --out DIR [--from STORE]
amicradle-ci stove pack DIR --name os32-gcc16 --version 16.2.0-open8
```

It is open6's recipe (../open6/README.md) with one input changed: the compiler is the gfopengcc
[v16.2.0-open8](https://github.com/DalsinAI/gfopengcc/releases/tag/v16.2.0-open8) release's x86-64 archive
(`gfopenamigagcc-16.2.0-open8-x86_64-linux.tar.xz`, SHA-256
`4855915429d8d623037af5aa911b2c3dd6b3ae98eb557eb22c4e76c4fbacf31b`), open7 with GCC patch 0019, the
fold-mem-offsets fix. The parts (NDK, port-deps, kits, Open SDK, extras) are open6's, from the store, and
vasm and libnix's qsort are put in by open6's scripts. `stove-json.py` writes STOVE.json with the recipe's
release.

The Cradle machine's live open8 stove (14 Nov 2026) was made by `upgrade.sh` from the live open6 stove
instead (../README.md); this recipe is the store's way to the same compiler.
