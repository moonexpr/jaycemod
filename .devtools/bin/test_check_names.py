import unittest

from check_names import LuaSource, Findings, check


def findings(*files: tuple[str, str]) -> Findings:
    return check([LuaSource.parse(path, text) for path, text in files])


class Blanking(unittest.TestCase):
    def test_comments_are_not_code(self):
        src = LuaSource.parse("a.lua", "-- ply.tf2Team\n--[[ tf2.winner\n]] local x = 1\n")
        self.assertNotIn("tf2", src.code)
        self.assertEqual(src.code.count("\n"), 3)
        self.assertEqual(src.line_of(src.code.index("local")), 3)

    def test_a_long_string_is_a_string_not_code(self):
        src = LuaSource.parse("a.lua", 'local s = [==[ ply.tf2Team ]==]\n')
        self.assertNotIn("tf2", src.code)
        self.assertEqual(src.strings, [(1, " ply.tf2Team ")])

    def test_a_dash_inside_a_string_does_not_start_a_comment(self):
        src = LuaSource.parse("a.lua", 'local s = "a--b" x.tf2Team = 1\n')
        self.assertIn("x.tf2Team", src.code)


class OldNames(unittest.TestCase):
    def test_an_identifier_in_code_is_an_old_name(self):
        f = findings(("a.lua", "ply.tf2Team = 2\nfunction GM:TF2Modules() end\n"))
        self.assertEqual([n for _, _, n in f.old_names], ["ply.tf2Team", "GM:TF2Modules"])

    def test_a_name_shaped_string_is_an_old_name(self):
        f = findings(("a.lua", 'GetGlobal2Int("tf2.winner", 0)\n'))
        self.assertEqual([n for _, _, n in f.old_names], ["tf2.winner"])

    def test_prose_in_a_string_is_not(self):
        f = findings(("a.lua", 'T.test("keeps TF2\'s numbers", fn)\n'))
        self.assertEqual(f.old_names, [])


class Hooks(unittest.TestCase):
    def test_our_hook_added_but_never_run_is_broken(self):
        f = findings(("a.lua", 'hook.Add("WetsandRoundWin", "x", fn)\n'))
        self.assertEqual(f.hooks_never_run, ["WetsandRoundWin"])

    def test_a_run_in_another_file_is_the_other_end(self):
        f = findings(("a.lua", 'hook.Add("WetsandRoundWin", "x", fn)\n'), ("b.lua", 'hook.Run("WetsandRoundWin", 2)\n'))
        self.assertEqual(f.hooks_never_run, [])
        self.assertEqual(f.hooks_without_listener, [])

    def test_a_run_nobody_listens_to_is_published_not_broken(self):
        f = findings(("a.lua", 'hook.Call("WetsandRoundSpawn")\n'))
        self.assertEqual(f.hooks_never_run, [])
        self.assertEqual(f.hooks_without_listener, ["WetsandRoundSpawn"])

    def test_a_run_through_a_local_constant_is_a_run(self):
        f = findings(
            ("a.lua", 'hook.Add("WetsandNbDebugNpcs", "x", fn)\n'),
            ("b.lua", 'local NPCS_HOOK = "WetsandNbDebugNpcs"\nhook.Run(NPCS_HOOK, found)\n'),
        )
        self.assertEqual(f.hooks_never_run, [])

    def test_engine_hooks_are_not_ours(self):
        f = findings(("a.lua", 'hook.Add("PlayerSpawn", "x", fn)\n'))
        self.assertEqual(f.hooks_never_run, [])


class NetworkedVars(unittest.TestCase):
    def test_a_getter_with_no_setter_is_broken(self):
        f = findings(("a.lua", 'GetGlobal2Int("wetsand_round_winner", 0)\n'))
        self.assertEqual(f.vars_never_set, ["wetsand_round_winner"])

    def test_both_ends_across_realms_match(self):
        f = findings(
            ("sv.lua", 'SetGlobal2Int("wetsand_round_winner", 2)\nply:SetNW2Float("wetsand_stun_end_time", 1)\n'),
            ("cl.lua", 'GetGlobal2Int("wetsand_round_winner", 0)\nply:GetNW2Float("wetsand_stun_end_time", 0)\n'),
        )
        self.assertEqual(f.vars_never_set, [])
        self.assertEqual(f.vars_never_read, [])

    def test_a_setter_with_no_getter_is_reported(self):
        f = findings(("a.lua", 'SetGlobal2Int("wetsand_round_role" .. team, 1)\n'))
        self.assertEqual(f.vars_never_read, ["wetsand_round_role.."])

    def test_a_prefix_matches_a_prefix(self):
        f = findings(
            ("sv.lua", 'SetGlobal2String("wetsand_round_goal_" .. team, s)\n'),
            ("cl.lua", 'GetGlobal2String("wetsand_round_goal_" .. myTeam, "")\n'),
        )
        self.assertEqual(f.vars_never_set, [])
        self.assertEqual(f.vars_never_read, [])


if __name__ == "__main__":
    unittest.main()
