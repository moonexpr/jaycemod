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


class Plan(unittest.TestCase):
    def test_every_step_has_a_check_script(self):
        for run in PLAN:
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
        result = self.harness.run_step("gm_construct", 1, Step("cfg_defaults", 5, before="exec sandcastle_defaults"))
        self.assertEqual(self.server.sent[0], "exec sandcastle_defaults")
        self.assertTrue(self.server.sent[1].startswith("lua_run WETSAND_TESTS.Run(\"cfg_defaults\""))
        self.assertEqual(result.status, "pass")
        self.assertEqual(result.info["rcon"], {"exec sandcastle_defaults": "Unknown command \"cl_x\""})

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
