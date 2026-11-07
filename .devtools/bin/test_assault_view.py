import json
import tempfile
import unittest
from pathlib import Path

from PIL import Image

from assault_view import PANEL, Draw, Parse, Reach

CASE = {"name": "center", "lo": {"x": -375, "y": -375}, "hi": {"x": 375, "y": 375}, "entry": {"x": -425, "y": 0},
        "enemy": {"x": 0, "y": 0}, "ring": 192, "band": 48,
        "entrances": [{"pos": {"x": -425, "y": 0}, "flow": 2, "front": True},
                      {"pos": {"x": 0, "y": 425}, "flow": 0, "front": False}],
        "members": [{"start": {"x": -640, "y": 0}, "stage": {"x": -50, "y": 450}, "point": {"x": -150, "y": -100},
                     "place": {"x": 300, "y": 300}, "entrance": {"x": 0, "y": 425}},
                    {"start": {"x": -700, "y": 50}},
                    {"start": {"x": -600, "y": 0}, "stage": {"x": -450, "y": -250}, "show": {"x": -489, "y": 0},
                     "hide": {"x": -450, "y": -250}, "place": {"x": 0, "y": 0},
                     "legs": [[{"x": -600, "y": 0}, {"x": -520, "y": -300}, {"x": -450, "y": -250}],
                              [{"x": -450, "y": -250}, {"x": 0, "y": 0}]]}]}
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

    def test_the_entrances_and_the_decoy_read(self):
        case = Parse(TEXT).cases[0]
        self.assertEqual([(e.pos, e.flow, e.front) for e in case.entrances], [((-425, 0), 2, True), ((0, 425), 0, False)])
        self.assertEqual(case.members[0].entrance, (0, 425))
        decoy = case.members[2]
        self.assertEqual((decoy.show, decoy.hide), ((-489, 0), (-450, -250)))

    def test_a_member_s_legs_read_as_routes(self):
        legs = Parse(TEXT).cases[0].members[2].legs
        self.assertEqual(legs, (((-600, 0), (-520, -300), (-450, -250)), ((-450, -250), (0, 0))))

    def test_each_panel_reaches_round_the_routes_too(self):
        lo, _ = Reach(Parse(TEXT).cases[0])
        self.assertLessEqual(lo[1], -375 - 0)

    def test_the_bench_saying_why_it_has_none_is_told(self):
        with self.assertRaisesRegex(ValueError, "still being found"):
            Parse('{"error": "the war\'s classes are still being found"}')

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
