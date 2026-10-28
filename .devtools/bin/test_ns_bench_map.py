#!/usr/bin/env python3
"""Tests for ns_bench_map.py's cut: what of a decompiled map a bench keeps."""
import re
import unittest

import ns_bench_map as M

BENCH = M.Bench(source=M.Path("x.bsp"), mins=(-100, -100, -100), maxs=(100, 100, 100),
                spawns=(M.Spawn(M.RED, (-50, 0, 8), 0), M.Spawn(M.BLU, (50, 0, 8), 180)))


def solid(sid, lo, hi):
    """A brush as BSPSource writes one: its sides' plane points on its faces."""
    (x0, y0, z0), (x1, y1, z1) = lo, hi
    planes = [f"({x0} {y0} {z1}) ({x0} {y1} {z1}) ({x1} {y1} {z1})",
              f"({x0} {y1} {z0}) ({x0} {y0} {z0}) ({x1} {y0} {z0})"]
    sides = "".join(f'\t\tside\n\t\t{{\n\t\t\t"id" "{sid * 10 + i}"\n\t\t\t"plane" "{p}"\n\t\t}}\n'
                    for i, p in enumerate(planes))
    return f'\tsolid\n\t{{\n\t\t"id" "{sid}"\n{sides}\t}}\n'


def ent(eid, classname, origin=None, solids="", extra=""):
    lines = [f'\t"id" "{eid}"', f'\t"classname" "{classname}"']
    if origin:
        lines.append(f'\t"origin" "{origin}"')
    return "entity\n{\n" + "\n".join(lines) + extra + "\n" + solids + "}\n"


VMF = ("versioninfo\n{\n}\nworld\n{\n\t\"id\" \"1\"\n\t\"classname\" \"worldspawn\"\n"
       + solid(800, (-50, -50, -10), (50, 50, 0))  # inside
       + solid(801, (90, -10, 0), (300, 10, 20))  # across the box's side
       + solid(802, (500, 500, 0), (600, 600, 20))  # outside
       + "}\n"
       + ent(2, "prop_static", "10 10 10")
       + ent(3, "prop_static", "500 0 0")
       + ent(4, "info_player_teamspawn", "0 0 0", extra='\n\t"TeamNum" "2"')
       + ent(5, "func_detail", solids=solid(900, (0, 0, 0), (10, 10, 10)))
       + ent(7, "func_detail", solids=solid(901, (400, 0, 0), (410, 10, 10)))
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

    def test_keeps_world_brushes_inside_or_across_the_box(self):
        self.assertIn('"id" "800"', self.text)
        self.assertIn('"id" "801"', self.text)

    def test_drops_world_brushes_outside_the_box(self):
        self.assertNotIn('"id" "802"', self.text)

    def test_keeps_brush_entities_with_a_brush_in_the_box_only(self):
        self.assertEqual(classes(self.text).count("func_detail"), 1)
        self.assertIn('"id" "900"', self.text)
        self.assertNotIn('"id" "901"', self.text)

    def test_replaces_the_maps_spawns_with_the_benchs(self):
        self.assertNotIn('"origin" "0 0 0"', self.text)
        self.assertEqual(classes(self.text).count("info_player_teamspawn"), 2)
        self.assertEqual(classes(self.text).count("info_player_start"), 1)
        self.assertIn('"origin" "50 0 8"', self.text)
        self.assertEqual((self.dropped, self.added), (5, 3))

    def test_new_ids_follow_the_highest(self):
        ids = [int(i) for i in re.findall(r'^\t"id" "(\d+)"', self.text, re.M)]
        self.assertEqual(len(ids), len(set(ids)))
        self.assertEqual(max(ids), 9004, "after the highest left, side 9001 of the func_detail kept")

    def test_new_entities_go_before_the_cameras(self):
        self.assertLess(self.text.index("info_player_start"), self.text.index("cameras"))


class ShellTest(unittest.TestCase):
    def test_six_slabs_enclose_the_box(self):
        slabs = M.shell((-100, -100, -100), (100, 100, 100), 16)
        self.assertEqual(len(slabs), 6)
        lows = [tuple(s["mins"]) for s in slabs]
        highs = [tuple(s["maxs"]) for s in slabs]
        self.assertIn((-116, -116, -116), lows)
        self.assertIn((116, 116, 116), highs)
        for s in slabs:  # none reaches into the box
            inside = all(lo < 100 and hi > -100 for lo, hi in zip(s["mins"], s["maxs"]))
            self.assertFalse(inside, s)


class NamesTest(unittest.TestCase):
    def test_bench_names_are_dev_origin_purpose(self):
        for name, bench in M.BENCHES.items():
            words = name.split("_")
            self.assertEqual(words[0], "dev", name)
            self.assertIn(words[1], bench.source.stem, f"{name}: its second word names the map it comes from")
            self.assertGreater(len(words), 2, f"{name}: what it tests follows")


if __name__ == "__main__":
    unittest.main()
