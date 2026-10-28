#!/usr/bin/env python3
"""Tests for ns_bench_map.py's cut: what of a decompiled map a bench keeps."""
import re
import unittest

import ns_bench_map as M

BENCH = M.Bench(source=M.Path("x.bsp"), mins=(-100, -100, -100), maxs=(100, 100, 100),
                spawns=(M.Spawn(M.RED, (-50, 0, 8), 0), M.Spawn(M.BLU, (50, 0, 8), 180)))


def ent(eid, classname, origin=None, solid=False, extra=""):
    lines = [f'\t"id" "{eid}"', f'\t"classname" "{classname}"']
    if origin:
        lines.append(f'\t"origin" "{origin}"')
    body = "\n".join(lines) + extra
    if solid:
        body += '\n\tsolid\n\t{\n\t\t"id" "900"\n\t\tside\n\t\t{\n\t\t\t"origin" "999 999 999"\n\t\t}\n\t}'
    return "entity\n{\n" + body + "\n}\n"


VMF = ("versioninfo\n{\n}\nworld\n{\n\t\"id\" \"1\"\n\t\"classname\" \"worldspawn\"\n}\n"
       + ent(2, "prop_static", "10 10 10")
       + ent(3, "prop_static", "500 0 0")
       + ent(4, "info_player_teamspawn", "0 0 0", extra='\n\t"TeamNum" "2"')
       + ent(5, "func_detail", solid=True)
       + ent(6, "light", "0 0 101")
       + "cameras\n{\n}\n")


def classes(text):
    return re.findall(r'^\t"classname" "([^"]+)"', text, re.M)


class CutTest(unittest.TestCase):
    def setUp(self):
        self.text, self.dropped, self.added = M.cut(VMF, BENCH)

    def test_keeps_point_entities_inside_the_box(self):
        self.assertIn('"origin" "10 10 10"', self.text)

    def test_drops_point_entities_outside_the_box(self):
        self.assertNotIn('"origin" "500 0 0"', self.text)
        self.assertNotIn('"origin" "0 0 101"', self.text)

    def test_keeps_brush_entities_for_the_cordon_to_cut(self):
        self.assertIn("func_detail", classes(self.text))

    def test_replaces_the_maps_spawns_with_the_benchs(self):
        self.assertNotIn('"origin" "0 0 0"', self.text)
        self.assertEqual(classes(self.text).count("info_player_teamspawn"), 2)
        self.assertEqual(classes(self.text).count("info_player_start"), 1)
        self.assertIn('"origin" "50 0 8"', self.text)
        self.assertEqual((self.dropped, self.added), (3, 3))

    def test_new_ids_follow_the_highest(self):
        ids = [int(i) for i in re.findall(r'^\t"id" "(\d+)"', self.text, re.M)]
        self.assertEqual(len(ids), len(set(ids)))
        self.assertEqual(max(ids), 903)

    def test_new_entities_go_before_the_cameras(self):
        self.assertLess(self.text.index("info_player_start"), self.text.index("cameras"))


class NamesTest(unittest.TestCase):
    def test_bench_names_are_dev_origin_purpose(self):
        for name, bench in M.BENCHES.items():
            words = name.split("_")
            self.assertEqual(words[0], "dev", name)
            self.assertIn(words[1], bench.source.stem, f"{name}: its second word names the map it comes from")
            self.assertGreater(len(words), 2, f"{name}: what it tests follows")


if __name__ == "__main__":
    unittest.main()
