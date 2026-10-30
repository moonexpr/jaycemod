import subprocess
import tempfile
import unittest
from pathlib import Path

import places
from rooms_view import KEY, KEY_HEIGHT, Area, Classes, Draw, Dump, LuaValue, PanelHeight, Parse, Summary


class LuaValueTest(unittest.TestCase):
    def test_a_graph_reads_back_in_luajit_as_written(self):
        value = {"graph": {7: {"outdoor": False, "lo": {"x": -1.5, "y": 2}, "links": [{"to": 9, "door": True}]}},
                 "windows": [], "map": 'cs_"office"'}
        check = ("local v = dofile(arg[1])\n"
                 "assert(v.graph[7].outdoor == false and v.graph[7].lo.x == -1.5 and v.graph[7].links[1].to == 9)\n"
                 "assert(v.graph[7].links[1].door == true and #v.windows == 0 and v.map == 'cs_\"office\"')\n")
        with tempfile.TemporaryDirectory() as tmp:
            path, script = Path(tmp) / "value.lua", Path(tmp) / "check.lua"
            path.write_text("return " + LuaValue(value))
            script.write_text(check)
            done = subprocess.run(["luajit", str(script), str(path)], capture_output=True, text=True)
        self.assertEqual(done.returncode, 0, done.stderr)


class ParseTest(unittest.TestCase):
    LINES = "\n".join([
        "levels\t2",
        "room\t1\troom\tfalse\t1\t1\t10\t20\t0",
        "in\t100\troom\t1",
        "door\t1\t5\t6\t0\troom\t1\t1\t2",
        "room\t2\tstairwell\tfalse\t1\t2\t30\t40\t50",
        "in\t101\troom\t2",
        "window\t1\t7\t8",
        "passage\t1\tcorridor\t2\t2\t20\t30\t0",
        "in\t102\tpassage\t1",
        "door\t2\t9\t9\t0\tpassage\t1\t\t2",
    ])

    def test_each_area_is_in_its_space_and_a_stairwell_spans_its_levels(self):
        found = Parse(self.LINES)
        self.assertEqual(found.levels, 2)
        self.assertIs(found.region[100], found.rooms[1])
        self.assertIs(found.region[102], found.passages[1])
        self.assertEqual(list(found.rooms[2].levels), [1, 2])
        self.assertEqual(list(found.rooms[1].levels), [1])
        self.assertEqual(found.doors, [(1, 5.0, 6.0), (2, 9.0, 9.0)])
        self.assertEqual(found.windows, [(1, 7.0, 8.0)])

    def test_a_doors_way_says_whose_it_is_the_corridor_it_goes_through_and_where_it_leads(self):
        found = Parse(self.LINES)
        self.assertEqual(found.ways[("room", 1)], [places.Door((5.0, 6.0, 0.0), (2,), 1)])
        self.assertEqual(found.ways[("passage", 1)], [places.Door((9.0, 9.0, 0.0), (2,), None)])

    def test_the_summary_counts_rooms_and_starting_classes_and_names_the_areas_left_out(self):
        found = Parse(self.LINES)
        areas = {i: Area(i, (0, 0), (1, 1), 0) for i in (100, 101, 102, 103)}
        classes = {1: places.Placed(places.RESTRICTED, "RED"), 2: places.Placed(places.WILDS, None)}
        lines = Summary(areas, found, classes)
        self.assertIn("2 levels, 2 rooms", lines[0])
        self.assertIn("1 stairwell indoors, levels 1-2", lines[0])
        self.assertIn("1 restricted RED", lines[1])
        self.assertIn("1 of 4 areas in no room or corridor", lines[2])


class ClassesTest(unittest.TestCase):
    def test_spawn_and_objective_areas_count_by_the_rooms_they_are_in_and_corridors_are_left_out(self):
        found = Parse(ParseTest.LINES)
        dump = Dump("map", {}, {}, [], {"RED": [100, 102], "BLU": [101]}, [100])
        classes = Classes(dump, found)
        self.assertEqual(sorted(classes), [1, 2], "rooms alone")
        self.assertEqual(classes[1].cls, places.RESTRICTED)
        self.assertEqual(classes[1].team, "RED")
        self.assertEqual(classes[2].team, "BLU")


class KeyTest(unittest.TestCase):
    def test_the_picture_carries_a_key_below_the_levels_naming_every_mark(self):
        found = Parse(ParseTest.LINES)
        areas = {100: Area(100, (0, 0), (500, 500), 0), 101: Area(101, (600, 0), (900, 400), 0),
                 102: Area(102, (0, 600), (900, 700), 0)}
        classes = {1: places.Placed(places.HIGHWAY, None), 2: places.Placed(places.STRONGHOLD, "BLU")}
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "map.png"
            Draw("map", areas, found, classes, out)
            from PIL import Image
            with Image.open(out) as image:
                height = image.height
        self.assertEqual(height, PanelHeight(areas) + KEY_HEIGHT, "the key's band under the panels")
        names = [entry.name for entry in KEY]
        for name in ("restricted RED", "restricted BLU", "stronghold RED", "stronghold BLU", "outpost RED",
                     "outpost BLU", "highway", "commons", "unoccupied", "wilds", "stairwell", "corridor",
                     "area in no room", "room's block", "door", "window"):
            self.assertIn(name, names)


if __name__ == "__main__":
    unittest.main()
