import json
import tempfile
import unittest
from pathlib import Path

from PIL import Image

from assault_view import PANEL, Draw, Parse, Reach

CASE = {"name": "center", "lo": {"x": -375, "y": -375}, "hi": {"x": 375, "y": 375}, "entry": {"x": -425, "y": 0},
        "enemy": {"x": 0, "y": 0}, "ring": 192, "band": 48,
        "members": [{"start": {"x": -640, "y": 0}, "stage": {"x": -450, "y": -250}, "point": {"x": -150, "y": -100},
                     "place": {"x": 300, "y": 300}},
                    {"start": {"x": -700, "y": 50}}]}
TEXT = json.dumps({"map": "dev_3house", "doors": [{"x": -425, "y": 0}], "windows": [{"x": 0, "y": 400}], "cases": [CASE, CASE]})


class ParseTest(unittest.TestCase):
    def test_the_bench_answer_reads_as_placements(self):
        placements = Parse("running\n" + TEXT + "\n")
        self.assertEqual(placements.map, "dev_3house")
        self.assertEqual(len(placements.cases), 2)
        case = placements.cases[0]
        self.assertEqual((case.name, case.enemy, case.ring), ("center", (0, 0), 192))
        self.assertEqual(case.members[0].point, (-150, -100))

    def test_a_member_left_without_a_place_reads_as_none(self):
        member = Parse(TEXT).cases[0].members[1]
        self.assertEqual((member.stage, member.point, member.place), (None, None, None))

    def test_an_answer_with_no_placements_is_refused(self):
        with self.assertRaises(ValueError):
            Parse("lua error: no stage")


class DrawTest(unittest.TestCase):
    def test_every_case_is_a_panel_side_by_side(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "assault.png"
            Draw(Parse(TEXT), out)
            width, height = Image.open(out).size
            self.assertEqual(width, 2 * PANEL)
            self.assertGreaterEqual(height, PANEL)

    def test_each_panel_reaches_round_the_room_its_stack_and_its_starts(self):
        lo, hi = Reach(Parse(TEXT).cases[0])
        self.assertLessEqual(lo[0], -700)
        self.assertGreaterEqual(hi[0], 375)


if __name__ == "__main__":
    unittest.main()
