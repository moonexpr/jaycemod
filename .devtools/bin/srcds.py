#!/usr/bin/env python3
r"""Run Garry's Mod's dedicated server under CrossOver and drive it with RCON.

  srcds.py start [--map gm_construct] [--port 27025] [--maxplayers 32] [--ip 0.0.0.0] [--no-lua-refresh] [--p2p]
                                                       start, wait for the map
  srcds.py rcon 'status'                               run a console command
  srcds.py stop                                        quit the server we started
  srcds.py console                                     follow its console in an iTerm window
  srcds.py --instance 2 start ...                      the same for a second server beside the first

Each instance (server_root.Instance; 1, the default, is the main server) has
its own root, launch record srcds[-n].pid, log srcds[-n].log and default port
(DEFAULT_PORT, then INSTANCE_PORT_STEP apart), so two can run side by side.

The server is GMod's Windows x86-64 srcds_win64.exe in the CrossOver bottle
"GModServer" and nowhere else: the operator plays in the bottle "Steam",
and a server there ended the operator's game once. The GModServer bottle's
C:\Steam\steamapps\common\GarrysMod and ...\Team Fortress 2 are links to
the Steam bottle's, so the files are shared and only the processes separate.
The server runs from GarrysModServer beside it, which `start` builds out of
symlinks (server_root.py): its addons/, data/, cache/ and console log are
its own, so it writes nothing in the shared install. It runs with -insecure
-noworkshop -nosteam: without them it crashes in steamclient64.dll while it
mounts the Workshop; the Workshop addons it needs (DrGBase) are mounted from
the operator's downloads by server_root's autorun instead. Its console must be a terminal: with a pipe or
/dev/null for stdin its main loop blocks in the console's GetLine before the
first frame, so a detached supervisor (this script's `_supervise`) gives it a
pty and drains it into .devtools/artifacts/srcds.log. The exe server_root
places is marked a console program, so Wine hands it that pty instead of
opening a console window: the log holds the console's ANSI colors, and
`console` (or `start --console`) follows it in an iTerm window with the
profile ITERM_PROFILE, a dark one, which suits GMod's truecolor text. -condebug writes
garrysmod/console.log, which holds what the console printed. +ip binds every
interface, DEFAULT_BIND_HOST, so the operator can play from another machine on
the tailnet and the server logs on to Steam (bound to the tailnet address
alone, it cannot reach Steam); --ip takes an address or a name (bind_address),
and --ip 127.0.0.1 keeps the server and its RCON on this machine. --no-lua-refresh adds -disableluarefresh, so edits
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
import fcntl
import json
import os
import pty
import re
import secrets
import shlex
import signal
import socket
import struct
import subprocess
import sys
import termios
import time
from collections import deque
from dataclasses import dataclass, field
from pathlib import Path
from typing import Deque, Dict, List, Optional, Set, Tuple

import server_root
from server_root import MAIN_INSTANCE, Instance, Layout

__all__ = [
    "AUTH",
    "AUTH_RESPONSE",
    "EXECCOMMAND",
    "RESPONSE_VALUE",
    "AuthFailed",
    "CONSOLE_COLUMNS",
    "BOTTLE",
    "Install",
    "InstanceFiles",
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
ALL_INTERFACES = "0.0.0.0"
# start binds every interface by default, so the operator can play from other
# machines on the tailnet and the server can log on to Steam: bound to the
# tailnet address alone, its Steam sockets are too, and Steam is unreachable
# from there. --ip 127.0.0.1 keeps it to this Mac.
DEFAULT_BIND_HOST = ALL_INTERFACES

REPO = Path(__file__).resolve().parents[2]
ARTIFACTS = REPO / ".devtools" / "artifacts"
PASSWORD_FILE = ARTIFACTS / "rcon_password"
PID_FILE = ARTIFACTS / "srcds.pid"
PROCESS_LOG = ARTIFACTS / "srcds.log"

BOTTLE = "GModServer"  # never "Steam", where the operator plays
BOTTLE_DIR = Path.home() / "Library/Application Support/CrossOver/Bottles" / BOTTLE
MAIN = Instance(MAIN_INSTANCE)
GMOD_WINDOWS = MAIN.root_windows
GMOD_DIR = MAIN.root / "garrysmod"
WINE_RELATIVE = "Contents/SharedSupport/CrossOver/bin/wine"
CROSSOVER_APPS = (Path.home() / "Applications/CrossOver Preview.app",)
SERVER_EXE = server_root.SERVER_EXE
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


class BindAddressUnknown(Exception):
    """The host to bind has no address (Tailscale off, say)."""


def bind_address(host: str, resolve=socket.gethostbyname) -> str:
    """The address srcds's +ip takes for host: an address as it is, a name
    resolved; one that does not resolve is refused, not bound elsewhere."""
    try:
        socket.inet_aton(host)
        return host
    except OSError:
        pass
    try:
        return resolve(host)
    except OSError as e:
        raise BindAddressUnknown(
            f"cannot bind {host}: it does not resolve ({e}); is Tailscale up? "
            f"--ip 127.0.0.1 binds this Mac only") from e


def reach_address(bound: str) -> str:
    """Where this Mac reaches a server bound to bound (RCON, stop)."""
    return LOCALHOST if bound == ALL_INTERFACES else bound


class WrongBottle(Exception):
    pass


@dataclass(frozen=True)
class Install:
    wine: Path
    bottle: str
    gmod_windows: str
    gmod_dir: Path

    @classmethod
    def on(cls, wine: Path, instance: Instance) -> "Install":
        """The instance's server, run by `wine` on the Steam bottle."""
        return cls(wine, BOTTLE, instance.root_windows, instance.root / "garrysmod")

    @classmethod
    def discover(cls, instance: Instance = MAIN) -> "Install":
        """The first CrossOver installed, on the Steam bottle."""
        installed = [app for app in CROSSOVER_APPS if (app / WINE_RELATIVE).exists()]
        if not installed:
            raise ServerDown("no CrossOver under /Applications")
        return cls.on(installed[0] / WINE_RELATIVE, instance)

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
    ip: str = LOCALHOST  # the address it binds, game and RCON alike
    p2p: bool = False  # True adds -p2p and sv_lan 0, so Steam friends can join

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
        ("ip", config.ip),
        ("maxplayers", str(config.maxplayers)),
        ("gamemode", config.gamemode),
        ("rcon_password", config.rcon_password),
        ("sv_lan", "0" if config.p2p else "1"),
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
    if config.p2p:
        argv.append("-p2p")
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


def port_in_use(host: str, port: int) -> bool:
    with socket.socket() as s:
        s.settimeout(0.5)
        return s.connect_ex((host, port)) == 0


SUPERVISOR_MARK = "_supervise"


@dataclass(frozen=True)
class Launched:
    """What one start launched: the supervisor and the wine launcher it ran."""
    supervisor: int
    launcher: int
    port: int
    server: Optional[int] = None  # the Windows process, once found (new_server)
    host: str = LOCALHOST  # the address it binds (+ip)

    def text(self) -> str:
        return json.dumps({"supervisor": self.supervisor, "launcher": self.launcher, "port": self.port,
                           "server": self.server, "host": self.host})

    @classmethod
    def parse(cls, text: str) -> "Launched":
        data = json.loads(text)
        server = data.get("server")
        return cls(int(data["supervisor"]), int(data["launcher"]), int(data["port"]),
                   int(server) if server is not None else None, data.get("host", LOCALHOST))

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


@dataclass(frozen=True)
class InstanceFiles:
    """An instance's launch record, process log and default port."""
    pid: Path
    log: Path
    port: int

    @classmethod
    def of(cls, instance: Instance) -> "InstanceFiles":
        return cls(ARTIFACTS / f"srcds{instance.suffix}.pid", ARTIFACTS / f"srcds{instance.suffix}.log",
                   DEFAULT_PORT + INSTANCE_PORT_STEP * (instance.number - MAIN_INSTANCE))


def read_launched(pid_file: Path = PID_FILE) -> Optional[Launched]:
    return Launched.parse(pid_file.read_text()) if pid_file.exists() else None


LAUNCH_RECORD_TIMEOUT = 10
SERVER_PROCESS_TIMEOUT = 60


@dataclass(frozen=True)
class Server:
    install: Install
    config: ServerConfig
    host: str = LOCALHOST
    instance: Instance = MAIN

    @property
    def files(self) -> InstanceFiles:
        return InstanceFiles.of(self.instance)

    def start(self) -> None:
        server_root.build(Layout.of(self.instance))
        argv = command_line(self.install, self.config)  # refuses any bottle but Steam
        pid_file, log = self.files.pid, self.files.log
        launched = read_launched(pid_file)
        if launched and launched.alive(running_processes()):
            raise ServerDown(f"a server this tool started is still running on port {launched.port}; stop it first")
        if port_in_use(self.config.ip, self.config.port):
            raise ServerDown(f"port {self.config.port} is taken")
        ARTIFACTS.mkdir(parents=True, exist_ok=True)
        pid_file.unlink(missing_ok=True)
        before = set(_process_table(running_processes()))
        supervisor = [sys.executable, str(Path(__file__).resolve()), SUPERVISOR_MARK, str(log), str(pid_file),
                      str(self.config.port), "--"]
        subprocess.Popen(supervisor + argv, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)
        deadline = time.monotonic() + LAUNCH_RECORD_TIMEOUT
        while not pid_file.exists():
            if time.monotonic() > deadline:
                raise ServerDown("the supervisor did not record its launch")
            time.sleep(0.2)
        deadline = time.monotonic() + SERVER_PROCESS_TIMEOUT
        while time.monotonic() < deadline:
            server = new_server(read_launched(pid_file), before, running_processes())
            if server is not None:
                pid_file.write_text(dataclasses.replace(read_launched(pid_file), server=server).text())
                return
            time.sleep(0.5)
        raise ServerDown("no new server process appeared on the port; see " + str(log))

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
                raise ServerDown(f"the server exited before {name} loaded; see {self.files.log}")
            time.sleep(1)
        raise ServerDown(f"{name} was not up within {timeout:.0f} s")

    def alive(self) -> bool:
        launched = read_launched(self.files.pid)
        return bool(launched and launched.alive(running_processes()))

    def stop(self, timeout: float = 30) -> None:
        """Quit through RCON; whatever this tool launched that outlives that
        gets SIGTERM, by process id (stop_targets), and nothing else does."""
        launched = read_launched(self.files.pid)
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
        self.files.pid.unlink()


# The supervisor: owns the server's terminal ------------------------------------------


# Wine's console wraps its lines at the pty's width, 80 when the pty has none;
# this is wider than any line, so the terminal that shows the log wraps them
CONSOLE_COLUMNS = 400
CONSOLE_ROWS = 50


def console_pty() -> Tuple[int, int]:
    """A pty (master, slave) whose window is CONSOLE_COLUMNS wide."""
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", CONSOLE_ROWS, CONSOLE_COLUMNS, 0, 0))
    return master, slave


def supervise(log_path: Path, pid_file: Path, port: int, argv: List[str]) -> int:
    master, slave = console_pty()
    proc = subprocess.Popen(argv, stdin=slave, stdout=slave, stderr=slave)
    os.close(slave)
    host = argv[argv.index("+ip") + 1]
    pid_file.write_text(Launched(os.getpid(), proc.pid, port, host=host).text())
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


ITERM_PROFILE = "Dark"


def console_command(log: Path) -> str:
    """Follows the log from its first line, and across a restart that rewrites it."""
    return "tail -n +1 -F " + shlex.quote(str(log))


def applescript_string(text: str) -> str:
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def iterm_script(command: str) -> str:
    return (f'tell application "iTerm"\n'
            f'  create window with profile {applescript_string(ITERM_PROFILE)} command {applescript_string(command)}\n'
            f'  activate\n'
            f'end tell\n')


def open_console(log: Path) -> None:
    subprocess.run(["osascript", "-e", iterm_script(console_command(log))], check=True, capture_output=True)


def password() -> str:
    if not PASSWORD_FILE.exists():
        ARTIFACTS.mkdir(parents=True, exist_ok=True)
        PASSWORD_FILE.write_text(secrets.token_hex(12))
    return PASSWORD_FILE.read_text().strip()


def started_host(instance: Instance = MAIN) -> str:
    launched = read_launched(InstanceFiles.of(instance).pid)
    return launched.host if launched else LOCALHOST


def started_port(default: int, instance: Instance = MAIN) -> int:
    launched = read_launched(InstanceFiles.of(instance).pid)
    return launched.port if launched else default


DEFAULT_PORT = 27015  # beside the client's 27015, so the operator's own game keeps its port
INSTANCE_PORT_STEP = 10  # each further instance's default port, above the last
DEFAULT_MAXPLAYERS = 32
MAP_LOAD_TIMEOUT = 240


def rcon_command(instance: Instance, text: str, timeout: float = 10) -> str:
    """A console command on the instance's running server, and its reply."""
    port = started_port(InstanceFiles.of(instance).port, instance)
    return make_server("gm_construct", port, instance=instance).rcon(text, timeout)


def make_server(map_name: str, port: int, lua_refresh: bool = True, maxplayers: int = DEFAULT_MAXPLAYERS,
                ip: Optional[str] = None, instance: Instance = MAIN, p2p: bool = False) -> Server:
    """ip: the address to bind; by default the running server's (rcon, stop), else 127.0.0.1."""
    install = Install.discover(instance)
    ip = ip or started_host(instance)
    config = ServerConfig(map_name, port, password(), maxplayers, lua_refresh=lua_refresh, ip=ip, p2p=p2p)
    return Server(install, config, reach_address(ip), instance)


def main() -> int:
    if sys.argv[1:2] == [SUPERVISOR_MARK]:
        return supervise(Path(sys.argv[2]), Path(sys.argv[3]), int(sys.argv[4]), sys.argv[6:])
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--instance", type=int, default=MAIN_INSTANCE,
                    help="which server: 1, the main one, or another run beside it")
    sub = ap.add_subparsers(dest="action", required=True)
    start = sub.add_parser("start")
    start.add_argument("--map", default="gm_construct")
    start.add_argument("--port", type=int, help="by default the instance's (DEFAULT_PORT for the main one)")
    start.add_argument("--maxplayers", type=int, default=DEFAULT_MAXPLAYERS)
    start.add_argument("--ip", default=DEFAULT_BIND_HOST,
                       help="the address or name to bind (default %(default)s, every interface, the tailnet's among them); "
                            "127.0.0.1 keeps it to this Mac, which a client in the other bottle cannot reach")
    start.add_argument("--no-lua-refresh", dest="lua_refresh", action="store_false",
                       help="start with -disableluarefresh: edits on disk never reach the running server")
    start.add_argument("--console", action="store_true", help="follow the console in an iTerm window")
    start.add_argument("--p2p", action="store_true",
                       help="add -p2p and sv_lan 0, so Steam friends can join through Steam's relays")
    rcon = sub.add_parser("rcon")
    rcon.add_argument("command")
    sub.add_parser("stop")
    sub.add_parser("console")
    args = ap.parse_args()
    try:
        instance = Instance(args.instance)
        files = InstanceFiles.of(instance)
        if args.action == "start":
            port = args.port or files.port
            server = make_server(args.map, port, args.lua_refresh, args.maxplayers, bind_address(args.ip), instance,
                                 args.p2p)
            server.start()
            if args.console:
                open_console(files.log)
            server.wait_for_map(args.map, MAP_LOAD_TIMEOUT)
            print(f"{args.map} is up on port {port}")
        elif args.action == "rcon":
            print(rcon_command(instance, args.command))
        elif args.action == "console":
            open_console(files.log)
        else:
            make_server("gm_construct", started_port(files.port, instance), instance=instance).stop()
    except (ServerDown, AuthFailed, BindAddressUnknown, OSError, subprocess.CalledProcessError, ValueError) as e:
        print(f"srcds: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
