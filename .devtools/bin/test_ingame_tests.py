import json
import shutil
import tempfile
import unittest
from pathlib import Path

from ingame_tests import (
    CHECKS_DIR,
    PLAN,
    CheckLine,
    Harness,
    Step,
    LuaError,
    MapResult,
    StepResult,
    console_notes,
    deploy,
    halloween_run,
    lua_errors,
    render_report,
    result_from_json,
    tree_digest,
)

LOG = """Dynamic prop roof_chimneys: no sequence named:spinslow

[ERROR] gamemodes/sandcastle/gamemode/features/capture/sv.lua:12: attempt to index a nil value
  1. Think - gamemodes/sandcastle/gamemode/features/capture/sv.lua:12
   2. unknown - lua/includes/modules/hook.lua:96

Unknown command "cl_hud_round_timer_y"
[ERROR] lua_run:1: attempt to index local 't' (a nil value)
  1. unknown - lua_run:1

Timer Failed! [Simple][@lua_run (line 1)]
Breaking out of potential MapIO infinite loop! Current event: unk_class(no_name) => (AddOutput) -> ()
"""


class LuaErrors(unittest.TestCase):
    def test_each_error_with_its_stack(self):
        errors = lua_errors(LOG)
        self.assertEqual(len(errors), 2)
        self.assertEqual(errors[0].message,
                         "gamemodes/sandcastle/gamemode/features/capture/sv.lua:12: attempt to index a nil value")
        self.assertEqual(errors[0].stack, (
            "1. Think - gamemodes/sandcastle/gamemode/features/capture/sv.lua:12",
            "2. unknown - lua/includes/modules/hook.lua:96",
        ))

    def test_the_same_error_twice_is_counted(self):
        errors = lua_errors(LOG + LOG)
        self.assertEqual([e.count for e in errors], [2, 2])

    def test_carriage_returns_from_the_windows_log_are_dropped(self):
        errors = lua_errors(LOG.replace("\n", "\r\n"))
        self.assertFalse(errors[0].message.endswith("\r"))

    def test_none(self):
        self.assertEqual(lua_errors("all fine\n"), [])


class Notes(unittest.TestCase):
    def test_engine_complaints_and_unknown_commands(self):
        notes = console_notes(LOG)
        self.assertIn('Unknown command "cl_hud_round_timer_y"', notes)
        self.assertIn("Breaking out of potential MapIO infinite loop! Current event: unk_class(no_name) => (AddOutput) -> ()",
                      notes)
        self.assertNotIn("Dynamic prop roof_chimneys: no sequence named:spinslow", notes)

    def test_lua_errors_are_not_notes(self):
        self.assertFalse(any(n.startswith("[ERROR]") for n in console_notes(LOG)))

    def test_repeats_are_listed_once(self):
        self.assertEqual(console_notes(LOG + LOG).count('Unknown command "cl_hud_round_timer_y"'), 1)


class Results(unittest.TestCase):
    def test_reads_the_runners_record(self):
        result = result_from_json("koth", {
            "status": "fail",
            "checks": [{"name": "a", "ok": True, "detail": "x"}, {"name": "b", "ok": False, "detail": ""}],
            "info": {"point": "hill"},
            "seconds": 3.5,
        })
        self.assertEqual(result.status, "fail")
        self.assertEqual(result.checks, (CheckLine("a", True, "x"), CheckLine("b", False, "")))
        self.assertEqual(result.info, {"point": "hill"})

    def test_util_table_to_json_writes_an_empty_list_as_an_object(self):
        result = result_from_json("load", {"status": "skip", "checks": {}, "info": {}, "seconds": 0})
        self.assertEqual(result.checks, ())


def ent(classname, **keys):
    return {"classname": classname, **keys}


FIFTHCURVE = [
    ent("tf_logic_holiday", holiday_type="2"),
    ent("merasmus", targetname="merasmus_spawn"),
    ent("headless_hatman", targetname="hhhh_spawn"),
    ent("point_template", targetname="horseman_spawn", Template01="hhhh_spawn"),
    ent("point_template", targetname="merasmus_triggered", Template01="merasmus_spawn", Template02="fx"),
    ent("tf_zombie_spawner"),
    ent("tf_zombie_spawner"),
    ent("tf_spell_pickup"),
    ent("func_nav_prefer"),
    ent("tf_halloween_minigame"),
    ent("tf_halloween_gift_spawn_location"),
    ent("team_train_watcher"),
]


class HalloweenPlan(unittest.TestCase):
    def setUp(self):
        self.run = halloween_run("pl_fifthcurve_event", FIFTHCURVE)
        self.steps = {s.check: s for s in self.run.steps}

    def test_bosses_come_from_their_templates(self):
        self.assertEqual(self.steps["bosses"].args["bosses"], [
            {"template": "horseman_spawn", "class": "headless_hatman"},
            {"template": "merasmus_triggered", "class": "merasmus"},
        ])

    def test_counts_the_halloween_classes_placed_but_not_templated_bosses(self):
        self.assertEqual(self.steps["halloween_entities"].args["classes"], {
            "tf_logic_holiday": 1,
            "tf_zombie_spawner": 2,
            "tf_spell_pickup": 1,
            "func_nav_prefer": 1,
            "tf_halloween_minigame": 1,
            "tf_halloween_gift_spawn_location": 1,
        })

    def test_stubs_and_engine_classes_only_where_placed(self):
        args = self.steps["halloween_entities"].args
        self.assertEqual(args["stubs"], ["tf_halloween_minigame"])
        self.assertEqual(args["engine"], ["func_nav_prefer"])

    def test_steps_follow_what_the_map_places(self):
        self.assertEqual([s.check for s in self.run.steps], [
            "load", "halloween_entities", "gameplay_start", "payload", "skeletons", "spells", "gifts", "bosses"])
        self.assertIs(self.steps["payload"].args["checkpoint"], False)

    def test_expects_the_holiday_the_maps_logic_names(self):
        self.assertEqual(self.steps["halloween_entities"].args["holiday"], 2)
        coal = halloween_run("pl_coal_event", [ent("tf_logic_holiday", holiday_type="3")])
        self.assertEqual({s.check: s for s in coal.steps}["halloween_entities"].args["holiday"], 3)

    def test_a_map_with_only_its_holiday_logic(self):
        run = halloween_run("pl_coal_event", [ent("tf_logic_holiday"), ent("team_train_watcher")])
        self.assertEqual([s.check for s in run.steps], ["load", "halloween_entities", "gameplay_start", "payload"])


class Plan(unittest.TestCase):
    def test_every_step_has_a_check_script(self):
        for run in list(PLAN) + [halloween_run("pl_fifthcurve_event", FIFTHCURVE)]:
            for step in run.steps:
                self.assertTrue((CHECKS_DIR / f"{step.check}.lua").exists(), step.check)

    def test_every_map_starts_with_the_load_check(self):
        for run in PLAN:
            self.assertEqual(run.steps[0].check, "load", run.map)


class Deploy(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def test_copies_the_runner_and_checks_as_text_files(self):
        deploy(self.tmp / "wetsand_tests")
        harness = self.tmp / "wetsand_tests" / "harness"
        self.assertTrue((harness / "runner.txt").exists())
        self.assertTrue((harness / "checks" / "load.txt").exists())

    def test_clears_results_of_an_earlier_run(self):
        old = self.tmp / "wetsand_tests" / "results" / "old.json"
        old.parent.mkdir(parents=True)
        old.write_text("{}")
        deploy(self.tmp / "wetsand_tests")
        self.assertFalse(old.exists())


class FakeServer:
    """Answers RCON as the runner would: a Run command writes its record."""

    def __init__(self, results: Path):
        self.results = results
        self.sent = []
        self.install = None

    def rcon(self, text):
        self.sent.append(text)
        if text.startswith("lua_run WETSAND_TESTS.Run("):
            run_id = text.split('"')[3]
            (self.results / f"{run_id}.json").write_text(
                '{"status": "pass", "checks": [{"name": "x", "ok": true, "detail": ""}], "info": {}, "seconds": 1}')
            return ""
        return "Unknown command \"cl_x\"\n"


class RunStep(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        deploy(self.tmp)
        self.server = FakeServer(self.tmp / "results")
        self.harness = Harness.__new__(Harness)
        self.harness.server = self.server
        self.harness.data_root = self.tmp

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def test_sends_its_console_command_first_and_keeps_the_reply(self):
        result = self.harness.run_step("pl_badwater", 1, Step("defaults_apply", 5, before="wetsand_defaults_apply"))
        self.assertEqual(self.server.sent[0], "wetsand_defaults_apply")
        self.assertTrue(self.server.sent[1].startswith("lua_run WETSAND_TESTS.Run(\"defaults_apply\""))
        self.assertEqual(result.status, "pass")
        self.assertEqual(result.info["rcon"], {"wetsand_defaults_apply": "Unknown command \"cl_x\""})

    def test_the_check_reads_the_commands_reply_from_its_arguments(self):
        self.harness.run_step("pl_badwater", 1, Step("defaults_apply", 5, {"x": 1}, before="wetsand_defaults_apply"))
        args = json.loads((self.tmp / "harness" / "args" / "pl_badwater_1_defaults_apply.txt").read_text())
        self.assertEqual(args, {"x": 1, "before_reply": "Unknown command \"cl_x\""})

    def test_writes_the_arguments_for_the_runner(self):
        self.harness.run_step("koth_viaduct", 0, Step("load", 5, {"rounds": True}))
        args = self.tmp / "harness" / "args" / "koth_viaduct_0_load.txt"
        self.assertEqual(args.read_text(), '{"rounds": true}')


class Digest(unittest.TestCase):
    def test_equal_trees_digest_equal_and_a_change_shows(self):
        tmp = Path(tempfile.mkdtemp())
        try:
            for name in ("a", "b"):
                (tmp / name / "sub").mkdir(parents=True)
                (tmp / name / "sub" / "f.lua").write_text("x")
            self.assertEqual(tree_digest(tmp / "a"), tree_digest(tmp / "b"))
            (tmp / "b" / "sub" / "f.lua").write_text("y")
            self.assertNotEqual(tree_digest(tmp / "a"), tree_digest(tmp / "b"))
        finally:
            shutil.rmtree(tmp)


class Report(unittest.TestCase):
    def test_lists_each_check_and_each_error(self):
        result = MapResult(
            map="koth_viaduct",
            steps=(StepResult("koth", "fail", (CheckLine("BLU wins", False, "winner 2"),), {}, None, 10.0),),
            errors=(LuaError("x.lua:1: boom", ("1. f - x.lua:1",), 1),),
            notes=(),
        )
        text = render_report([result], header="Header", human_only=["sound"])
        self.assertIn("koth_viaduct", text)
        self.assertIn("FAIL", text)
        self.assertIn("BLU wins", text)
        self.assertIn("x.lua:1: boom", text)
        self.assertIn("1. f - x.lua:1", text)
        self.assertIn("sound", text)


if __name__ == "__main__":
    unittest.main()
