#!/usr/bin/env python3
r"""Run Garry's Mod's dedicated server under CrossOver and drive it with RCON.

  srcds.py start [--map gm_construct] [--port 27025] [--no-lua-refresh]
                                                       start, wait for the map
  srcds.py rcon 'status'                               run a console command
  srcds.py stop                                        quit the server we started

The server is GMod's Windows x86-64 srcds_win64.exe in the CrossOver bottle
"Steam" and nowhere else: the operator plays in the bottle "Team Fortress 2",
and a server there ended his game once. The Steam bottle's
C:\Steam\steamapps\common\GarrysMod and ...\Team Fortress 2 are links to
the TF2 bottle's, so the files are shared and only the processes separate;
this tool writes nothing in the GMod install but the console log. It runs with -insecure -noworkshop -nosteam: without them it
crashes in steamclient64.dll while it mounts the Workshop, so Workshop addons
(DrGBase) never load on it. Its console must be a terminal: with a pipe or
/dev/null for stdin its main loop blocks in the console's GetLine before the
first frame, so a detached supervisor (this script's `_supervise`) gives it a
pty and drains it into .devtools/artifacts/srcds.log. -condebug writes
garrysmod/console.log, which holds what the console printed. +ip 127.0.0.1
keeps RCON on this machine. --no-lua-refresh adds -disableluarefresh, so edits
on disk after start-up never reach the running server (game events v2's T1).

The RCON password is kept in .devtools/artifacts/rcon_password. The
supervisor records the processes it launched in .devtools/artifacts/srcds.pid
(itself and the wine launcher; the server is the launcher's descendant).
`stop` asks the server to quit over RCON, then signals only those launched
processes still running: never a wineserver or wine's own services (even
one this launch started), never by name or pattern, never wineboot.
"""
from __future__ import annotations

import argparse
import dataclasses
import json
import os
import pty
import re
import secrets
import signal
import socket
import struct
import subprocess
import sys
import time
from collections import deque
from dataclasses import dataclass, field
from pathlib import Path
from typing import Deque, Dict, List, Optional, Set, Tuple

__all__ = [
    "AUTH",
    "AUTH_RESPONSE",
    "EXECCOMMAND",
    "RESPONSE_VALUE",
    "AuthFailed",
    "BOTTLE",
    "Install",
    "Launched",
    "Packet",
    "RconClient",
    "Server",
    "ServerConfig",
    "command_line",
    "decode_packets",
    "encode_packet",
    "map_from_status",
    "new_server",
    "stop_targets",
    "WrongBottle",
]

# Source RCON packet types (developer.valvesoftware.com/wiki/Source_RCON_Protocol).
AUTH = 3
AUTH_RESPONSE = 2
EXECCOMMAND = 2
RESPONSE_VALUE = 0
AUTH_REFUSED_ID = -1
HEADER = struct.Struct("<iii")  # size, id, type
SIZE_FIELD = 4
MIN_SLOTS = 2  # the harness's bots need room
LOCALHOST = "127.0.0.1"

REPO = Path(__file__).resolve().parents[2]
ARTIFACTS = REPO / ".devtools" / "artifacts"
PASSWORD_FILE = ARTIFACTS / "rcon_password"
PID_FILE = ARTIFACTS / "srcds.pid"
PROCESS_LOG = ARTIFACTS / "srcds.log"

BOTTLE = "Steam"  # never "Team Fortress 2", where the operator plays
BOTTLE_DIR = Path.home() / "Library/Application Support/CrossOver/Bottles" / BOTTLE
GMOD_WINDOWS = r"C:\Steam\steamapps\common\GarrysMod"
GMOD_DIR = BOTTLE_DIR / "drive_c/Steam/steamapps/common/GarrysMod/garrysmod"
WINE_RELATIVE = "Contents/SharedSupport/CrossOver/bin/wine"
CROSSOVER_APPS = (Path("/Applications/CrossOver GPTK4.app"), Path("/Applications/CrossOver.app"))
SERVER_EXE = "srcds_win64.exe"
# Processes a stop never signals, whoever started them: the bottle's
# wineserver and wine's services, which every program in the bottle shares.
NEVER_STOP = ("wineserver", "winedevice.exe", "services.exe", "explorer.exe", "plugplay.exe",
              "svchost.exe", "rpcss.exe", "winewrapper.exe --enable-alt-loader")
MAP_NAME = re.compile(r"^[A-Za-z0-9_\-]+$")
STATUS_MAP = re.compile(r"^map\s*:\s*(\S+)", re.MULTILINE)


class AuthFailed(Exception):
    pass


class ServerDown(Exception):
    pass


class WrongBottle(Exception):
    pass


@dataclass(frozen=True)
class Install:
    wine: Path
    bottle: str
    gmod_windows: str
    gmod_dir: Path

    @classmethod
    def discover(cls) -> "Install":
        """The first CrossOver installed, on the Steam bottle."""
        installed = [app for app in CROSSOVER_APPS if (app / WINE_RELATIVE).exists()]
        if not installed:
            raise ServerDown("no CrossOver under /Applications")
        return cls(installed[0] / WINE_RELATIVE, BOTTLE, GMOD_WINDOWS, GMOD_DIR)

    @property
    def console_log(self) -> Path:
        return self.gmod_dir / "console.log"

    @property
    def data_dir(self) -> Path:
        return self.gmod_dir / "data"


@dataclass(frozen=True)
class ServerConfig:
    map: str
    port: int
    rcon_password: str
    maxplayers: int
    gamemode: str = "sandcastle"
    convars: Tuple[Tuple[str, str], ...] = field(default_factory=tuple)
    lua_refresh: bool = True  # False adds -disableluarefresh

    def __post_init__(self):
        if not MAP_NAME.match(self.map):
            raise ValueError(f"not a map name: {self.map!r}")
        if not self.rcon_password or re.search(r"\s|\"", self.rcon_password):
            raise ValueError("the RCON password must be non-empty, without spaces or quotes")
        if self.maxplayers < MIN_SLOTS:
            raise ValueError(f"maxplayers {self.maxplayers}: bots need at least {MIN_SLOTS} slots")


def command_line(install: Install, config: ServerConfig) -> List[str]:
    if install.bottle != BOTTLE:
        raise WrongBottle(f"servers run only in the bottle {BOTTLE!r}, not {install.bottle!r}")
    convars = [
        ("ip", LOCALHOST),
        ("maxplayers", str(config.maxplayers)),
        ("gamemode", config.gamemode),
        ("rcon_password", config.rcon_password),
        ("sv_lan", "1"),
        ("sv_hibernate_think", "1"),
    ] + list(config.convars)
    argv = [
        str(install.wine), "--bottle", install.bottle, "--no-gui", "--no-update",
        "--workdir", install.gmod_windows,
        "--cx-app", install.gmod_windows + "\\" + SERVER_EXE,
        "-console", "-game", "garrysmod", "-port", str(config.port),
        "-insecure", "-noworkshop", "-nosteam", "-condebug", "-nohltv",
    ]
    if not config.lua_refresh:
        argv.append("-disableluarefresh")
    for name, value in convars:
        argv += ["+" + name, value]
    return argv + ["+map", config.map]


# RCON ---------------------------------------------------------------------------------


@dataclass(frozen=True)
class Packet:
    id: int
    type: int
    body: str


def encode_packet(p: Packet) -> bytes:
    body = p.body.encode("utf-8") + b"\x00\x00"
    return struct.pack("<i", HEADER.size - SIZE_FIELD + len(body)) + struct.pack("<ii", p.id, p.type) + body


def decode_packets(data: bytes) -> Tuple[List[Packet], bytes]:
    """Every whole packet at the front of data, and the bytes left over."""
    packets = []
    while len(data) >= SIZE_FIELD:
        (size,) = struct.unpack_from("<i", data)
        end = SIZE_FIELD + size
        if len(data) < end:
            break
        _, pid, ptype = HEADER.unpack_from(data)
        body = data[HEADER.size:end].rstrip(b"\x00")
        packets.append(Packet(pid, ptype, body.decode("utf-8", errors="replace")))
        data = data[end:]
    return packets, data


class RconClient:
    """One authenticated RCON connection. A command's answer may span many
    packets; an empty RESPONSE_VALUE sent after it comes back last, which
    marks the end."""

    def __init__(self, sock: socket.socket):
        self.sock = sock
        self.buffer = b""
        self.pending: Deque[Packet] = deque()
        self.next_id = 1

    @classmethod
    def connect(cls, host: str, port: int, password: str, timeout: float) -> "RconClient":
        sock = socket.create_connection((host, port), timeout=timeout)
        client = cls(sock)
        try:
            auth_id = client._send(AUTH, password)
            while True:
                p = client._receive()
                if p.type == AUTH_RESPONSE:
                    if p.id == AUTH_REFUSED_ID:
                        raise AuthFailed("RCON refused the password")
                    if p.id == auth_id:
                        return client
        except BaseException:
            sock.close()
            raise

    def command(self, text: str) -> str:
        cmd_id = self._send(EXECCOMMAND, text)
        end_id = self._send(RESPONSE_VALUE, "")
        parts = []
        while True:
            p = self._receive()
            if p.id == end_id:
                return "".join(parts)
            if p.id == cmd_id:
                parts.append(p.body)

    def close(self) -> None:
        self.sock.close()

    def __enter__(self) -> "RconClient":
        return self

    def __exit__(self, *exc) -> None:
        self.close()

    def _send(self, ptype: int, body: str) -> int:
        pid = self.next_id
        self.next_id += 1
        self.sock.sendall(encode_packet(Packet(pid, ptype, body)))
        return pid

    def _receive(self) -> Packet:
        while not self.pending:
            data = self.sock.recv(65536)
            if not data:
                raise ServerDown("RCON connection closed")
            packets, self.buffer = decode_packets(self.buffer + data)
            self.pending.extend(packets)
        return self.pending.popleft()


def map_from_status(text: str) -> Optional[str]:
    m = STATUS_MAP.search(text)
    return m.group(1) if m else None


# The server process -------------------------------------------------------------------


def running_processes() -> str:
    """`ps -axo pid=,ppid=,command=`: what stop_targets reads."""
    return subprocess.run(["ps", "-axo", "pid=,ppid=,command="], capture_output=True, text=True).stdout


def port_in_use(port: int) -> bool:
    with socket.socket() as s:
        s.settimeout(0.5)
        return s.connect_ex((LOCALHOST, port)) == 0


SUPERVISOR_MARK = "_supervise"


@dataclass(frozen=True)
class Launched:
    """What one start launched: the supervisor and the wine launcher it ran."""
    supervisor: int
    launcher: int
    port: int
    server: Optional[int] = None  # the Windows process, once found (new_server)

    def text(self) -> str:
        return json.dumps({"supervisor": self.supervisor, "launcher": self.launcher, "port": self.port,
                           "server": self.server})

    @classmethod
    def parse(cls, text: str) -> "Launched":
        data = json.loads(text)
        server = data.get("server")
        return cls(int(data["supervisor"]), int(data["launcher"]), int(data["port"]),
                   int(server) if server is not None else None)

    def alive(self, processes: str) -> bool:
        return bool(stop_targets(self, processes))


def _process_table(processes: str) -> Dict[int, Tuple[int, str]]:
    table = {}
    for line in processes.splitlines():
        parts = line.split(None, 2)
        if len(parts) == 3 and parts[0].isdigit() and parts[1].isdigit():
            table[int(parts[0])] = (int(parts[1]), parts[2])
    return table


def _descendants(root: int, table: Dict[int, Tuple[int, str]]) -> Set[int]:
    """root and every process below it."""
    tree = {root}
    grew = True
    while grew:
        grew = False
        for pid, (ppid, _) in table.items():
            if ppid in tree and pid not in tree:
                tree.add(pid)
                grew = True
    return tree


def _serves(command: str, port: int) -> bool:
    return SERVER_EXE in command and f"-port {port} " in command + " "


def new_server(launched: Launched, before: Set[int], processes: str) -> Optional[int]:
    """The server process this launch started: wine gives it parent 1, so it
    is the one srcds on our port, outside the supervisor's own tree (whose
    command lines name the server too), whose id was not running before."""
    table = _process_table(processes)
    tree = _descendants(launched.supervisor, table)
    found = [pid for pid, (_, command) in table.items()
             if pid not in before and pid not in tree and _serves(command, launched.port)]
    return found[0] if len(found) == 1 else None


def stop_targets(launched: Launched, processes: str) -> List[int]:
    """The processes a stop may signal: the supervisor this tool launched
    (still running as its supervisor, so a reused id is left alone) and its
    descendants (the wine launcher), and the server process it adopted if
    that id still runs our server; never the bottle's wineserver or wine's
    services, whoever started them."""
    table = _process_table(processes)
    server = table.get(launched.server) if launched.server is not None else None
    adopted = [launched.server] if server and _serves(server[1], launched.port) else []
    sup = table.get(launched.supervisor)
    if sup is None or SUPERVISOR_MARK not in sup[1]:
        return adopted
    ours = _descendants(launched.supervisor, table) | set(adopted)
    return sorted(pid for pid in ours if not any(name in table[pid][1] for name in NEVER_STOP))


def read_launched() -> Optional[Launched]:
    return Launched.parse(PID_FILE.read_text()) if PID_FILE.exists() else None


LAUNCH_RECORD_TIMEOUT = 10
SERVER_PROCESS_TIMEOUT = 60


@dataclass(frozen=True)
class Server:
    install: Install
    config: ServerConfig
    host: str = LOCALHOST

    def start(self) -> None:
        argv = command_line(self.install, self.config)  # refuses any bottle but Steam
        launched = read_launched()
        if launched and launched.alive(running_processes()):
            raise ServerDown(f"a server this tool started is still running on port {launched.port}; stop it first")
        if port_in_use(self.config.port):
            raise ServerDown(f"port {self.config.port} is taken")
        ARTIFACTS.mkdir(parents=True, exist_ok=True)
        PID_FILE.unlink(missing_ok=True)
        before = set(_process_table(running_processes()))
        supervisor = [sys.executable, str(Path(__file__).resolve()), SUPERVISOR_MARK, str(PROCESS_LOG),
                      str(self.config.port), "--"]
        subprocess.Popen(supervisor + argv, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)
        deadline = time.monotonic() + LAUNCH_RECORD_TIMEOUT
        while not PID_FILE.exists():
            if time.monotonic() > deadline:
                raise ServerDown("the supervisor did not record its launch")
            time.sleep(0.2)
        deadline = time.monotonic() + SERVER_PROCESS_TIMEOUT
        while time.monotonic() < deadline:
            server = new_server(read_launched(), before, running_processes())
            if server is not None:
                PID_FILE.write_text(dataclasses.replace(read_launched(), server=server).text())
                return
            time.sleep(0.5)
        raise ServerDown("no new server process appeared on the port; see " + str(PROCESS_LOG))

    def rcon(self, text: str, timeout: float = 10) -> str:
        with RconClient.connect(self.host, self.config.port, self.config.rcon_password, timeout) as client:
            return client.command(text)

    def current_map(self) -> Optional[str]:
        try:
            return map_from_status(self.rcon("status"))
        except (OSError, ServerDown):
            return None

    def wait_for_map(self, name: str, timeout: float) -> None:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if self.current_map() == name:
                return
            if not self.alive():
                raise ServerDown(f"the server exited before {name} loaded; see {PROCESS_LOG}")
            time.sleep(1)
        raise ServerDown(f"{name} was not up within {timeout:.0f} s")

    def alive(self) -> bool:
        launched = read_launched()
        return bool(launched and launched.alive(running_processes()))

    def stop(self, timeout: float = 30) -> None:
        """Quit through RCON; whatever this tool launched that outlives that
        gets SIGTERM, by process id (stop_targets), and nothing else does."""
        launched = read_launched()
        if launched is None:
            return
        try:
            self.rcon("quit", timeout=5)
        except (OSError, ServerDown, AuthFailed):
            pass
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline and launched.alive(running_processes()):
            time.sleep(1)
        for pid in stop_targets(launched, running_processes()):
            os.kill(pid, signal.SIGTERM)
        PID_FILE.unlink()


# The supervisor: owns the server's terminal ------------------------------------------


def supervise(log_path: Path, port: int, argv: List[str]) -> int:
    master, slave = pty.openpty()
    proc = subprocess.Popen(argv, stdin=slave, stdout=slave, stderr=slave)
    os.close(slave)
    PID_FILE.write_text(Launched(os.getpid(), proc.pid, port).text())
    with open(log_path, "wb") as log:
        while True:
            try:
                data = os.read(master, 65536)
            except OSError:
                break
            if not data:
                break
            log.write(data)
            log.flush()
    return proc.wait()


def password() -> str:
    if not PASSWORD_FILE.exists():
        ARTIFACTS.mkdir(parents=True, exist_ok=True)
        PASSWORD_FILE.write_text(secrets.token_hex(12))
    return PASSWORD_FILE.read_text().strip()


def started_port(default: int) -> int:
    launched = read_launched()
    return launched.port if launched else default


DEFAULT_PORT = 27025  # beside the client's 27015, so the operator's own game keeps its port
DEFAULT_MAXPLAYERS = 32
MAP_LOAD_TIMEOUT = 240


def make_server(map_name: str, port: int, lua_refresh: bool = True) -> Server:
    install = Install.discover()
    return Server(install, ServerConfig(map_name, port, password(), DEFAULT_MAXPLAYERS, lua_refresh=lua_refresh))


def main() -> int:
    if sys.argv[1:2] == [SUPERVISOR_MARK]:
        return supervise(Path(sys.argv[2]), int(sys.argv[3]), sys.argv[5:])
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="action", required=True)
    start = sub.add_parser("start")
    start.add_argument("--map", default="gm_construct")
    start.add_argument("--port", type=int, default=DEFAULT_PORT)
    start.add_argument("--no-lua-refresh", dest="lua_refresh", action="store_false",
                       help="start with -disableluarefresh: edits on disk never reach the running server")
    rcon = sub.add_parser("rcon")
    rcon.add_argument("command")
    sub.add_parser("stop")
    args = ap.parse_args()
    try:
        if args.action == "start":
            server = make_server(args.map, args.port, args.lua_refresh)
            server.start()
            server.wait_for_map(args.map, MAP_LOAD_TIMEOUT)
            print(f"{args.map} is up on port {args.port}")
        elif args.action == "rcon":
            print(make_server("gm_construct", started_port(DEFAULT_PORT)).rcon(args.command))
        else:
            make_server("gm_construct", started_port(DEFAULT_PORT)).stop()
    except (ServerDown, AuthFailed, OSError) as e:
        print(f"srcds: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
