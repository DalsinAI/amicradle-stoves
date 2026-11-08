# os32-gcc16 open6: the recipe

The os32-gcc16 16.2.0-open6 stove, made again from recorded inputs on any machine:

```sh
amicradle-ci stove assemble os32-gcc16/open6/recipe.json --out DIR [--from STORE]
amicradle-ci stove pack DIR --name os32-gcc16 --version 16.2.0-open6
```

Every input is checked by its SHA-256 and comes from the stove store
(`http://amigachromebuild:8787/store/` by default), never from an older stove:

| Input | SHA-256 | Where it comes from |
| --- | --- | --- |
| `gfopenamigagcc@16.2.0-open6` | `65f28447...57eaa7` | gfopengcc release v16.2.0-open6, x86-64 archive, as published (also fetched from the release with `gh` when the store lacks it) |
| `os32-gcc16-open6-ndk@1` | `ad5392a8...56126` | NDK 3.2 and the open NDK (`ndk/`, `OPENNDK.json`, `prefix/m68k-amigaos/ndk*`, `openndk-fd`) |
| `os32-gcc16-open6-port-deps@1` | `957086c4...0d0f3` | `prefix/m68k-amigaos/port-deps` (its `manifest.json` gives each file's SHA-256 and origin) |
| `os32-gcc16-open6-kits@1` | `a036df9e...bdde` | the OpenGPU 0.6/0.7 and GFOpenGPU 0.8 kits: `kits/` and every file their `*.files` lists name |
| `os32-gcc16-open6-extras@1` | `cdc5255d...608be` | `compat/`, `patches/`, `tools/`, `tests/` and the remaining headers |
| `vasm@2.0f` | `c84b2de1...78f49` | http://phoenix.owl.de/tags/vasm2_0f.tar.gz (`../vasm/vasm.lock`), built by `add-vasm.sh` |

After the parts, `../libnix/install-qsort.sh` replaces libnix's `qsort` in every `libnix.a` with the fixed one
(`../libnix/qsort.c`, 7 Nov 2026; see `../README.md`, "libnix's qsort"); `STOVE.json` says so under `"libnix"`.

The four parts were made once, on 6 Nov 2026, by `make-parts.py` from the stove
assembled that day (which had carried them from the retired local open6 build);
`parts.json` records them. `kits.json` is that stove's kit record, which
`stove-json.py` puts in the new `STOVE.json`.

Against the 6 Nov 2026 folder (`amicradle-ci stove diff`): 7517 files the same;
added `prefix/bin/vasmm68k_mot` and `prefix/bin/vobjdump` (game ports assemble
with them; amigachocolatedoom found vasm only in the deprecated os32 stove beside
it); `STOVE.json` rewritten (the recipe and parts instead of a time stamp); the
kit installer's backups `kits/replaced-*` left out.

vasm is free for non-commercial use, not open source: the store is on our LAN;
never put this stove, or its archive, in a release.
