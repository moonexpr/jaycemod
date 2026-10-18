import unittest

from kill_icons_art import (
    CELL_TALL,
    ICONS,
    SCALE,
    ArtError,
    Icon,
    Part,
    layout,
    mod_textures,
    rect,
    thick,
)


def square(name: str, x: float, w: float) -> Icon:
    return Icon(name, (Part(rect(x, 4, w, 8)),))


class Thick(unittest.TestCase):
    def test_a_straight_line_becomes_a_box_its_width_across(self):
        knots = thick([(0, 10), (20, 10)], 4)
        self.assertEqual(sorted(knots), sorted([(0, 8), (20, 8), (20, 12), (0, 12)]))

    def test_a_bend_keeps_its_width_at_the_corner(self):
        knots = thick([(0, 0), (10, 0), (10, 10)], 2)
        self.assertIn((11, -1), [(round(x, 6), round(y, 6)) for x, y in knots])


class Layout(unittest.TestCase):
    def test_each_icon_is_its_own_width_plus_margins_and_a_cell_tall(self):
        cells = layout((square("a", 10, 20), square("b", 0, 40)), sheet_wide=512)
        self.assertEqual([c.h for c in cells], [CELL_TALL, CELL_TALL])
        self.assertEqual(cells[0].w, cells[0].margin * 2 + 20 * SCALE)
        self.assertEqual(cells[1].w, cells[1].margin * 2 + 40 * SCALE)

    def test_cells_fill_a_row_then_wrap(self):
        icons = tuple(square(str(i), 0, 60) for i in range(3))
        cells = layout(icons, sheet_wide=300)
        self.assertEqual([(c.x, c.y) for c in cells], [(0, 0), (cells[0].w, 0), (0, CELL_TALL)])

    def test_an_icon_wider_than_the_sheet_is_refused(self):
        with self.assertRaises(ArtError):
            layout((square("wide", 0, 400),), sheet_wide=512)

    def test_an_icon_outside_its_cell_height_is_refused(self):
        with self.assertRaises(ArtError):
            layout((Icon("tall", (Part(rect(0, 0, 10, 40)),)),), sheet_wide=512)

    def test_the_shipped_icons_fit_one_sheet(self):
        cells = layout(ICONS, sheet_wide=512)
        self.assertLessEqual(max(c.y + c.h for c in cells), 512)


class ModTextures(unittest.TestCase):
    def test_writes_tf2s_format_with_both_sheets(self):
        cells = layout((square("weapon_pistol", 0, 20),), sheet_wide=512)
        text = mod_textures(cells, "sandcastle/kill_icons/hl2.png", "sandcastle/kill_icons/hl2_neg.png")
        self.assertIn('"weapon_pistol"', text)
        self.assertIn('"dfile"\t"sandcastle/kill_icons/hl2.png"', text)
        self.assertIn('"dnegfile"\t"sandcastle/kill_icons/hl2_neg.png"', text)
        self.assertIn(f'"width"\t"{cells[0].w}"', text)


if __name__ == "__main__":
    unittest.main()
