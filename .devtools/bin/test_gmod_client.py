"""gmod_client.py's safeguards, against a fake system: the process table, the
lsof output, the launcher, the clock and the signal call are all injected,
so no test starts or signals a real process."""
import inspect
import signal
import subprocess
from dataclasses import fields
from pathlib import Path

import pytest

import gmod_client
from gmod_client import (
    BOTTLE,
    CLIENT_EXE,
    GmodClient,
    Layout,
    NoClient,
    Process,
    ProcessTable,
    Recorded,
    Refused,
    System,
    build_parser,
    command_line,
    new_clients,
    players,
    run_watchdog,
)

BOTTLES = Path("/Users/op/Library/Application Support/CrossOver/Bottles")
TF2_BOTTLE = BOTTLES / "Team Fortress 2"
STEAM_BOTTLE = BOTTLES / "Steam"
APP = "/Apps/CrossOver.app"
WINE = APP + "/Contents/SharedSupport/CrossOver/bin/wine"
WRAPPER = APP + "/Contents/SharedSupport/CrossOver/lib/wine/x86_64-windows/winewrapper.exe"
GMOD = "C:\\Steam\\steamapps\\common\\GarrysMod"
T0 = "Thu Oct  8 09:00:00 2026"
T1 = "Thu Oct  8 10:00:03 2026"
T1_LATER = "Thu Oct  8 10:00:09 2026"
T2 = "Thu Oct  8 11:30:00 2026"
HELPER = GMOD + "\\gmod_win64.exe --type={kind} --no-sandbox --lang=en-US --log-file=" + GMOD + "\\debug.log"
LAUNCHER, CLIENT, WATCHDOG = 950, 951, 940
STEAM, WEBHELPER = 810, 811

OPERATOR = [
    Process(1, 0, T0, "/sbin/launchd"),
    Process(441, 1, T0, WRAPPER + " --enable-alt-loader macdrv --wait-children --start -- C:/users/crossover/Steam.lnk"),
    Process(800, 1, T0, APP + "/Contents/SharedSupport/CrossOver/bin/wineserver"),
    Process(801, 1, T0, "C:\\windows\\system32\\winedevice.exe"),
    Process(802, 1, T0, "C:\\windows\\system32\\services.exe"),
    Process(803, 1, T0, "C:\\windows\\system32\\explorer.exe /desktop"),
    Process(STEAM, 1, T0, "C:\\Steam\\steam.exe "),
    Process(WEBHELPER, 1, T0, "C:\\Steam\\bin\\cef\\cef.win64\\steamwebhelper.exe --type=renderer"),
]


def lsof_section(pid, cwd):
    return f"p{pid}\nfcwd\nn{cwd}\nftxt\nn{APP}/Contents/SharedSupport/CrossOver/lib/wine/x86_64-unix/ntdll.so\n"


class FakeSystem(System):
    """A process table that changes on a fake clock. launch() adds the wine
    launcher at once and the Windows client a few seconds later, its command
    line the Windows program and arguments the launch gave; a signal is
    recorded and, if the process obeys it, ends it. ps can be made to fail
    for the next few looks."""

    def __init__(self, processes=OPERATOR, cwd=None):
        self.t = 10_000.0
        self.table = {p.pid: p for p in processes}
        self.cwd = {STEAM: str(TF2_BOTTLE / "drive_c/Steam"), WEBHELPER: str(TF2_BOTTLE / "drive_c/Steam")}
        self.cwd.update(cwd or {})
        self.events = []
        self.launches = []
        self.signals = []
        self.signal_times = []
        self.obeys = {signal.SIGTERM, signal.SIGKILL}
        self.clients_per_launch = 1
        self.client_delay = 3
        self.ps_failures = 0

    def at(self, delay, action):
        self.events.append((self.t + delay, action))

    def add(self, process):
        self.table[process.pid] = process

    def remove(self, pid):
        self.table.pop(pid, None)

    def processes(self):
        if self.ps_failures:
            self.ps_failures -= 1
            raise subprocess.CalledProcessError(1, ["ps", "-axo", "pid=,ppid=,lstart=,command="])
        due = [e for e in self.events if e[0] <= self.t]
        self.events = [e for e in self.events if e[0] > self.t]
        for _, action in sorted(due, key=lambda e: e[0]):
            action()
        return "".join(f"{p.pid:5d} {p.ppid:5d} {p.started}     {p.command}\n" for p in self.table.values())

    def lsof(self, pids):
        return "".join(lsof_section(pid, self.cwd[pid]) for pid in pids if pid in self.table and pid in self.cwd)

    def launch(self, argv):
        self.launches.append(list(argv))
        windows = " ".join(argv[argv.index("--cx-app") + 1:])
        self.add(Process(LAUNCHER, WATCHDOG, T1, WRAPPER + " --run -- " + windows))
        for i in range(self.clients_per_launch):
            client = Process(CLIENT + i, 1, T1, windows)
            self.at(self.client_delay, lambda c=client: self.add(c))
        return LAUNCHER

    def signal(self, pid, sig):
        self.signals.append((pid, sig))
        self.signal_times.append(self.t)
        if sig in self.obeys:
            self.remove(pid)

    def now(self):
        return self.t

    def sleep(self, seconds):
        self.t += seconds


def layout(tmp_path):
    gmod = tmp_path / "garrysmod"
    (gmod / "cfg").mkdir(parents=True, exist_ok=True)
    (gmod / "cfg" / "config.cfg").write_text("bind w +forward\n")
    (gmod / "cfg" / "autoexec.cfg").write_text("echo hi\n")
    return Layout(
        pid_file=tmp_path / "artifacts" / "gmod_client.pid",
        client_dir=tmp_path / "artifacts" / "client",
        gmod_dir=gmod,
        bottles=BOTTLES,
    )


def client_with(tmp_path, system):
    return GmodClient(system, layout(tmp_path))


def log_of(client):
    return client.layout.log_file.read_text() if client.layout.log_file.exists() else ""


def assert_refused_and_launched_nothing(client, system, mentioning):
    found = client.check()
    assert not found.allowed
    assert any(mentioning in r for r in found.refusals), found.refusals
    with pytest.raises(Refused):
        client.launch(27025, 20)
    assert system.launches == []
    assert system.signals == []


# The preflight ---------------------------------------------------------------------------


def test_refuses_while_tf2_runs(tmp_path):
    for exe in ("tf_win64.exe", "tf.exe", "hl2.exe"):
        for i, command in enumerate((
            f"C:\\Steam\\steamapps\\common\\Team Fortress 2\\{exe} -steam -game tf",  # in the operator's bottle
            f"D:\\Games\\Valve\\{exe}",  # in any other bottle
            f"{WRAPPER} --run -- C:\\Steam\\steamapps\\common\\Team Fortress 2\\{exe}",  # its launcher alone
        )):
            system = FakeSystem(OPERATOR + [Process(700, 1, T0, command)])
            assert_refused_and_launched_nothing(client_with(tmp_path / f"{exe}{i}", system), system, exe)


def test_refuses_while_a_gmod_client_runs(tmp_path):
    for exe in ("gmod.exe", "gmod_win64.exe"):
        system = FakeSystem(OPERATOR + [Process(700, 1, T0, f"{GMOD}\\{exe} -steam")])
        assert_refused_and_launched_nothing(client_with(tmp_path / exe, system), system, exe)


def test_refuses_without_steam_running_in_the_tf2_bottle(tmp_path):
    no_steam = FakeSystem([p for p in OPERATOR if p.pid != STEAM])
    assert_refused_and_launched_nothing(client_with(tmp_path / "none", no_steam), no_steam, "steam.exe")
    # Steam in the other bottle, and only Steam's web helper in this one.
    elsewhere = FakeSystem(cwd={STEAM: str(STEAM_BOTTLE / "drive_c/Steam")})
    assert_refused_and_launched_nothing(client_with(tmp_path / "elsewhere", elsewhere), elsewhere, "steam.exe")
    # A bottle whose name only starts like this one's is another bottle.
    lookalike = FakeSystem(cwd={STEAM: str(BOTTLES / "Team Fortress 2 (old)/drive_c/Steam")})
    assert_refused_and_launched_nothing(client_with(tmp_path / "lookalike", lookalike), lookalike, "steam.exe")
    assert client_with(tmp_path / "allowed", FakeSystem()).check().allowed


def test_refuses_while_its_own_client_still_runs(tmp_path):
    system = FakeSystem()
    client = client_with(tmp_path, system)
    recorded = client.launch(27025, 20)
    found = client.check()
    assert any("gmod_client.pid" in r and str(recorded.pid) in r for r in found.refusals), found.refusals
    with pytest.raises(Refused):
        client.launch(27025, 20)
    assert len(system.launches) == 1
    # Once that client is gone, its old record refuses nothing.
    system.remove(recorded.pid)
    system.remove(LAUNCHER)
    assert client.check().allowed


def test_has_no_way_to_choose_another_bottle(tmp_path):
    assert BOTTLE == "Team Fortress 2"
    assert list(inspect.signature(command_line).parameters) == ["wine", "port"]
    argv = command_line(WINE, 27025)
    assert argv[argv.index("--bottle") + 1] == BOTTLE
    assert argv.count("--bottle") == 1
    assert not any("bottle" == f.name for f in fields(Layout))
    assert layout(tmp_path).bottle_dir == TF2_BOTTLE
    for action in ("check", "start", "stop"):
        with pytest.raises(SystemExit):
            build_parser().parse_args([action, "--bottle", "Steam"])


# The launch ------------------------------------------------------------------------------


def test_launches_only_the_gmod_client(tmp_path):
    system = FakeSystem()
    client_with(tmp_path, system).launch(27025, 20)
    assert len(system.launches) == 1
    argv = system.launches[0]
    assert argv[:3] == [WINE, "--bottle", "Team Fortress 2"]
    program = argv[argv.index("--cx-app") + 1]
    assert program == GMOD + "\\gmod_win64.exe"
    assert argv[argv.index("+connect") + 1] == "127.0.0.1:27025"
    assert argv[argv.index("+con_logfile") + 1].startswith("data/ws_tests/client/")
    assert "-condebug" not in argv
    assert "--no-update" in argv[:argv.index("--cx-app")]  # never updates the operator's bottle
    assert system.signals == []


def test_records_the_one_new_client_pid(tmp_path):
    system = FakeSystem()
    client = client_with(tmp_path, system)
    recorded = client.launch(27025, 20)
    # The launcher names gmod_win64.exe in its arguments, but the client is
    # the new process that runs it.
    assert (recorded.pid, recorded.started, recorded.launcher) == (CLIENT, T1, LAUNCHER)
    assert Recorded.parse(client.layout.pid_file.read_text()) == recorded
    assert f"launched client pid {CLIENT}" in log_of(client)


def test_two_new_clients_record_none_and_signal_nothing(tmp_path):
    system = FakeSystem()
    system.clients_per_launch = 2
    client = client_with(tmp_path, system)
    with pytest.raises(NoClient):
        client.launch(27025, 20)
    assert not client.layout.pid_file.exists()
    assert system.signals == []


def helper(pid, kind="renderer", started=T1):
    """One of the client's CEF browser helpers: gmod_win64.exe again, with
    --type=, and under Wine parent 1, outside the launcher's tree."""
    return Process(pid, 1, started, HELPER.format(kind=kind))


def test_finds_the_client_among_its_browser_helpers(tmp_path):
    system = FakeSystem()
    for i, kind in enumerate(("gpu-process", "renderer", "utility")):
        system.at(system.client_delay, lambda p=helper(960 + i, kind): system.add(p))
    client = client_with(tmp_path, system)
    recorded = client.launch(27025, 20)
    assert (recorded.pid, recorded.started) == (CLIENT, T1)
    assert system.signals == []
    # The client is the one without --type= that carries our log and our
    # server; a gmod_win64.exe joining another server, or logging elsewhere,
    # is not ours.
    argv = command_line(WINE, 27025)
    ours = Process(CLIENT, 1, T1, " ".join(argv[argv.index("--cx-app") + 1:]))
    others = [
        helper(960),
        Process(970, 1, T1, ours.command.replace("27025", "27015")),
        Process(971, 1, T1, ours.command.replace("+con_logfile data/ws_tests/client/console.log", "")),
    ]
    table = ProcessTable((ours, *others))
    assert [p.pid for p in new_clients(table, frozenset(), LAUNCHER, 27025)] == [CLIENT]


def test_the_launch_logs_the_preflights_findings(tmp_path):
    client = client_with(tmp_path, FakeSystem())
    client.launch(27025, 20)
    log = log_of(client)
    assert f"steam.exe pid {STEAM} runs in Team Fortress 2" in log
    assert "CrossOver " + APP in log


# Closing ---------------------------------------------------------------------------------


def test_stop_signals_only_the_launched_client(tmp_path):
    system = FakeSystem()
    client = client_with(tmp_path, system)
    client.launch(27025, 20)
    system.add(Process(700, 1, T2, "C:\\Steam\\steamapps\\common\\Team Fortress 2\\tf_win64.exe -steam"))
    system.add(Process(960, 1, T2, GMOD + "\\gmod_win64.exe -steam"))
    client.close("stop")
    assert system.signals == [(CLIENT, signal.SIGTERM)]
    assert not client.layout.pid_file.exists()


def test_stop_leaves_a_reused_pid_alone(tmp_path):
    for i, reused in enumerate((
        Process(CLIENT, 1, T2, GMOD + "\\gmod_win64.exe -novid"),  # the same program, started later
        Process(CLIENT, 1, T2, "/usr/bin/vim notes.txt"),
    )):
        system = FakeSystem()
        client = client_with(tmp_path / f"case{i}", system)
        client.launch(27025, 20)
        system.add(reused)
        client.close("stop")
        assert system.signals == []
        assert f"pid {CLIENT} no longer runs the client" in log_of(client)


def test_stop_escalates_to_sigkill_on_the_same_pid_only(tmp_path):
    stubborn = FakeSystem()
    stubborn.obeys = {signal.SIGKILL}
    client = client_with(tmp_path / "stubborn", stubborn)
    client.launch(27025, 20)
    client.close("stop")
    assert stubborn.signals == [(CLIENT, signal.SIGTERM), (CLIENT, signal.SIGKILL)]
    assert stubborn.signal_times[1] - stubborn.signal_times[0] >= 15
    # The client exits and its pid is reused before the grace runs out.
    reused = FakeSystem()
    reused.obeys = set()
    client = client_with(tmp_path / "reused", reused)
    client.launch(27025, 20)
    reused.at(5, lambda: reused.add(Process(CLIENT, 1, T2, "/usr/bin/vim")))
    client.close("stop")
    assert reused.signals == [(CLIENT, signal.SIGTERM)]


def test_stop_reports_changed_cfg_files(tmp_path):
    system = FakeSystem()
    client = client_with(tmp_path, system)
    client.launch(27025, 20)
    cfg = client.layout.gmod_dir / "cfg"
    (cfg / "config.cfg").write_text("bind w +forward\nbind e +use\n")
    (cfg / "new.cfg").write_text("x\n")
    client.close("stop")
    changed = [line for line in log_of(client).splitlines() if "cfg changed" in line]
    assert changed and "cfg/config.cfg" in changed[-1] and "cfg/new.cfg" in changed[-1]
    assert "autoexec.cfg" not in changed[-1]


def test_stop_keeps_the_clients_console_log(tmp_path):
    system = FakeSystem()
    client = client_with(tmp_path, system)
    client.launch(27025, 20)
    client.layout.console_log.write_text("] connect 127.0.0.1:27025\n")
    client.close("stop")
    kept = list(client.layout.client_dir.glob("client_console-*.log"))
    assert len(kept) == 1 and kept[0].read_text() == "] connect 127.0.0.1:27025\n"


# The watchdog ----------------------------------------------------------------------------


def test_the_watchdog_closes_the_client_when_the_operators_game_starts(tmp_path):
    system = FakeSystem()
    client = client_with(tmp_path, system)
    recorded = client.launch(27025, 20)
    started = system.t + 30.3
    system.at(30.3, lambda: system.add(Process(700, 1, T2, "C:\\Steam\\steamapps\\common\\Team Fortress 2\\tf_win64.exe")))
    client.watch(recorded)
    assert system.signals == [(CLIENT, signal.SIGTERM)]
    assert started <= system.signal_times[0] <= started + 2
    assert "operator's game" in log_of(client)


def test_the_watchdog_closes_the_client_at_its_time_limit(tmp_path):
    system = FakeSystem()
    client = client_with(tmp_path, system)
    recorded = client.launch(27025, 1)
    client.watch(recorded)
    assert system.signals == [(CLIENT, signal.SIGTERM)]
    assert recorded.deadline <= system.signal_times[0] <= recorded.deadline + 2


def test_the_watchdog_keeps_the_client_while_its_browser_helpers_run(tmp_path):
    system = FakeSystem()
    client = client_with(tmp_path, system)
    recorded = client.launch(27025, 1)
    # The menu's browser starts a second or more after the client.
    system.at(1, lambda: system.add(helper(960, "gpu-process")))
    system.at(1, lambda: system.add(helper(961, "renderer", T1_LATER)))
    client.watch(recorded)
    assert system.signals == [(CLIENT, signal.SIGTERM)]  # never a helper
    assert recorded.deadline <= system.signal_times[0] <= recorded.deadline + 2
    log = log_of(client)
    assert "its time limit passed" in log and "operator's game" not in log
    # A helper still running once the client is closed is named, not signalled.
    assert "browser helper pid 960" in log and "browser helper pid 961" in log


def test_the_watchdog_still_closes_for_another_gmod_client(tmp_path):
    for i, other in enumerate((
        Process(980, 1, T2, GMOD + "\\gmod_win64.exe -steam"),  # the operator's own GMod
        Process(980, 1, T2, GMOD + "\\gmod.exe -steam"),
        Process(980, 1, T2, GMOD + "\\gmod_win64.exe -novid -nojoy +con_logfile "
                            "data/ws_tests/client/console.log +connect 127.0.0.1:27025"),  # a second of ours
        helper(980, "renderer", T0),  # a helper older than our client: another GMod's
    )):
        system = FakeSystem()
        client = client_with(tmp_path / f"case{i}", system)
        recorded = client.launch(27025, 20)
        system.at(1, lambda: system.add(helper(960)))
        appears = system.t + 10
        system.at(10, lambda p=other: system.add(p))
        client.watch(recorded)
        assert system.signals == [(CLIENT, signal.SIGTERM)], other
        assert appears <= system.signal_times[0] <= appears + 2, other
        assert "the operator's game started: pid 980" in log_of(client)


def test_a_client_that_appears_late_is_still_recorded_and_watched(tmp_path):
    system = FakeSystem()
    system.client_delay = 400  # past the 180 s the first search allowed
    client = client_with(tmp_path, system)
    assert run_watchdog(client, 27025, 20) == 0
    log = log_of(client)
    assert f"launched client pid {CLIENT}" in log
    assert system.signals == [(CLIENT, signal.SIGTERM)]
    assert "its time limit passed" in log


def test_a_process_table_failure_after_the_launch_keeps_looking(tmp_path):
    system = FakeSystem()
    client = client_with(tmp_path, system)
    real_launch = system.launch

    def launch_then_fail(argv):
        system.ps_failures = 5  # ps fails for the next five looks
        return real_launch(argv)

    system.launch = launch_then_fail
    assert run_watchdog(client, 27025, 1) == 0
    log = log_of(client)
    assert "cannot read the process table" in log
    assert f"launched client pid {CLIENT}" in log
    assert system.signals == [(CLIENT, signal.SIGTERM)]


def test_a_client_never_found_is_left_launched_not_recorded(tmp_path):
    system = FakeSystem()
    system.clients_per_launch = 0
    client = client_with(tmp_path, system)
    with pytest.raises(NoClient):
        client.launch(27025, 1)
    assert system.now() >= 10_000.0 + 60  # it looked until the run's deadline
    assert not client.layout.pid_file.exists()
    assert client.launched() is not None  # the state start and stop report
    assert "launched, not recorded" in log_of(client)
    assert system.signals == []


def test_stop_before_the_client_is_recorded_closes_it_once_found(tmp_path):
    system = FakeSystem()
    system.client_delay = 30
    client = client_with(tmp_path, system)
    system.at(10, lambda: client.close("stop"))  # stop while the watchdog still looks
    assert run_watchdog(client, 27025, 20) == 0
    assert system.signals == [(CLIENT, signal.SIGTERM)]
    assert system.signal_times[0] < 10_000.0 + 60
    assert "launched, not recorded" in log_of(client)
    assert not client.layout.pid_file.exists() and client.launched() is None


def test_start_says_launched_not_recorded(tmp_path):
    system = FakeSystem()
    system.clients_per_launch = 0
    client = client_with(tmp_path, system)
    with pytest.raises(NoClient):
        client.launch(27025, 1)
    code, message = gmod_client.unrecorded(client, watchdog_exit=1)
    assert code != 0 and message.startswith("launched, not recorded")
    assert str(LAUNCHER) in message
    code, message = gmod_client.unrecorded(client_with(tmp_path / "none", FakeSystem()), watchdog_exit=3)
    assert code == 3 and "launched nothing" in message


def test_the_watchdog_ends_quietly_once_stop_has_closed_the_client(tmp_path):
    system = FakeSystem()
    client = client_with(tmp_path, system)
    recorded = client.launch(27025, 20)
    system.at(10, lambda: client.close("stop"))
    client.watch(recorded)
    assert system.signals == [(CLIENT, signal.SIGTERM)]


# Reading the server's status -------------------------------------------------------------

STATUS = """hostname: Garry's Mod
map     : koth_viaduct at: 0 x, 0 y, 0 z
players : 2 (32 max)

# userid name                uniqueid            connected ping loss state  adr
#      2 "moon expr"         STEAM_0:1:1234      00:12       50    0 active loopback
#      3 "Bot01"             BOT                                     active
#      4 "joining"           STEAM_0:0:42        00:01       60    0 spawning 127.0.0.1:27005
"""


def test_players_are_the_active_humans_in_the_status():
    assert players(STATUS) == ["moon expr"]
    assert players("Unknown command") == []


def test_the_client_program_is_read_from_a_windows_path_with_spaces():
    tf2 = Process(700, 1, T0, "C:\\Steam\\steamapps\\common\\Team Fortress 2\\tf_win64.exe -steam")
    assert tf2.program == "tf_win64.exe"
    assert Process(950, 1, T0, WRAPPER + " --run -- " + GMOD + "\\gmod_win64.exe").program == "winewrapper.exe"
    assert Process(951, 1, T0, GMOD + "\\gmod_win64.exe").program == CLIENT_EXE
