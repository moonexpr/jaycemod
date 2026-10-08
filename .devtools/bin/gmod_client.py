#!/usr/bin/env python3
r"""Launch and close the Garry's Mod client for game events v2's client tests
(T1 to T5), in the CrossOver bottle "Team Fortress 2" and nowhere else.

  gmod_client.py check                                 the preflight alone: exit 0 if a launch is allowed, 3 if not
  gmod_client.py start [--port 27025] [--minutes 20]   preflight, launch, wait until the server lists the player
  gmod_client.py stop                                  close the client this tool launched, and keep its log

The operator plays TF2 in that bottle, and a server there once ended his
game, so this tool's safeguards are its tested behaviour
(test_gmod_client.py):

- The preflight refuses, and launches nothing, while any tf_win64.exe, tf.exe
  or hl2.exe runs (in any bottle: the name alone is enough), while any
  gmod.exe or gmod_win64.exe runs, while Steam is not already running in the
  bottle (launching GMod would start it there), or while the client this
  tool recorded still runs.
- The launch is one command: the bottle's own CrossOver wine (the one its
  Steam has mapped, so the bottle's wineserver sees its own version), with
  --bottle "Team Fortress 2" and --no-update, running gmod_win64.exe with
  +con_logfile under data/wetsand_tests/client/ (never -condebug: the
  dedicated server writes console.log in the shared install) and +connect
  to the dedicated server srcds.py runs in the bottle "Steam". The bottle is
  a constant; there is no option for another.
- The client is the one new process running gmod_win64.exe; its pid and
  start time go to .devtools/artifacts/gmod_client.pid.
- A detached watchdog checks every second and closes the client when the
  operator's game starts or the time limit passes.
- Closing signals only the recorded pid, and only while it still runs
  gmod_win64.exe with the recorded start time: SIGTERM, then SIGKILL 15 s
  later. Never the wine launcher, a wineserver, wine's services, Steam or
  its web helper, and never anything found by name or pattern.

Everything found and done is appended to
.devtools/artifacts/gev2-research/client/gmod_client.log; closing copies the
client's console log beside it as client_console-<UTC time>.log and lists
any garrysmod/cfg/*.cfg that changed during the run.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shlex
import shutil
import signal
import subprocess
import sys
import time
import traceback
from abc import ABC, abstractmethod
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, FrozenSet, Iterable, List, Optional, Sequence, Tuple

sys.path.insert(0, str(Path(__file__).resolve().parent))
import srcds  # noqa: E402

__all__ = [
    "BOTTLE",
    "CLIENT_EXE",
    "GmodClient",
    "Layout",
    "NoClient",
    "OsSystem",
    "Opened",
    "Preflight",
    "Process",
    "ProcessTable",
    "Recorded",
    "Refused",
    "System",
    "build_parser",
    "command_line",
    "new_clients",
    "operator_game",
    "parse_lsof",
    "players",
    "preflight",
]

BOTTLE = "Team Fortress 2"  # the operator's bottle; the client's only one, and no option changes it
BOTTLES = Path.home() / "Library/Application Support/CrossOver/Bottles"
GMOD_WINDOWS = "C:\\Steam\\steamapps\\common\\GarrysMod"
GMOD_RELATIVE = "drive_c/Steam/steamapps/common/GarrysMod/garrysmod"
WINE_RELATIVE = "/Contents/SharedSupport/CrossOver/bin/wine"
CROSSOVER_APP = re.compile(r"^(/.*?/CrossOver[^/]*\.app)/Contents/")

CLIENT_EXE = "gmod_win64.exe"
STEAM_EXE = "steam.exe"
OPERATOR_GAMES = ("tf_win64.exe", "tf.exe", "hl2.exe")
GMOD_CLIENTS = ("gmod.exe", "gmod_win64.exe")
REFUSED_NAMES = OPERATOR_GAMES + GMOD_CLIENTS

CLIENT_LOG = "data/wetsand_tests/client/console.log"  # +con_logfile, relative to garrysmod/
LOCALHOST = "127.0.0.1"

FIND_INTERVAL = 0.5  # s between looks for the new client after the launch
FIND_TIMEOUT = 180  # s; wine makes the Windows process within seconds
WATCH_INTERVAL = 1  # s; so the operator's game closes the client within 2 s
TERM_GRACE = 15  # s from SIGTERM to SIGKILL
KILL_WAIT = 5  # s to see SIGKILL take
JOIN_TIMEOUT = 600  # s for the client to load and join
JOIN_INTERVAL = 2
DEFAULT_MINUTES = 20
MAX_MINUTES = 180
EXIT_REFUSED = 3
WATCH_MARK = "_watch"

# `ps -axo pid=,ppid=,lstart=,command=` under LC_ALL=C: lstart is
# "%a %b %e %H:%M:%S %Y", kept verbatim as the process's start time.
PS_LINE = re.compile(r"^\s*(\d+)\s+(\d+)\s+(\w{3} \w{3} [ \d]\d \d\d:\d\d:\d\d \d{4})\s+(.*?)\s*$")
WINDOWS_PROGRAM = re.compile(r"^[A-Za-z]:[\\/].*?\.exe(?=\s|$)", re.IGNORECASE)
STATUS_PLAYER = re.compile(r'^#\s*\d+\s+"(?P<name>.*)"\s+(?P<id>\S+)(?P<rest>.*)$')


class Refused(Exception):
    """The preflight found a reason not to launch; nothing was launched."""

    def __init__(self, preflight: "Preflight"):
        super().__init__("; ".join(preflight.refusals))
        self.preflight = preflight


class NoClient(Exception):
    """The launch made no single new client to record."""


# Values ----------------------------------------------------------------------------------


@dataclass(frozen=True)
class Process:
    pid: int
    ppid: int
    started: str  # ps's lstart, verbatim
    command: str

    @property
    def program(self) -> str:
        """The file name it runs, lower case: a Windows process shows its
        Windows path (which may hold spaces), anything else its first word."""
        m = WINDOWS_PROGRAM.match(self.command)
        path = m.group(0) if m else (self.command.split(None, 1) or [""])[0]
        return re.split(r"[\\/]", path)[-1].lower()

    def named(self, exes: Iterable[str]) -> Optional[str]:
        """The first of exes its command line names anywhere, as a path's last
        part or a word: stricter than what it runs, so a launcher counts."""
        for exe in exes:
            if re.search(r"(?:^|[\s\\/\"'])" + re.escape(exe) + r"(?=$|[\s\"'])", self.command, re.IGNORECASE):
                return exe
        return None


@dataclass(frozen=True)
class ProcessTable:
    processes: Tuple[Process, ...]

    @classmethod
    def parse(cls, text: str) -> "ProcessTable":
        found = []
        for line in text.splitlines():
            m = PS_LINE.match(line)
            if m:
                found.append(Process(int(m.group(1)), int(m.group(2)), m.group(3), m.group(4)))
        return cls(tuple(found))

    def get(self, pid: int) -> Optional[Process]:
        return next((p for p in self.processes if p.pid == pid), None)

    def pids(self) -> FrozenSet[int]:
        return frozenset(p.pid for p in self.processes)

    def descendants(self, root: int) -> FrozenSet[int]:
        """root and every process below it."""
        tree = {root}
        grew = True
        while grew:
            grew = False
            for p in self.processes:
                if p.ppid in tree and p.pid not in tree:
                    tree.add(p.pid)
                    grew = True
        return frozenset(tree)

    def runs(self, recorded: "Recorded") -> bool:
        """Whether the recorded pid still runs the client it launched: the
        same program, started at the same time, so a reused pid is not it."""
        p = self.get(recorded.pid)
        return p is not None and p.started == recorded.started and p.program == CLIENT_EXE


@dataclass(frozen=True)
class Opened:
    """What lsof shows of one process: its working directory and its files."""
    cwd: Optional[str]
    files: Tuple[str, ...]


def parse_lsof(text: str) -> Dict[int, Opened]:
    """`lsof -p PIDS -Ffn` output, by pid."""
    cwd: Dict[int, Optional[str]] = {}
    files: Dict[int, List[str]] = {}
    pid = None
    fd = None
    for line in text.splitlines():
        tag, value = line[:1], line[1:]
        if tag == "p":
            pid = int(value)
            cwd.setdefault(pid, None)
            files.setdefault(pid, [])
        elif tag == "f":
            fd = value
        elif tag == "n" and pid is not None:
            files[pid].append(value)
            if fd == "cwd":
                cwd[pid] = value
    return {p: Opened(cwd[p], tuple(files[p])) for p in cwd}


@dataclass(frozen=True)
class Recorded:
    """The client one launch made, as gmod_client.pid keeps it."""
    pid: int
    started: str
    launcher: int  # the wine launcher's pid: never signalled, only excluded
    port: int
    deadline: float  # epoch seconds; the watchdog closes the client then
    baseline: Tuple[int, ...]  # every pid running when the client was found
    cfg: Tuple[Tuple[str, str], ...]  # garrysmod/cfg/*.cfg and their SHA-256 at launch

    def text(self) -> str:
        return json.dumps({
            "pid": self.pid,
            "started": self.started,
            "launcher": self.launcher,
            "port": self.port,
            "deadline": self.deadline,
            "baseline": list(self.baseline),
            "cfg": dict(self.cfg),
        })

    @classmethod
    def parse(cls, text: str) -> "Recorded":
        data = json.loads(text)
        return cls(int(data["pid"]), str(data["started"]), int(data["launcher"]), int(data["port"]),
                   float(data["deadline"]), tuple(int(p) for p in data["baseline"]),
                   tuple(sorted((str(k), str(v)) for k, v in data["cfg"].items())))


@dataclass(frozen=True)
class Preflight:
    findings: Tuple[str, ...]
    refusals: Tuple[str, ...]
    wine: Optional[str]  # the bottle's CrossOver wine, when one could be told

    @property
    def allowed(self) -> bool:
        return not self.refusals and self.wine is not None


@dataclass(frozen=True)
class Layout:
    pid_file: Path
    client_dir: Path  # .devtools/artifacts/gev2-research/client
    gmod_dir: Path  # the shared install's garrysmod/
    bottles: Path  # CrossOver's Bottles folder; the bottle itself is BOTTLE

    @classmethod
    def default(cls) -> "Layout":
        return cls(
            pid_file=srcds.ARTIFACTS / "gmod_client.pid",
            client_dir=srcds.ARTIFACTS / "gev2-research" / "client",
            gmod_dir=BOTTLES / BOTTLE / GMOD_RELATIVE,
            bottles=BOTTLES,
        )

    @property
    def bottle_dir(self) -> Path:
        return self.bottles / BOTTLE

    @property
    def log_file(self) -> Path:
        return self.client_dir / "gmod_client.log"

    @property
    def wine_log(self) -> Path:
        return self.client_dir / "wine.log"

    @property
    def console_log(self) -> Path:
        return self.gmod_dir / CLIENT_LOG


# Rules -----------------------------------------------------------------------------------


def _under(path: Optional[str], folder: Path) -> bool:
    if path is None:
        return False
    p = Path(path)
    return p == folder or folder in p.parents


def preflight(table: ProcessTable, opened: Dict[int, Opened], recorded: Optional[Recorded],
              bottle_dir: Path) -> Preflight:
    """Whether a launch is allowed, and why not: pure, from the process table,
    lsof's view of each steam.exe, and the last record."""
    findings: List[str] = []
    refusals: List[str] = []
    for p in table.processes:
        game = p.named(OPERATOR_GAMES)
        if game:
            refusals.append(f"the operator's game runs: pid {p.pid} names {game}")
        gmod = p.named(GMOD_CLIENTS)
        if gmod:
            refusals.append(f"a GMod client runs: pid {p.pid} names {gmod}")
    in_bottle = []
    for p in table.processes:
        if p.program != STEAM_EXE:
            continue
        seen = opened.get(p.pid, Opened(None, ()))
        if _under(seen.cwd, bottle_dir):
            in_bottle.append(seen)
            findings.append(f"steam.exe pid {p.pid} runs in {BOTTLE}")
        else:
            findings.append(f"steam.exe pid {p.pid} runs outside {BOTTLE} (cwd {seen.cwd})")
    if not in_bottle:
        refusals.append(f"no steam.exe runs in the bottle {BOTTLE!r}; this tool never starts Steam there")
    apps = sorted({m.group(1) for seen in in_bottle for f in seen.files for m in [CROSSOVER_APP.match(f)] if m})
    wine = None
    if len(apps) == 1:
        wine = apps[0] + WINE_RELATIVE
        findings.append(f"CrossOver {apps[0]} runs the bottle")
    elif in_bottle:
        refusals.append("cannot tell which CrossOver runs the bottle: " + (", ".join(apps) or "none mapped"))
    if recorded is not None and table.runs(recorded):
        refusals.append(f"gmod_client.pid names client pid {recorded.pid}, which still runs; stop it first")
    if not any(p.named(REFUSED_NAMES) for p in table.processes):
        findings.append("no TF2 and no GMod client running")
    return Preflight(tuple(findings), tuple(refusals), wine)


def command_line(wine: str, port: int) -> List[str]:
    """The one launch: gmod_win64.exe in the bottle BOTTLE, joining our server."""
    return [
        wine, "--bottle", BOTTLE, "--no-gui", "--no-update",
        "--workdir", GMOD_WINDOWS,
        "--cx-app", GMOD_WINDOWS + "\\" + CLIENT_EXE,
        "-novid", "-nojoy",
        "+con_logfile", CLIENT_LOG,
        "+connect", f"{LOCALHOST}:{port}",
    ]


def new_clients(table: ProcessTable, before: FrozenSet[int], launcher: int) -> List[Process]:
    """The processes running gmod_win64.exe that did not run before the launch,
    outside the launcher's own tree (wine gives the client parent 1)."""
    ours = table.descendants(launcher)
    return [p for p in table.processes if p.program == CLIENT_EXE and p.pid not in before and p.pid not in ours]


def operator_game(table: ProcessTable, recorded: Recorded) -> Optional[Process]:
    """A process that means the operator's game (or another GMod) started:
    one running any refused name, or a new one naming it, other than our
    client and its launcher's tree."""
    ours = table.descendants(recorded.launcher) | {recorded.pid}
    for p in table.processes:
        if p.pid in ours:
            continue
        if p.program in REFUSED_NAMES or (p.pid not in recorded.baseline and p.named(REFUSED_NAMES)):
            return p
    return None


def players(status: str) -> List[str]:
    """The active human players in the server's `status`."""
    names = []
    for line in status.splitlines():
        m = STATUS_PLAYER.match(line.strip())
        if m and m.group("id") != "BOT" and re.search(r"\bactive\b", m.group("rest")):
            names.append(m.group("name"))
    return names


# I/O -------------------------------------------------------------------------------------


class System(ABC):
    """The client's only door to processes, signals and time."""

    @abstractmethod
    def processes(self) -> str:
        """`ps -axo pid=,ppid=,lstart=,command=`."""

    @abstractmethod
    def lsof(self, pids: Sequence[int]) -> str:
        """`lsof -p PIDS -Ffn`: read only."""

    @abstractmethod
    def launch(self, argv: Sequence[str]) -> int:
        """Start argv detached; its pid."""

    @abstractmethod
    def signal(self, pid: int, sig: int) -> None: ...

    @abstractmethod
    def now(self) -> float:
        """Epoch seconds."""

    @abstractmethod
    def sleep(self, seconds: float) -> None: ...


@dataclass(frozen=True)
class OsSystem(System):
    wine_log: Path

    def processes(self) -> str:
        return subprocess.run(["ps", "-axo", "pid=,ppid=,lstart=,command="], capture_output=True, text=True,
                              errors="replace", check=True, env={**os.environ, "LC_ALL": "C"}).stdout

    def lsof(self, pids: Sequence[int]) -> str:
        # lsof exits 1 when a pid has gone meanwhile; what it printed still holds.
        return subprocess.run(["lsof", "-p", ",".join(str(p) for p in pids), "-Ffn"], capture_output=True,
                              text=True, errors="replace").stdout

    def launch(self, argv: Sequence[str]) -> int:
        self.wine_log.parent.mkdir(parents=True, exist_ok=True)
        with open(self.wine_log, "ab") as log:
            return subprocess.Popen(list(argv), stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT,
                                    start_new_session=True).pid

    def signal(self, pid: int, sig: int) -> None:
        os.kill(pid, sig)

    def now(self) -> float:
        return time.time()

    def sleep(self, seconds: float) -> None:
        time.sleep(seconds)


def _utc(epoch: float, fmt: str = "%Y-%m-%dT%H:%M:%SZ") -> str:
    return time.strftime(fmt, time.gmtime(epoch))


# The controller --------------------------------------------------------------------------


@dataclass(frozen=True)
class GmodClient:
    system: System
    layout: Layout

    def log(self, message: str) -> None:
        self.layout.client_dir.mkdir(parents=True, exist_ok=True)
        with open(self.layout.log_file, "a") as log:
            log.write(f"{_utc(self.system.now())} {message}\n")

    def table(self) -> ProcessTable:
        return ProcessTable.parse(self.system.processes())

    def recorded(self) -> Optional[Recorded]:
        pid_file = self.layout.pid_file
        return Recorded.parse(pid_file.read_text()) if pid_file.exists() else None

    def check(self) -> Preflight:
        table = self.table()
        steam = [p.pid for p in table.processes if p.program == STEAM_EXE]
        opened = parse_lsof(self.system.lsof(steam)) if steam else {}
        return preflight(table, opened, self.recorded(), self.layout.bottle_dir)

    def launch(self, port: int, minutes: float) -> Recorded:
        """Preflight, launch, and record the one new client; raises Refused
        (nothing launched) or NoClient (nothing recorded, nothing signalled)."""
        found = self.check()
        self.log("preflight: " + "; ".join(found.findings + found.refusals))
        if not found.allowed:
            self.log("refused; launched nothing")
            raise Refused(found)
        cfg = self._cfg()
        self.layout.console_log.parent.mkdir(parents=True, exist_ok=True)
        self.layout.console_log.unlink(missing_ok=True)  # each run's log is its own
        before = self.table().pids()
        argv = command_line(found.wine, port)
        launched_at = self.system.now()
        launcher = self.system.launch(argv)
        self.log(f"launched {shlex.join(argv)} (wine launcher pid {launcher})")
        give_up = launched_at + FIND_TIMEOUT
        while True:
            table = self.table()
            new = new_clients(table, before, launcher)
            if len(new) == 1:
                break
            if len(new) > 1:
                self.log(f"{len(new)} new {CLIENT_EXE} processes ({', '.join(str(p.pid) for p in new)}): "
                         "cannot tell ours; recorded none, signalled none")
                raise NoClient("more than one new client appeared")
            if self.system.now() >= give_up:
                self.log(f"no new {CLIENT_EXE} within {FIND_TIMEOUT} s; recorded none")
                raise NoClient(f"no client appeared within {FIND_TIMEOUT} s")
            self.system.sleep(FIND_INTERVAL)
        client = new[0]
        recorded = Recorded(client.pid, client.started, launcher, port, launched_at + minutes * 60,
                            tuple(sorted(table.pids())), cfg)
        self.layout.pid_file.parent.mkdir(parents=True, exist_ok=True)
        self.layout.pid_file.write_text(recorded.text())
        self.log(f"launched client pid {client.pid} (started {client.started}); "
                 f"the watchdog closes it by {_utc(recorded.deadline)}")
        return recorded

    def watch(self, recorded: Recorded) -> None:
        """Until the client is gone: close it when the operator's game starts
        or the time limit passes."""
        while True:
            if self.recorded() != recorded:
                self.log(f"watchdog: client pid {recorded.pid} is no longer recorded; the watchdog ends")
                return
            table = self.table()
            if not table.runs(recorded):
                self.close("the client exited")
                return
            game = operator_game(table, recorded)
            if game is not None:
                self.close(f"the operator's game started: pid {game.pid} {game.program}")
                return
            if self.system.now() >= recorded.deadline:
                self.close("its time limit passed")
                return
            self.system.sleep(WATCH_INTERVAL)

    def close(self, reason: str) -> None:
        """Signal only the recorded client, then keep its log and report cfg changes."""
        recorded = self.recorded()
        if recorded is None:
            self.log(f"close ({reason}): no client recorded; nothing to do")
            return
        self.log(f"closing client pid {recorded.pid}: {reason}")
        if self._signal_if_ours(recorded, signal.SIGTERM):
            if not self._gone_within(recorded, TERM_GRACE) and self._signal_if_ours(recorded, signal.SIGKILL):
                if not self._gone_within(recorded, KILL_WAIT):
                    self.log(f"pid {recorded.pid} still runs after SIGKILL")
            if not self.table().runs(recorded):
                self.log(f"client pid {recorded.pid} has exited")
        self._keep_console_log()
        self._report_cfg(recorded)
        self.layout.pid_file.unlink(missing_ok=True)
        self.log("closed")

    def _signal_if_ours(self, recorded: Recorded, sig: int) -> bool:
        """Signal the recorded pid only while it still runs the client this
        tool launched (the check and the signal are back to back)."""
        if not self.table().runs(recorded):
            self.log(f"pid {recorded.pid} no longer runs the client it launched; "
                     f"{signal.Signals(sig).name} not sent")
            return False
        self.system.signal(recorded.pid, sig)
        self.log(f"sent {signal.Signals(sig).name} to pid {recorded.pid}")
        return True

    def _gone_within(self, recorded: Recorded, seconds: float) -> bool:
        give_up = self.system.now() + seconds
        while self.table().runs(recorded):
            if self.system.now() >= give_up:
                return False
            self.system.sleep(1)
        return True

    def _cfg(self) -> Tuple[Tuple[str, str], ...]:
        cfg_dir = self.layout.gmod_dir / "cfg"
        return tuple(sorted((f"cfg/{p.name}", hashlib.sha256(p.read_bytes()).hexdigest())
                            for p in cfg_dir.glob("*.cfg")))

    def _report_cfg(self, recorded: Recorded) -> None:
        before, after = dict(recorded.cfg), dict(self._cfg())
        changed = sorted(name for name in set(before) | set(after) if before.get(name) != after.get(name))
        self.log("cfg changed during the run: " + ", ".join(changed) if changed else "cfg unchanged")

    def _keep_console_log(self) -> None:
        source = self.layout.console_log
        if not source.exists():
            self.log(f"the client wrote no {CLIENT_LOG}")
            return
        kept = self.layout.client_dir / f"client_console-{_utc(self.system.now(), '%Y%m%dT%H%M%SZ')}.log"
        shutil.copyfile(source, kept)
        self.log(f"kept the client's console log as {kept.name}")


# The command line ------------------------------------------------------------------------


def _minutes(text: str) -> float:
    value = float(text)
    if not 0 < value <= MAX_MINUTES:
        raise argparse.ArgumentTypeError(f"minutes must be above 0 and at most {MAX_MINUTES}")
    return value


def build_parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="action", required=True)
    sub.add_parser("check")
    start = sub.add_parser("start")
    start.add_argument("--port", type=int, default=srcds.DEFAULT_PORT)
    start.add_argument("--minutes", type=_minutes, default=DEFAULT_MINUTES)
    sub.add_parser("stop")
    watch = sub.add_parser(WATCH_MARK)  # the detached watchdog start spawns
    watch.add_argument("port", type=int)
    watch.add_argument("minutes", type=_minutes)
    return ap


def _print_preflight(found: Preflight) -> None:
    for line in found.findings:
        print(f"found: {line}")
    for line in found.refusals:
        print(f"refused: {line}")


def run_watchdog(client: GmodClient, port: int, minutes: float) -> int:
    try:
        recorded = client.launch(port, minutes)
    except Refused:
        return EXIT_REFUSED
    except NoClient:
        return 1
    except OSError as e:
        client.log(f"the launch failed: {e}")
        return 1
    try:
        client.watch(recorded)
    except Exception:
        client.log("the watchdog failed:\n" + traceback.format_exc())
        client.close("the watchdog failed")
        raise
    return 0


def run_start(client: GmodClient, port: int, minutes: float) -> int:
    server = srcds.make_server("gm_construct", port)
    try:
        server.rcon("status", timeout=5)
    except (OSError, srcds.ServerDown, srcds.AuthFailed) as e:
        print(f"gmod_client: no dedicated server answers on port {port} ({e}); start it with srcds.py first",
              file=sys.stderr)
        return 1
    found = client.check()
    _print_preflight(found)
    if not found.allowed:
        client.log("start refused: " + "; ".join(found.refusals))
        return EXIT_REFUSED
    watchdog = subprocess.Popen([sys.executable, str(Path(__file__).resolve()), WATCH_MARK, str(port), str(minutes)],
                                stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                start_new_session=True)
    give_up = time.monotonic() + FIND_TIMEOUT + 30
    while client.recorded() is None:
        if watchdog.poll() is not None or time.monotonic() > give_up:
            print(f"gmod_client: no client was launched; see {client.layout.log_file}", file=sys.stderr)
            return 1
        time.sleep(1)
    print(f"client pid {client.recorded().pid} launched; waiting for it to join (up to {JOIN_TIMEOUT} s)")
    give_up = time.monotonic() + JOIN_TIMEOUT
    while time.monotonic() < give_up:
        if client.recorded() is None:
            print(f"gmod_client: the client was closed before it joined; see {client.layout.log_file}",
                  file=sys.stderr)
            return 1
        try:
            joined = players(server.rcon("status"))
        except (OSError, srcds.ServerDown, srcds.AuthFailed):
            joined = []
        if joined:
            client.log(f"joined the server as {', '.join(joined)}")
            print(f"joined as {', '.join(joined)}")
            return 0
        time.sleep(JOIN_INTERVAL)
    client.close(f"it did not join within {JOIN_TIMEOUT} s")
    print("gmod_client: the client did not join; closed it", file=sys.stderr)
    return 1


def main(argv: Optional[Sequence[str]] = None) -> int:
    args = build_parser().parse_args(argv)
    layout = Layout.default()
    client = GmodClient(OsSystem(layout.wine_log), layout)
    if args.action == "check":
        found = client.check()
        _print_preflight(found)
        return 0 if found.allowed else EXIT_REFUSED
    if args.action == "stop":
        client.close("stop")
        return 0
    if args.action == WATCH_MARK:
        return run_watchdog(client, args.port, args.minutes)
    return run_start(client, args.port, args.minutes)


if __name__ == "__main__":
    sys.exit(main())
