#!/usr/bin/env python3
"""Unit tests for run-open9-rebuild.sh: a fake stove, gh and pthread_users.py, no network.
python3 -m unittest test_run_open9_rebuild.py"""
import os
import shutil
import socket
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPT = HERE / "run-open9-rebuild.sh"
HOST = subprocess.run(["hostname", "-s"], capture_output=True, text=True).stdout.strip() or socket.gethostname()

FAKE_REBUILD = """import sys, time
args = sys.argv[1:]
report = args[args.index("--report") + 1]
open(report, "w").write("repo\\tresult\\nalpha\\tbuilt\\nbeta\\tfailed\\ngamma\\tbuilt\\n")
print("fake rebuild", " ".join(args), flush=True)
time.sleep(30)
"""


def exe(path: Path, text: str):
    path.write_text(text)
    path.chmod(0o755)


class Run(unittest.TestCase):
    def setUp(self):
        self._t = tempfile.TemporaryDirectory()
        t = self.t = Path(self._t.name)
        self.bin = t / "bin"
        self.bin.mkdir()
        exe(self.bin / "gh", "#!/bin/sh\nexit ${GH_RC:-0}\n")
        self.stove = t / "stove"
        (self.stove / "prefix" / "bin").mkdir(parents=True)
        self.gcc(open9=True)
        self.list = t / "pthread-users.tsv"
        self.list.write_text("repo\ttag\nalpha\tv1\nbeta\tv2\ngamma\tv3\n")
        self.rb = t / "rebuild"
        self.rb.mkdir()
        shutil.copy(SCRIPT, self.rb / SCRIPT.name)
        (self.rb / "pthread_users.py").write_text(FAKE_REBUILD)
        self.work = t / "work"
        self.env = dict(os.environ, PATH=f"{self.bin}:{os.environ['PATH']}", REBUILD_HOST=HOST,
                        STOVE=str(self.stove), LIST=str(self.list), WORK=str(self.work))

    def tearDown(self):
        self.run_it("stop")
        self._t.cleanup()

    def gcc(self, open9: bool):
        rel = "16.2.0-open9" if open9 else "16.2.0-open8"
        exe(self.stove / "prefix" / "bin" / "m68k-amigaos-gcc",
            f"#!/bin/sh\necho 'm68k-amigaos-gcc (GFOpenAmigaGCC {rel}) 16.2.0'\n")

    def run_it(self, *args, **env):
        return subprocess.run(["bash", str(self.rb / SCRIPT.name), *args], capture_output=True, text=True,
                              env=dict(self.env, **env))

    def test_other_host_stops(self):
        r = self.run_it("--dry-run", REBUILD_HOST="not-" + HOST)
        self.assertEqual(r.returncode, 2)
        self.assertIn("not not-" + HOST, r.stderr)

    def test_open8_stove_stops(self):
        self.gcc(open9=False)
        r = self.run_it("--dry-run")
        self.assertEqual(r.returncode, 2)
        self.assertIn("not 16.2.0-open9", r.stderr)

    def test_no_list_stops(self):
        self.list.unlink()
        r = self.run_it("--dry-run")
        self.assertEqual(r.returncode, 2)
        self.assertIn("no list", r.stderr)

    def test_gh_signed_out_stops(self):
        r = self.run_it("--dry-run", GH_RC="1")
        self.assertEqual(r.returncode, 2)
        self.assertIn("gh is not signed in", r.stderr)

    def test_dry_run_prints_command_and_starts_nothing(self):
        r = self.run_it("--dry-run", "--only", "alpha")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("16.2.0-open9", r.stdout)
        self.assertIn("3 repos scanned", r.stdout)
        self.assertIn("rebuild --stove", r.stdout)
        self.assertIn("--only alpha", r.stdout)
        self.assertFalse(self.work.exists())  # a dry run writes nothing

    def test_start_status_second_start_stop(self):
        r = self.run_it()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("started, pid", r.stdout)
        for _ in range(50):
            if (self.work / "rebuild-report.tsv").exists():
                break
            time.sleep(0.1)
        s = self.run_it("status")
        self.assertIn("running, pid", s.stdout)
        self.assertIn("3 done:", s.stdout)
        self.assertIn("built 2", s.stdout)
        self.assertIn("failed 1", s.stdout)
        again = self.run_it()
        self.assertEqual(again.returncode, 2)
        self.assertIn("running already", again.stderr)
        stop = self.run_it("stop")
        self.assertIn("stopped pid", stop.stdout)
        time.sleep(0.3)
        self.assertIn("not running", self.run_it("status").stdout)
        log = (self.work / "rebuild.log").read_text()
        self.assertIn("start", log)
        self.assertIn("fake rebuild rebuild --stove", log)


if __name__ == "__main__":
    unittest.main()
