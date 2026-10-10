"""server_watch.py: the events sandcastle_watch.lua appends to an instance's
data/sandcastle_watch.txt, followed for Claude Code's Monitor."""
from pathlib import Path

from server_root import Instance
import pytest

from server_watch import UnknownListener, WatchLine, follow, listen, listener_source, log_path, verdict


def test_each_instance_has_its_own_log():
    assert log_path(Instance(1)) == Instance(1).root / "garrysmod" / "data" / "sandcastle_watch.txt"
    assert log_path(Instance(2)) == Instance(2).root / "garrysmod" / "data" / "sandcastle_watch.txt"


def test_a_line_is_time_name_kind_and_text():
    assert WatchLine.parse("6.00 stage3 met dist=-7 at c_1") == WatchLine(6.0, "stage3", "met", "dist=-7 at c_1")
    assert WatchLine.parse("1.00 speed changed ") == WatchLine(1.0, "speed", "changed", "")
    assert WatchLine.parse("not a watch line") is None


def test_until_a_name_ends_on_its_met_or_its_failure_and_nothing_else():
    assert verdict(WatchLine(1, "stage3", "met", ""), "stage3") == 0
    assert verdict(WatchLine(1, "stage3", "timeout", ""), "stage3") == 1
    assert verdict(WatchLine(1, "stage3", "error", ""), "stage3") == 1
    assert verdict(WatchLine(1, "other", "met", ""), "stage3") is None
    assert verdict(WatchLine(1, "stage3", "changed", ""), "stage3") is None


def test_following_prints_only_lines_written_after_it_starts(tmp_path: Path):
    log = tmp_path / "sandcastle_watch.txt"
    log.write_text("0.00 old event before\n")
    printed = []

    def wait():  # the server writes while the follower waits
        with log.open("a") as f:
            f.write("2.00 cart event passed c_1\n3.00 stage3 met done\n")

    code = follow(log, "stage3", printed.append, wait, polls=3)
    assert printed == ["2.00 cart event passed c_1", "3.00 stage3 met done"]
    assert code == 0


def test_a_log_not_yet_written_is_waited_for(tmp_path: Path):
    log = tmp_path / "sandcastle_watch.txt"
    printed = []
    code = follow(log, "stage3", printed.append, lambda: log.write_text("1.00 stage3 timeout dist=-1973\n"), polls=3)
    assert (printed, code) == (["1.00 stage3 timeout dist=-1973"], 1)


def test_following_from_a_position_prints_what_was_written_since(tmp_path: Path):
    log = tmp_path / "sandcastle_watch.txt"
    log.write_text("0.00 old event before\n")
    start = log.stat().st_size
    with log.open("a") as f:  # written while the listener was armed, before the follow began
        f.write("1.00 nav progress opening doors\n")
    printed = []
    code = follow(log, "nav", printed.append, lambda: None, polls=1, start=start)
    assert printed == ["1.00 nav progress opening doors"]
    assert code is None


def test_a_listener_is_a_lua_file_named_after_its_task(tmp_path: Path):
    (tmp_path / "nav_generate.lua").write_text("Watch.Task('nav_generate', {})")
    assert listener_source(tmp_path, "nav_generate") == "Watch.Task('nav_generate', {})"


def test_an_unknown_listener_names_the_ones_there_are(tmp_path: Path):
    (tmp_path / "nav_generate.lua").write_text("")
    (tmp_path / "bake.lua").write_text("")
    with pytest.raises(UnknownListener, match="bake, nav_generate"):
        listener_source(tmp_path, "nope")


def test_listening_arms_the_listener_then_runs_the_command_then_follows_from_before_both(tmp_path: Path):
    log = tmp_path / "sandcastle_watch.txt"
    log.write_text("0.00 old event before\n")
    done = []

    def arm(source):
        done.append(("arm", source))
        with log.open("a") as f:
            f.write("1.00 nav progress waiting\n")

    def run(command):
        done.append(("run", command))
        with log.open("a") as f:
            f.write("2.00 nav met 412 areas\n")

    printed = []
    code = listen("nav", "Watch.Task('nav', {})", "mp_nav_generate", log, arm, run, printed.append, lambda: None, polls=1)
    assert done == [("arm", "Watch.Task('nav', {})"), ("run", "mp_nav_generate")]
    assert printed == ["1.00 nav progress waiting", "2.00 nav met 412 areas"]
    assert code == 0


def test_listening_without_a_command_only_arms(tmp_path: Path):
    log = tmp_path / "sandcastle_watch.txt"
    ran = []
    listen("nav", "src", None, log, lambda s: None, ran.append, lambda t: None, lambda: None, polls=0)
    assert ran == []
