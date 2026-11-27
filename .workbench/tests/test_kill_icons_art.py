import unittest

from kill_icons_art import (
    CELL_TALL,
    CROWBAR,
    STUNSTICK,
    FRAG,
    GRENADE,
    ICONS,
    SCALE,
    ArtError,
    Icon,
    Part,
    fingerprint,
    layout,
    lua_module,
    mod_textures,
    pose,
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


def near(points):
    return [(round(x, 6), round(y, 6)) for x, y in points]


class Pose(unittest.TestCase):
    def test_moves_a_design_from_one_point_to_another(self):
        (part,) = pose((Part(((1, 2),)),), about=(1, 2), at=(10, 20))
        self.assertEqual(near(part.knots), [(10, 20)])

    def test_scales_about_the_point(self):
        (part,) = pose((Part(((2, 0),)),), about=(0, 0), at=(0, 0), scale=0.5)
        self.assertEqual(near(part.knots), [(1, 0)])

    def test_positive_degrees_turn_counter_clockwise_on_screen(self):
        (part,) = pose((Part(((1, 0),)),), about=(0, 0), at=(0, 0), degrees=90)
        self.assertEqual(near(part.knots), [(0, -1)], "y is down: up the screen")

    def test_a_flip_turns_it_upside_down_before_it_turns(self):
        (part,) = pose((Part(((0, 1),)),), about=(0, 0), at=(0, 0), flip=True)
        self.assertEqual(near(part.knots), [(0, -1)])

    def test_keeps_each_parts_operation(self):
        (part,) = pose((Part(((0, 0),), "subtract"),), about=(0, 0), at=(0, 0))
        self.assertEqual(part.op, "subtract")


def span(parts):
    points = [p for part in parts for p in part.knots]
    return max(y for _, y in points) - min(y for _, y in points)


class Frag(unittest.TestCase):
    def test_is_three_grenades_each_smaller_than_the_last(self):
        n = len(GRENADE)
        self.assertEqual(len(FRAG.parts), 3 * n)
        tall = [span(FRAG.parts[i * n:(i + 1) * n]) for i in range(3)]
        self.assertGreater(tall[0], tall[1])
        self.assertGreater(tall[1], tall[2])

    def test_each_is_tilted_its_own_way_and_none_fires_a_flash(self):
        n = len(GRENADE)
        body = [FRAG.parts[i * n].knots for i in range(3)]
        slopes = {round((b[1][1] - b[0][1]) / (b[1][0] - b[0][0]), 3) for b in body}
        self.assertEqual(len(slopes), 3, "no two lean alike")
        self.assertEqual(FRAG.flash, ())


class Melee(unittest.TestCase):
    def test_each_rises_toward_the_victim(self):
        for icon in (CROWBAR, STUNSTICK):
            points = [p for part in icon.parts for p in part.knots]
            left = min(points)
            right = max(points)
            self.assertLess(right[1], left[1], f"{icon.name}: its right end is higher up the screen")


    def test_the_crowbars_hook_is_at_its_top_right_and_its_claw_at_its_bottom_left(self):
        points = [p for part in CROWBAR.parts for p in part.knots]
        left, _, right, _ = CROWBAR.bounds()

        def tall(near):
            ys = [y for x, y in points if near(x)]
            return max(ys) - min(ys)

        hook = tall(lambda x: x > right - 12)
        claw = tall(lambda x: x < left + 12)
        self.assertGreater(hook, claw, "the hook's curl is the bulkier end, on the right")

class Prop(unittest.TestCase):
    def test_a_prop_kill_has_its_own_icon(self):
        self.assertIn("prop_physics", [i.name for i in ICONS])


class Halloween(unittest.TestCase):
    def test_the_pumpkin_bomb_the_horsemann_and_monoculus_have_icons(self):
        names = [i.name for i in ICONS]
        for name in ("tf_pumpkin_bomb", "headless_hatman", "eyeball_boss"):
            self.assertIn(name, names)


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



class Shipping(unittest.TestCase):
    def test_a_sheets_name_changes_with_any_icon_so_clients_download_it_again(self):
        a = layout((square("a", 0, 20),), sheet_wide=512)
        b = layout((square("a", 0, 21),), sheet_wide=512)
        self.assertEqual(fingerprint(a), fingerprint(layout((square("a", 0, 20),), sheet_wide=512)))
        self.assertNotEqual(fingerprint(a), fingerprint(b))
        self.assertRegex(fingerprint(a), r"^[0-9a-f]{8}$")

    def test_the_layout_ships_as_a_lua_module_holding_its_text_verbatim(self):
        text = '"x"\n{\n\t"a"\t"]]"\n}\n'
        module = lua_module(text)
        self.assertIn("module(...)", module)
        self.assertIn("TEXT = [==[\n" + text + "]==]", module)

    def test_a_layout_holding_the_closing_bracket_is_refused(self):
        with self.assertRaises(ArtError):
            lua_module("]==]")


if __name__ == "__main__":
    unittest.main()
