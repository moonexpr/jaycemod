import subprocess
import tempfile
import unittest
from pathlib import Path

from rooms_view import Area, LuaValue, Parse, Summary


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
        "room\t1\troom\tfalse\t1\t1\t10\t20",
        "in\t100\troom\t1",
        "door\t1\t5\t6",
        "room\t2\tstairwell\tfalse\t1\t2\t30\t40",
        "in\t101\troom\t2",
        "window\t1\t7\t8",
        "passage\t1\tcorridor\t2\t2",
        "in\t102\tpassage\t1",
        "door\t2\t9\t9",
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

    def test_the_summary_counts_by_kind_and_level_and_names_the_areas_left_out(self):
        found = Parse(self.LINES)
        areas = {i: Area(i, (0, 0), (1, 1), 0) for i in (100, 101, 102, 103)}
        lines = Summary(areas, found)
        self.assertIn("2 levels, 2 rooms", lines[0])
        self.assertIn("1 stairwell indoors, levels 1-2", lines[0])
        self.assertIn("1 of 4 areas in no room or corridor", lines[1])


if __name__ == "__main__":
    unittest.main()
