#!/usr/bin/env python3
"""Unit tests for pthread_users.py: no network, no gh, no stove. python3 -m unittest test_pthread_users.py"""
import io
import json
import os
import stat
import sys
import tarfile
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
import pthread_users as pu  # noqa: E402

PTHREAD = pu.HUNK + b"\x4e\x75junk" + pu.MARKER + b"%ld\x00more"
PROGRAM = pu.HUNK + b"\x00\x00\x00\x00plain program"


class Tmp(unittest.TestCase):
    def setUp(self):
        self._t = tempfile.TemporaryDirectory()
        self.t = Path(self._t.name)

    def tearDown(self):
        self._t.cleanup()


class Carries(Tmp):
    def test_finds_only_files_with_the_text(self):
        (self.t / "C").mkdir()
        (self.t / "C" / "Game").write_bytes(PTHREAD)
        (self.t / "Game.info").write_bytes(b"icon")
        (self.t / "Readme").write_bytes(b"pthread thread")  # no '#': not libpthread's text
        self.assertEqual(pu.carries_libpthread(self.t), ["C/Game"])

    def test_amiga_programs(self):
        (self.t / "C").mkdir()
        (self.t / "C" / "Prog").write_bytes(PROGRAM)
        (self.t / "Prog.info").write_bytes(b"\xe3\x10icon")
        (self.t / "Readme").write_bytes(b"text " + pu.HUNK)       # the magic not at the start: not a program
        self.assertEqual(pu.amiga_programs(self.t), ["C/Prog"])

    def test_empty_folder(self):
        self.assertEqual(pu.carries_libpthread(self.t), [])


class Archives(Tmp):
    def test_is_archive(self):
        for n in ("A.lha", "a.LZH", "b.zip", "c.tar.gz", "d.tgz", "e.tar.xz", "f.tar.bz2", "g.tar"):
            self.assertTrue(pu.is_archive(n), n)
        for n in ("A.lha.sha256", "x.readme", "SHA256SUMS", "y.info"):
            self.assertFalse(pu.is_archive(n), n)

    def test_unpack_zip_and_find(self):
        z = self.t / "p.zip"
        with zipfile.ZipFile(z, "w") as f:
            f.writestr("Game/Game", PTHREAD)
            f.writestr("../escape", PTHREAD)  # never written outside
        pu.unpack(z, self.t / "x")
        self.assertEqual(pu.carries_libpthread(self.t / "x"), ["Game/Game"])
        self.assertFalse((self.t / "escape").exists())

    def test_unpack_tar(self):
        a = self.t / "p.tar.gz"
        with tarfile.open(a, "w:gz") as f:
            info = tarfile.TarInfo("Prog/prog")
            info.size = len(PTHREAD)
            f.addfile(info, io.BytesIO(PTHREAD))
        pu.unpack(a, self.t / "x")
        self.assertEqual(pu.carries_libpthread(self.t / "x"), ["Prog/prog"])

    def test_not_an_archive(self):
        with self.assertRaises(ValueError):
            pu.unpack(self.t / "x.readme", self.t / "x")


class Lists(Tmp):
    def test_tsv_round_trip_and_users(self):
        p = self.t / "l.tsv"
        old, new = "2026-11-10T12:00:00Z", "2026-11-16T12:00:00Z"
        rows = [["a", "v1", "yes", "A.lha:C/A", new, "yes"], ["b", "v2", "no", "", old, "yes"],
                ["c", "", "no-release", "", "", ""], ["d", "v3", "error", "boom", old, ""],
                ["e", "v4", "yes", "E.lha:E", old, "yes"], ["f", "v5", "no", "", new, "yes"],
                ["g", "v6", "no", "", old, "no"], ["h", "v7", "yes", "H.lha:H"]]   # a scan from before fmo
        pu.write_tsv(p, "repo\ttag\tcarries\tfiles\tpublished\tprograms", rows)
        self.assertEqual(pu.read_tsv(p), rows)
        got = pu.read_tsv(p)
        self.assertEqual(pu.users(got, "pthread"), ["a", "e", "h"])
        self.assertEqual(pu.users(got, "fmo"), ["b", "e"])        # programs, released before open8
        self.assertEqual(pu.users(got), ["a", "b", "e", "h"])
        self.assertEqual(pu.users(got, "fmo", fixed="2026-11-01T00:00:00Z"), [])
        self.assertFalse(p.with_suffix(".tsv.part").exists())
        late_old = [["i", "v8", "no", "", new, "yes", "yes"], ["j", "v9", "no", "", new, "yes", "no"]]
        self.assertEqual(pu.users(late_old, "fmo"), ["i"])               # built on a named open6 stove

    def test_names_old_stove(self):
        for t in ("native os32-gcc16-open6 build", "GFOpenAmigaGCC 16.2.0-open7", "built on open6."):
            self.assertTrue(pu.names_old_stove(t), t)
        for t in ("built on open8", "open60 things", "reopen6", "16.2.0-open9", ""):
            self.assertFalse(pu.names_old_stove(t), t)

    def test_release_ref(self):
        self.assertEqual(pu.release_ref(["r", "v1.0-rc1", "yes"]), "refs/tags/v1.0-rc1")
        self.assertEqual(pu.release_ref(["r", "", "no-release"]), "HEAD")
        self.assertEqual(pu.release_ref(None), "HEAD")

    def test_missing_file_is_empty(self):
        self.assertEqual(pu.read_tsv(self.t / "none.tsv"), [])


class Recipes(Tmp):
    def test_table_first_then_defaults_then_none(self):
        (self.t / "package").mkdir()
        (self.t / "package" / "build-amiga.sh").write_text("")
        (self.t / "build-amiga.sh").write_text("")
        self.assertEqual(pu.recipe_for("r", self.t, {"r": "make -f Makefile.amiga"}), "make -f Makefile.amiga")
        self.assertEqual(pu.recipe_for("r", self.t, {}), "sh package/build-amiga.sh")
        (self.t / "package" / "build-amiga.sh").unlink()
        self.assertEqual(pu.recipe_for("r", self.t, {}), "sh build-amiga.sh")
        (self.t / "build-amiga.sh").unlink()
        self.assertIsNone(pu.recipe_for("r", self.t, {}))

    def test_shipped_recipes_file_parses(self):
        f = Path(pu.__file__).with_name("recipes.tsv")
        for row in pu.read_tsv(f):
            self.assertEqual(len(row), 2, row)
            self.assertTrue(row[0] and row[1].strip(), row)


class MakefileRecipe(Tmp):
    """recipes/amiga-makefile.sh with a makefile like the ports' amiga/Makefile.amigaos."""
    MF = ("STOVE ?= /old/os32-gcc16-open6\nBUILD = build\nOUT = $(BUILD)/Game\n"
          "all: ; mkdir -p $(OUT) && printf '%s' \"$(STOVE)\" > $(OUT)/stove && printf '\\000\\000\\003\\363' > $(OUT)/Game\n"
          "dist: all ; mkdir -p dist/Game && cp $(OUT)/Game dist/Game/\n")

    def make(self, *args, stove_arg="", src_from=""):
        import subprocess
        (self.t / "src").mkdir(exist_ok=True)
        (self.t / "src" / "Makefile.amigaos").write_text(self.MF)
        out = self.t / "out"
        out.mkdir(exist_ok=True)
        env = dict(os.environ, STOVE="/new/stove", OUT=str(out), STOVE_ARG=stove_arg, FROM=src_from)
        return subprocess.run(["sh", str(pu.HERE / "recipes" / "amiga-makefile.sh"), "Makefile.amigaos", *args],
                              cwd=self.t / "src", env=env, capture_output=True, text=True), out

    def test_builds_with_the_given_stove_and_copies_out(self):
        r, out = self.make()
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual((out / "Game" / "stove").read_text(), "/new/stove")   # not the makefile's open6 default
        self.assertEqual(pu.amiga_programs(out), ["Game/Game"])

    def test_target_vars_and_prefix(self):
        r, out = self.make("all", "BUILD=b2", stove_arg="prefix")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual((out / "Game" / "stove").read_text(), "/new/stove/prefix")
        self.assertTrue((self.t / "src" / "b2" / "Game" / "Game").is_file())

    def test_from_names_the_folder(self):
        self.MF = "all: ; mkdir -p build/amigaos && printf '\\000\\000\\003\\363' > build/amigaos/xrick\n"
        r, out = self.make(src_from="build/amigaos")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(pu.amiga_programs(out), ["amigaos/xrick"])
        r, _ = self.make()                          # no $(OUT), no dist/, no FROM: fails, never guesses
        self.assertNotEqual(r.returncode, 0)

    def test_a_failing_make_fails(self):
        self.MF = "all: ; exit 4\n"
        r, _ = self.make()
        self.assertNotEqual(r.returncode, 0)


class Stove(Tmp):
    def test_identity_from_stove_json(self):
        (self.t / "STOVE.json").write_text(json.dumps({"release": "GFOpenAmigaGCC 16.2.0-open9"}))
        self.assertEqual(pu.stove_identity(self.t), "GFOpenAmigaGCC 16.2.0-open9")

    def test_identity_from_compiler(self):
        b = self.t / "prefix" / "bin"
        b.mkdir(parents=True)
        g = b / "m68k-amigaos-gcc"
        g.write_text("#!/bin/sh\necho 'm68k-amigaos-gcc (GFOpenAmigaGCC 16.2.0-open9) 16.2.0b'\n")
        g.chmod(g.stat().st_mode | stat.S_IEXEC)
        self.assertIn("16.2.0-open9", pu.stove_identity(self.t))

    def test_not_a_stove(self):
        self.assertEqual(pu.stove_identity(self.t), "")

    def test_already_built(self):
        rep = [["a", "built", "9", "o", "l", "abc", "open9"], ["b", "failed", "9", "o", "l", "abc", "open9"]]
        self.assertTrue(pu.already_built(rep, "a", "abc", "open9"))
        self.assertFalse(pu.already_built(rep, "a", "def", "open9"))
        self.assertFalse(pu.already_built(rep, "a", "abc", "open8"))
        self.assertFalse(pu.already_built(rep, "b", "abc", "open9"))


class RebuildRun(Tmp):
    """rebuild end to end with a local git repo in place of GitHub and a fake stove."""

    def test_built_failed_norecipe_nolib(self):
        import subprocess
        stove = self.t / "stove"
        stove.mkdir()
        (stove / "STOVE.json").write_text(json.dumps({"release": "GFOpenAmigaGCC 16.2.0-open9"}))
        srcs = {}
        for name, script in {"good": 'printf "\\000\\000\\003\\363pthread thread #%%ld" > "$OUT/Prog"; test -n "$STOVE"',
                             "bad": "exit 3", "nolib": 'printf "\\000\\000\\003\\363plain" > "$OUT/Prog"', "empty": "true", "none": None}.items():
            r = self.t / "remote" / name
            r.mkdir(parents=True)
            if script is not None:
                (r / "package").mkdir()
                (r / "package" / "build-amiga.sh").write_text(script + "\n")
            (r / "README").write_text(name)
            for c in (["init", "-q"], ["add", "-A"],
                      ["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "x"]):
                subprocess.run(["git", "-C", str(r), *c], check=True)
            srcs[name] = r

        def fake_run(cmd, **kw):
            if isinstance(cmd, list) and cmd[:3] == ["gh", "repo", "clone"]:
                cmd = ["git", "clone", "-q", str(srcs[cmd[3].split("/")[1]]), cmd[4]]
            return real_run(cmd, **kw)
        real_run = subprocess.run
        report = self.t / "report.tsv"
        args = ["rebuild", "--stove", str(stove), "--work", str(self.t / "work"), "--report", str(report),
                "--recipes", str(self.t / "none.tsv"), "--only", "good", "bad", "nolib", "empty", "none"]
        with mock.patch.object(pu.subprocess, "run", side_effect=fake_run):
            self.assertEqual(pu.main(args), 1)
            rows = pu.read_tsv(report)
            got = {r[0]: r[1] for r in rows}
            self.assertEqual(got, {"good": "built", "bad": "failed", "nolib": "built", "empty": "no-output",
                                   "none": "no-recipe"})
            self.assertEqual({r[0]: r[7] for r in rows if r[1] == "built"}, {"good": "yes", "nolib": "no"})
            # a second run skips what is built at the same head on the same stove
            before = (self.t / "work" / "good" / "build.log").stat().st_mtime_ns
            pu.main(args)
            self.assertEqual((self.t / "work" / "good" / "build.log").stat().st_mtime_ns, before)


if __name__ == "__main__":
    unittest.main()
