#!/usr/bin/env python3
"""specs_merge.py: python3 os32-gcc16/tests/upgrade/test_specs_merge.py (no stove needed)."""
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
import specs_merge as sm  # noqa: E402

RELEASE = "*asm:\n%{m68040:-m68040}\n\n*lib:\n-lnix %(fpuauto)\n\n*fpuauto:\n-lfpuauto\n\n"
LIVE = RELEASE.replace("-lnix %(fpuauto)", "-lnix %(fpuauto) %(gfmalloc)") + \
    "*gfmalloc:\n%{!nogfmalloc:-lgfmalloc}\n\n*lib_libnix:\n-lnix\n-lstubs\n\n"


class Merge(unittest.TestCase):
    def test_blocks(self):
        b = sm.blocks(LIVE)
        self.assertEqual(list(b), ["asm", "lib", "fpuauto", "gfmalloc", "lib_libnix"])
        self.assertEqual(b["lib_libnix"], "*lib_libnix:\n-lnix\n-lstubs")

    def test_live_only_blocks_appended_release_kept(self):
        text, added, differ = sm.merge(LIVE, RELEASE)
        self.assertEqual(added, ["gfmalloc", "lib_libnix"])
        self.assertEqual(differ, ["lib"])
        b = sm.blocks(text)
        self.assertEqual(b["lib"], "*lib:\n-lnix %(fpuauto)")          # the release's text stays
        self.assertEqual(b["gfmalloc"], "*gfmalloc:\n%{!nogfmalloc:-lgfmalloc}")
        self.assertTrue(text.startswith(RELEASE.rstrip("\n")))

    def test_a_name_twice_is_one_name(self):
        live = RELEASE + "*lib:\n+ -lextra\n\n*gfmalloc:\n-lgfmalloc\n\n"
        b = sm.blocks(live)
        self.assertEqual(b["lib"], "*lib:\n-lnix %(fpuauto)\n\n*lib:\n+ -lextra")
        text, added, differ = sm.merge(live, RELEASE + "*lib:\n+ -lextra\n\n")
        self.assertEqual((added, differ), (["gfmalloc"], []))

    def test_nothing_to_carry_leaves_it(self):
        text, added, differ = sm.merge(RELEASE, RELEASE)
        self.assertEqual((text, added, differ), (RELEASE, [], []))

    def test_idempotent(self):
        once = sm.merge(LIVE, RELEASE)[0]
        twice, added, _ = sm.merge(LIVE, once)
        self.assertEqual(added, [])
        self.assertEqual(twice, once)

    def test_main_writes_and_keeps_before(self):
        with tempfile.TemporaryDirectory() as t:
            live, nxt = Path(t, "live"), Path(t, "specs")
            live.write_text(LIVE)
            nxt.write_text(RELEASE)
            self.assertEqual(sm.main([str(live), str(nxt), "--check"]), 0)
            self.assertEqual(nxt.read_text(), RELEASE)
            sm.main([str(live), str(nxt)])
            self.assertIn("*gfmalloc:", nxt.read_text())
            self.assertEqual(Path(t, "specs.before-merge").read_text(), RELEASE)


if __name__ == "__main__":
    unittest.main()
