"""gev2_client_session.sh against fake tools: every tool it calls (gmod_client.py,
srcds.py, gev2_probe.py, gev2_marker.py) is a fake that logs its arguments,
ps is a fake that prints a file, and main is a scratch git repository, so no
test launches, signals or marks anything real. check_no_markers.py is the
real one, run on the scratch repository."""
import json
import os
import signal
import subprocess
import sys
import time
from pathlib import Path

import pytest

from gev2_marker import TAG

BIN = Path(__file__).resolve().parent
SCRIPT = BIN / "gev2_client_session.sh"
FAKE_NAMES = ("gmod_client.py", "srcds.py", "gev2_probe.py", "gev2_marker.py")
GMOD_LINE = "C:\\Steam\\steamapps\\common\\GarrysMod\\gmod_win64.exe -novid +connect 127.0.0.1:27025"

FAKE_TOOL = r'''
import json, subprocess, sys, time
from pathlib import Path
here = Path(__file__).resolve().parent
name = Path(__file__).name
args = sys.argv[1:]
key = " ".join([name] + args[:1])
with open(here / "calls.log", "a") as log:
    log.write(" ".join([name] + args) + "\n")
cfg = json.loads((here / "fake.json").read_text())
for command in cfg.get("effects", {}).get(key, []):
    subprocess.run(command, shell=True, check=True, cwd=here)
time.sleep(cfg.get("sleep", {}).get(key, 0))
sys.stdout.write(cfg.get("stdout", {}).get(key, ""))
codes = cfg.get("exits", {}).get(key, 0)
if isinstance(codes, list):  # one code per call, the last repeating
    seen = cfg.setdefault("seen", {})
    n = seen.get(key, 0)
    seen[key] = n + 1
    (here / "fake.json").write_text(json.dumps(cfg))
    codes = codes[min(n, len(codes) - 1)]
sys.exit(codes)
'''


def git(repo, *args):
    return subprocess.run(
        ["git", "-c", "user.name=t", "-c", "user.email=t@example.com", "-c", "commit.gpgsign=false", *args],
        cwd=repo, check=True, capture_output=True, text=True).stdout.strip()


class Session:
    """One run of the script, its fakes, and what they saw."""

    def __init__(self, tmp_path):
        self.tools = tmp_path / "tools"
        self.tools.mkdir(parents=True)
        for name in FAKE_NAMES:
            (self.tools / name).write_text(FAKE_TOOL)
        (self.tools / "check_no_markers.py").symlink_to(BIN / "check_no_markers.py")
        self.ps = self.tools / "ps"
        self.ps.write_text(f"#!/bin/sh\ncat '{self.tools / 'ps.txt'}'\n")
        self.ps.chmod(0o755)
        (self.tools / "ps.txt").write_text("/sbin/launchd\nC:\\Steam\\steam.exe\n")
        self.cfg = {
            # a launched client shows in ps until stop closes it
            "effects": {
                "gmod_client.py start": [f"printf '%s\\n' '{GMOD_LINE}' >> ps.txt"],
                "gmod_client.py stop": ["grep -v gmod_win64 ps.txt > ps.new || true; mv ps.new ps.txt"],
            },
        }
        self.main = tmp_path / "main"
        gamemode = self.main / "addon" / "gamemodes" / "sandcastle" / "gamemode"
        (gamemode / "wetsand").mkdir(parents=True)
        (gamemode / "features" / "capture").mkdir(parents=True)
        (gamemode / "wetsand" / "cl_spectate.lua").write_text("local lastMode\n")
        (gamemode / "features" / "capture" / "cl.lua").write_text("local View = {}\nreturn View\n")
        git(self.main, "init", "-q")
        git(self.main, "add", "-A")
        git(self.main, "commit", "-qm", "files")
        self.artifacts = tmp_path / "artifacts"
        self.artifacts.mkdir()
        self.proc = None

    def env(self):
        return {
            **os.environ,
            "GEV2_SESSION_TOOLS": str(self.tools),
            "GEV2_SESSION_PS": str(self.ps),
            "GEV2_SESSION_MAIN": str(self.main),
            "GEV2_SESSION_ARTIFACTS": str(self.artifacts),
            "GEV2_SESSION_SETTLE": "0",
            "GEV2_SESSION_GONE_WAIT": "0",
        }

    def start(self, *args):
        (self.tools / "fake.json").write_text(json.dumps(self.cfg))
        self.proc = subprocess.Popen(["bash", str(SCRIPT), *args], env=self.env(), stdout=subprocess.PIPE,
                                     stderr=subprocess.STDOUT, text=True)
        return self.proc

    def run(self, *args):
        self.start(*args)
        out, _ = self.proc.communicate(timeout=60)
        return self.proc.returncode, out

    def calls(self):
        log = self.tools / "calls.log"
        return log.read_text().splitlines() if log.exists() else []

    def actions(self):
        """Each call as its tool and first argument."""
        return [" ".join(c.split()[:2]) for c in self.calls()]


LAUNCHING = ("gmod_client.py start", "gmod_client.py stop", "srcds.py start", "srcds.py stop", "srcds.py rcon",
             "gev2_probe.py run", "gev2_marker.py set", "gev2_marker.py restore")
CLEANUP = ["gev2_marker.py restore", "gmod_client.py stop", "srcds.py stop"]


@pytest.fixture
def session(tmp_path):
    return Session(tmp_path)


# The start checks ------------------------------------------------------------------------


def test_refuses_to_start_while_a_marker_is_set(session):
    session.cfg["stdout"] = {"gev2_marker.py status": "/x/addon/features/capture/cl.lua\n"}
    code, out = session.run("t1")
    assert code == 2, out
    assert not any(a in LAUNCHING for a in session.actions()), session.calls()
    assert "markers are set" in out


def test_refuses_to_start_while_a_client_or_server_is_recorded(session):
    for name in ("gmod_client.pid", "gmod_client.launch", "srcds.pid"):
        (session.artifacts / name).write_text("{}")
        code, out = session.run("t2t4")
        assert code == 2, out
        assert name in out
        assert not any(a in LAUNCHING for a in session.actions()), session.calls()
        (session.artifacts / name).unlink()


def test_a_failed_client_check_exits_3_and_launches_nothing(session):
    for check_exit in (3, 1):
        session.cfg["exits"] = {"gmod_client.py check": check_exit}
        code, out = session.run("t1")
        assert code == 3, out
        assert not any(a in LAUNCHING for a in session.actions()), session.calls()


# The sessions ----------------------------------------------------------------------------


def test_t1_runs_its_steps_in_order_then_cleans_up_in_order(session):
    code, out = session.run("t1")
    assert code == 0, out
    assert session.actions() == [
        "gev2_marker.py status",
        "gmod_client.py check",
        "gev2_marker.py set",
        "gev2_marker.py set",
        "srcds.py start",
        "gev2_probe.py run",
        "gev2_marker.py restore",
        "gev2_marker.py set",
        "gev2_marker.py set",
        "gmod_client.py start",
        "gev2_probe.py run",
    ] + CLEANUP
    calls = session.calls()
    assert "--no-lua-refresh" in calls[4] and "koth_viaduct" in calls[4]
    spectate = str(session.main / "addon/gamemodes/sandcastle/gamemode/wetsand/cl_spectate.lua")
    capture = str(session.main / "addon/gamemodes/sandcastle/gamemode/features/capture/cl.lua")
    assert calls[2].startswith(f"gev2_marker.py set {spectate} WETSAND_T1_INCLUDE = \"sent-")
    assert calls[3].startswith(f"gev2_marker.py set {capture} WETSAND_T1_COMPILE = \"sent-")
    assert "\"disk-" in calls[7] and "\"disk-" in calls[8]
    assert calls[5] == "gev2_probe.py run client_t1"
    assert calls[10] == "gev2_probe.py run --client client_t1"


def test_t2t4_restarts_the_client_and_probes_after_each_save(session):
    code, out = session.run("t2t4")
    assert code == 0, out
    calls = session.calls()
    assert sum(c.startswith("gmod_client.py start") for c in calls) == 3  # the first launch and two restarts
    assert not any("--no-lua-refresh" in c for c in calls)
    labels = [c.split("--label ")[1].split()[0] for c in calls if "--label" in c]
    assert labels == ["base", "save-connected", "save-rejoined", "restored", "refresh-saved",
                      "refresh-connected", "refresh-rejoined"]
    assert "gev2_probe.py run client_t4" in calls and "gev2_probe.py run --client client_t4" in calls
    refresh = [c for c in calls if c.startswith("srcds.py rcon")]
    assert refresh == ["srcds.py rcon lua_refresh_file gamemodes/sandcastle/gamemode/features/capture/cl.lua"]
    # Every save (a set, and a restore while refresh is on) is followed by a wait.
    assert out.count("waiting 0 s") >= 4
    assert session.actions()[-3:] == CLEANUP


def test_a_refused_client_start_aborts_and_is_never_retried(session):
    session.cfg["exits"] = {"gmod_client.py start": 3}
    code, out = session.run("t2t4")
    assert code == 3, out
    assert session.actions().count("gmod_client.py start") == 1
    assert session.actions()[-3:] == CLEANUP


def test_a_failed_client_restart_aborts_the_session(session):
    session.cfg["exits"] = {"gmod_client.py start": [0, 1]}
    code, out = session.run("t2t4")
    assert code == 1, out
    actions = session.actions()
    assert actions.count("gmod_client.py start") == 2
    assert actions[actions.index("gmod_client.py start", actions.index("gmod_client.py start") + 1) + 1:] == CLEANUP


def test_a_gmod_still_running_after_stop_aborts(session):
    session.cfg["effects"]["gmod_client.py stop"] = []  # the client outlives stop
    code, out = session.run("t2t4")
    assert code == 4, out
    actions = session.actions()
    assert actions.count("gmod_client.py start") == 1  # no relaunch after the first stop
    assert "gmod_win64.exe still runs" in out
    assert actions[-3:] == CLEANUP


def test_a_signal_runs_cleanup_once(session):
    session.cfg["sleep"] = {"gev2_probe.py run": 2}
    proc = session.start("t1")
    deadline = time.monotonic() + 30
    while not any(c.startswith("gev2_probe.py run") for c in session.calls()):
        assert time.monotonic() < deadline
        time.sleep(0.05)
    proc.send_signal(signal.SIGTERM)
    out, _ = proc.communicate(timeout=60)
    assert proc.returncode == 128 + signal.SIGTERM, out
    actions = session.actions()
    assert actions[actions.index("gev2_probe.py run") + 1:] == CLEANUP


# The end checks --------------------------------------------------------------------------


def test_a_changed_main_status_fails_the_session(session):
    session.cfg["effects"]["srcds.py start"] = [f"touch '{session.main / 'addon' / 'stray.lua'}'"]
    code, out = session.run("t1")
    assert code == 4, out
    assert "status changed" in out and "stray.lua" in out


def test_new_commits_on_main_are_checked_for_marker_lines(session):
    capture = session.main / "addon/gamemodes/sandcastle/gamemode/features/capture/cl.lua"
    commit = (f"git -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false -C '{session.main}' "
              "commit -qam work")
    session.cfg["effects"]["srcds.py start"] = [
        f"printf '%s\\n' 'WETSAND_T2 = \"x\" {TAG}' > '{capture}.new' && cat '{capture}' >> '{capture}.new' "
        f"&& mv '{capture}.new' '{capture}' && {commit}"]
    code, out = session.run("t1")
    assert code == 4, out
    assert "marker line" in out
    # A clean commit on main during the session is fine.
    session2 = Session(session.tools.parent / "clean")
    notes = session2.main / "addon" / "notes.lua"
    session2.cfg["effects"]["srcds.py start"] = [
        f"echo 'x = 1' > '{notes}' && git -C '{session2.main}' add -A && "
        f"git -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false -C '{session2.main}' commit -qm notes"]
    code, out = session2.run("t1")
    assert code == 0, out
    assert "main moved" in out


# The dry run -----------------------------------------------------------------------------


def test_a_dry_run_launches_and_marks_nothing(session):
    for name in ("t1", "t2t4"):
        (session.tools / "calls.log").unlink(missing_ok=True)
        code, out = session.run("--dry-run", name)
        assert code == 0, out
        assert session.actions() == ["gev2_marker.py status", "gmod_client.py check"], session.calls()
        assert "would run" in out and "gmod_client.py start" in out


def test_usage(session):
    for args in ((), ("t3",), ("--dry-run",)):
        code, out = session.run(*args)
        assert code == 2 and "usage: gev2_client_session.sh" in out
        assert session.calls() == []
