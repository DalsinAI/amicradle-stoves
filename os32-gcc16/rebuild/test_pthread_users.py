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

PTHREAD = b"\x4e\x75junk" + pu.MARKER + b"%ld\x00more"


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
        rows = [["a", "v1", "yes", "A.lha:C/A"], ["b", "v2", "no", ""], ["c", "", "no-release", ""],
                ["d", "v3", "error", "boom"], ["e", "v4", "yes", "E.lha:E"]]
        pu.write_tsv(p, "repo\ttag\tcarries\tfiles", rows)
        self.assertEqual(pu.read_tsv(p), rows)
        self.assertEqual(pu.users(pu.read_tsv(p)), ["a", "e"])
        self.assertFalse(p.with_suffix(".tsv.part").exists())

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
        for name, script in {"good": 'printf "\\116\\165pthread thread #%%ld" > "$OUT/Prog"; test -n "$STOVE"',
                             "bad": "exit 3", "nolib": 'echo hi > "$OUT/Prog"', "none": None}.items():
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
                "--recipes", str(self.t / "none.tsv"), "--only", "good", "bad", "nolib", "none"]
        with mock.patch.object(pu.subprocess, "run", side_effect=fake_run):
            self.assertEqual(pu.main(args), 1)
            got = {r[0]: r[1] for r in pu.read_tsv(report)}
            self.assertEqual(got, {"good": "built", "bad": "failed", "nolib": "no-libpthread", "none": "no-recipe"})
            # a second run skips what is built at the same head on the same stove
            before = (self.t / "work" / "good" / "build.log").stat().st_mtime_ns
            pu.main(args)
            self.assertEqual((self.t / "work" / "good" / "build.log").stat().st_mtime_ns, before)


if __name__ == "__main__":
    unittest.main()
