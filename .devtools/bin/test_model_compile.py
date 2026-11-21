#!/usr/bin/env python3
"""model_compile's command, built without running it: the bottle, the paths as Wine sees them."""
from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import model_compile as mc
import srcds


class CommandTest(unittest.TestCase):
    def test_a_path_in_the_bottle_is_on_c_and_any_other_on_z(self):
        c = srcds.BOTTLE_DIR / "drive_c"
        self.assertEqual(mc.windows_path(c / "Steam/steamapps/common/GarrysMod/bin/studiomdl.exe"),
                         r"C:\Steam\steamapps\common\GarrysMod\bin\studiomdl.exe")
        self.assertEqual(mc.windows_path(Path("/Users/x/repo/a b.qc")), r"Z:\Users\x\repo\a b.qc")

    def test_a_relative_path_is_refused(self):
        with self.assertRaises(mc.CompileError):
            mc.windows_path(Path("repo/a.qc"))

    def test_it_runs_in_the_server_bottle_never_the_operators(self):
        argv = mc.command(Path("/wine"), Path("/s/studiomdl.exe"), Path("/g"), Path("/q/v.qc"))
        self.assertEqual(argv[argv.index("--bottle") + 1], "GModServer")
        self.assertNotIn("Steam", argv[:argv.index("--cx-app")])
        self.assertEqual(argv[-1], r"Z:\q\v.qc")
        self.assertEqual(argv[argv.index("-game") + 1], r"Z:\g")

    def test_outputs_are_the_files_studiomdl_wrote(self):
        with tempfile.TemporaryDirectory() as d:
            folder = Path(d) / "models" / "tf_weapons"
            folder.mkdir(parents=True)
            for ext in (".mdl", ".vvd", ".dx90.vtx", ".txt"):
                (folder / ("v_tf_scattergun" + ext)).write_bytes(b"")
            (folder / "v_tf_bat.mdl").write_bytes(b"")
            self.assertEqual([p.name for p in mc.outputs(Path(d), "v_tf_scattergun")],
                             ["v_tf_scattergun.mdl", "v_tf_scattergun.vvd", "v_tf_scattergun.dx90.vtx"])


if __name__ == "__main__":
    unittest.main()
