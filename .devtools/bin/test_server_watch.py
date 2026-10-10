"""server_watch.py: the events sandcastle_watch.lua appends to an instance's
data/sandcastle_watch.txt, followed for Claude Code's Monitor."""
from pathlib import Path

from server_root import Instance
from server_watch import WatchLine, follow, log_path, verdict


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
