"""gameports/record_stove.py (the canonical copy): names the compiler, refuses no stove (BL-144)."""
from __future__ import annotations

import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPT = HERE / "record_stove.py"
SPEC = importlib.util.spec_from_file_location("record_stove", SCRIPT)
assert SPEC and SPEC.loader
rs = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(rs)
SHA = "4855915429d8d623037af5aa911b2c3dd6b3ae98eb557eb22c4e76c4fbacf31b"


def fake_stove(root: Path, version: str | None, stove_json: dict | None = None,
               provenance: dict | None = None) -> Path:
    (root / "prefix/bin").mkdir(parents=True)
    if version is not None:
        cc = root / "prefix/bin/m68k-amigaos-gcc"
        cc.write_text(f"#!/bin/sh\necho 'm68k-amigaos-gcc ({version}) 16.2.0b'\necho 'Copyright'\n")
        os.chmod(cc, 0o755)
    if stove_json is not None:
        (root / "STOVE.json").write_text(json.dumps(stove_json))
    if provenance is not None:
        (root / "provenance.json").write_text(json.dumps(provenance))
    return root


def run(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, str(SCRIPT), *args], capture_output=True, text=True)


class RecordStove(unittest.TestCase):
    def setUp(self):
        t = tempfile.TemporaryDirectory()
        self.addCleanup(t.cleanup)
        self.tmp = Path(t.name)

    def test_published_stove_is_recorded_with_its_archive(self):
        s = fake_stove(self.tmp / "open9", "GFOpenAmigaGCC 16.2.0-open9",
                       {"release": "GFOpenAmigaGCC 16.2.0-open9", "compilerArchive": {"sha256": SHA}})
        r = run("--stove", str(s))
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(r.stdout.split(), ["16.2.0-open9", SHA])
        self.assertIn("GFOpenAmigaGCC 16.2.0-open9", r.stderr)

    def test_stoves_the_old_gate_refused_now_build(self):
        cases = (  # (folder, compiler says, STOVE.json, provenance.json, expected release)
            ("local9", "GFOpenAmigaGCC 16.2.0-open9", {"release": "GFOpenAmigaGCC 16.2.0-open9"}, None,
             "16.2.0-open9"),                               # no archive SHA-256
            ("old3", "OpenAmigaGCC 16.2.0-open3", None, {"archive_sha256": "7" * 64}, "16.2.0-open3"),
            ("lie", "GFOpenAmigaGCC 16.2.0-open6", {"release": "GFOpenAmigaGCC 16.2.0-open9"}, None,
             "16.2.0-open6"),                               # the compiler's own word wins
            ("bare", "local build", None, None, "unknown"),  # no receipts at all
        )
        for name, said, sj, prov, release in cases:
            with self.subTest(name):
                r = run("--stove", str(fake_stove(self.tmp / name, said, sj, prov)))
                self.assertEqual(r.returncode, 0, r.stderr)
                self.assertEqual(r.stdout.split()[0], release)

    def test_no_archive_is_unpublished(self):
        s = fake_stove(self.tmp / "s", "GFOpenAmigaGCC 16.2.0-open5", {"release": "GFOpenAmigaGCC 16.2.0-open5"})
        self.assertEqual(run("--stove", str(s)).stdout.split(), ["16.2.0-open5", "unpublished"])

    def test_build_info_is_written(self):
        s = fake_stove(self.tmp / "os32-gcc16-open9", "GFOpenAmigaGCC 16.2.0-open9")
        self.assertEqual(run("--stove", str(s), "--out", str(self.tmp / "out")).returncode, 0)
        info = json.loads((self.tmp / "out/build-info.json").read_text())
        self.assertEqual(info["stove"], "os32-gcc16-open9")
        self.assertIn("GFOpenAmigaGCC 16.2.0-open9", info["compiler"])
        self.assertEqual(rs.record(s, self.tmp / "o2")["release"], "16.2.0-open9")
        self.assertTrue((self.tmp / "o2/build-info.json").is_file())
        self.assertEqual(run(str(s), str(self.tmp / "o3")).returncode, 0)  # the positional form

    def test_no_compiler_is_the_only_failure(self):
        r = run("--stove", str(fake_stove(self.tmp / "empty", None, {"release": "16.2.0-open9"})))
        self.assertEqual(r.returncode, 2)
        self.assertIn("no compiler", r.stderr)

    def test_old_gate_options_are_gone(self):
        s = fake_stove(self.tmp / "s", "GFOpenAmigaGCC 16.2.0-open9")
        self.assertNotEqual(run("--stove", str(s), "--min", "open9").returncode, 0)


class NoGateLeft(unittest.TestCase):
    def test_the_old_gate_is_gone(self):
        self.assertFalse((HERE / "verify_gameport_stove.py").exists())
        self.assertNotIn("verify_gameport_stove", (HERE / "README.md").read_text())


if __name__ == "__main__":
    unittest.main()
