#!/usr/bin/env python3
"""Run Garry's Mod's dedicated server under CrossOver and drive it with RCON.

  srcds.py start [--map gm_construct] [--port 27025]   start, wait for the map
  srcds.py rcon 'status'                               run a console command
  srcds.py stop                                        quit the server we started

The server is GMod's Windows x86-64 srcds_win64.exe in the bottle "Team
Fortress 2". It runs with -insecure -noworkshop -nosteam: without them it
crashes in steamclient64.dll while it mounts the Workshop, so Workshop addons
(DrGBase) never load on it. Its console must be a terminal: with a pipe or
/dev/null for stdin its main loop blocks in the console's GetLine before the
first frame, so a detached supervisor (this script's `_supervise`) gives it a
pty and drains it into .devtools/artifacts/srcds.log. -condebug writes
garrysmod/console.log, which holds what the console printed. +ip 127.0.0.1
keeps RCON on this machine.

The RCON password is kept in .devtools/artifacts/rcon_password, and the
started process's id in .devtools/artifacts/srcds.pid, so `stop` only ever
stops the server this tool started.
"""
from __future__ import annotations

import argparse
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
from typing import Deque, List, Optional, Tuple

__all__ = [
    "AUTH",
    "AUTH_RESPONSE",
    "EXECCOMMAND",
    "RESPONSE_VALUE",
    "AuthFailed",
    "Install",
    "Packet",
    "RconClient",
    "Server",
    "ServerConfig",
    "command_line",
    "decode_packets",
    "encode_packet",
    "map_from_status",
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

BOTTLE = "Team Fortress 2"
BOTTLE_DIR = Path.home() / "Library/Application Support/CrossOver/Bottles" / BOTTLE
GMOD_WINDOWS = r"C:\Steam\steamapps\common\GarrysMod"
GMOD_DIR = BOTTLE_DIR / "drive_c/Steam/steamapps/common/GarrysMod/garrysmod"
WINE_RELATIVE = "Contents/SharedSupport/CrossOver/bin/wine"
CROSSOVER_APPS = (Path("/Applications/CrossOver GPTK4.app"), Path("/Applications/CrossOver.app"))
SERVER_EXE = "srcds_win64.exe"
MAPS_ADDON = "wetsand_test_maps"
MAP_NAME = re.compile(r"^[A-Za-z0-9_\-]+$")
STATUS_MAP = re.compile(r"^map\s*:\s*(\S+)", re.MULTILINE)


class AuthFailed(Exception):
    pass


class ServerDown(Exception):
    pass


@dataclass(frozen=True)
class Install:
    wine: Path
    bottle: str
    gmod_windows: str
    gmod_dir: Path

    @classmethod
    def discover(cls, running: str) -> "Install":
        """The CrossOver whose wineserver is already running the bottle (its
        Steam), since a second CrossOver's wine refuses a running wineserver
        of another version; else the first installed."""
        installed = [app for app in CROSSOVER_APPS if (app / WINE_RELATIVE).exists()]
        if not installed:
            raise ServerDown("no CrossOver under /Applications")
        app = next((a for a in installed if f"{a}/" in running and "wineserver" in running), installed[0])
        return cls(app / WINE_RELATIVE, BOTTLE, GMOD_WINDOWS, GMOD_DIR)

    @property
    def console_log(self) -> Path:
        return self.gmod_dir / "console.log"

    @property
    def tf_maps(self) -> Path:
        return self.gmod_dir.parent.parent / "Team Fortress 2" / "tf" / "maps"

    @property
    def maps_addon(self) -> Path:
        return self.gmod_dir / "addons" / MAPS_ADDON

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

    def __post_init__(self):
        if not MAP_NAME.match(self.map):
            raise ValueError(f"not a map name: {self.map!r}")
        if not self.rcon_password or re.search(r"\s|\"", self.rcon_password):
            raise ValueError("the RCON password must be non-empty, without spaces or quotes")
        if self.maxplayers < MIN_SLOTS:
            raise ValueError(f"maxplayers {self.maxplayers}: bots need at least {MIN_SLOTS} slots")


def command_line(install: Install, config: ServerConfig) -> List[str]:
    convars = [
        ("ip", LOCALHOST),
        ("maxplayers", str(config.maxplayers)),
        ("gamemode", config.gamemode),
        ("rcon_password", config.rcon_password),
        ("sv_lan", "1"),
        ("sv_hibernate_think", "1"),
    ] + list(config.convars)
    argv = [
        str(install.wine), "--bottle", install.bottle, "--no-gui",
        "--workdir", install.gmod_windows,
        "--cx-app", install.gmod_windows + "\\" + SERVER_EXE,
        "-console", "-game", "garrysmod", "-port", str(config.port),
        "-insecure", "-noworkshop", "-nosteam", "-condebug", "-nohltv",
    ]
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
    return subprocess.run(["ps", "-axo", "pid=,command="], capture_output=True, text=True).stdout


def port_in_use(port: int) -> bool:
    with socket.socket() as s:
        s.settimeout(0.5)
        return s.connect_ex(("127.0.0.1", port)) == 0


def server_pids(port: int, processes: str) -> List[int]:
    """The srcds processes serving this port (the Windows process and the
    wine wrapper that started it), from `ps -axo pid=,command=`."""
    pids = []
    for line in processes.splitlines():
        pid, _, command = line.strip().partition(" ")
        if SERVER_EXE in command and f"-port {port} " in command + " ":
            pids.append(int(pid))
    return pids


@dataclass(frozen=True)
class Server:
    install: Install
    config: ServerConfig
    host: str = "127.0.0.1"

    def start(self) -> None:
        if port_in_use(self.config.port) or server_pids(self.config.port, running_processes()):
            raise ServerDown(f"port {self.config.port} is taken; is a server already running?")
        ARTIFACTS.mkdir(parents=True, exist_ok=True)
        link_maps(self.install.tf_maps, self.install.maps_addon)
        argv = [sys.executable, str(Path(__file__).resolve()), "_supervise", str(PROCESS_LOG), "--"]
        proc = subprocess.Popen(argv + command_line(self.install, self.config), stdin=subprocess.DEVNULL,
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        PID_FILE.write_text(f"{proc.pid} {self.config.port}\n")

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
        return bool(server_pids(self.config.port, running_processes()))

    def stop(self, timeout: float = 30) -> None:
        """Quit through RCON; if the process outlives that, signal only the
        processes serving our port, and only if this tool started one."""
        if not PID_FILE.exists():
            return
        try:
            self.rcon("quit", timeout=5)
        except (OSError, ServerDown, AuthFailed):
            pass
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline and self.alive():
            time.sleep(1)
        for pid in server_pids(self.config.port, running_processes()):
            os.kill(pid, signal.SIGTERM)
        unlink_maps(self.install.maps_addon)
        PID_FILE.unlink()


# TF2's maps, for the server ------------------------------------------------------------
# The client mounts TF2 through Steam; the dedicated server mounts only what
# cfg/mount.cfg lists (TF2's download folder here), so it finds no TF2 map.
# Rather than edit the operator's mount.cfg, the server gets an addon of its
# own holding a link to each TF2 .bsp (addons are search paths), removed on
# stop. TF2's models and materials already come from the VPKs gameinfo.txt
# lists. TF2's .nav files are left out: an addon comes before garrysmod/ in
# the search path, so one would shadow the converted mesh in garrysmod/maps.


def link_maps(tf_maps: Path, addon: Path) -> None:
    maps = addon / "maps"
    maps.mkdir(parents=True, exist_ok=True)
    for bsp in tf_maps.glob("*.bsp"):
        link = maps / bsp.name
        if not link.is_symlink():
            link.symlink_to(bsp)


def unlink_maps(addon: Path) -> None:
    maps = addon / "maps"
    if not addon.exists():
        return
    entries = list(maps.iterdir()) if maps.exists() else []
    if any(not e.is_symlink() for e in entries) or any(p != maps for p in addon.iterdir()):
        raise ValueError(f"{addon} holds more than map links; left alone")
    for link in entries:
        link.unlink()
    maps.rmdir()
    addon.rmdir()


# The supervisor: owns the server's terminal ------------------------------------------


def supervise(log_path: Path, argv: List[str]) -> int:
    master, slave = pty.openpty()
    proc = subprocess.Popen(argv, stdin=slave, stdout=slave, stderr=slave)
    os.close(slave)
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
    if PID_FILE.exists():
        return int(PID_FILE.read_text().split()[1])
    return default


DEFAULT_PORT = 27025  # beside the client's 27015, so the operator's own game keeps its port
DEFAULT_MAXPLAYERS = 32
MAP_LOAD_TIMEOUT = 240


def make_server(map_name: str, port: int) -> Server:
    install = Install.discover(running_processes())
    return Server(install, ServerConfig(map_name, port, password(), DEFAULT_MAXPLAYERS))


def main() -> int:
    if sys.argv[1:2] == ["_supervise"]:
        return supervise(Path(sys.argv[2]), sys.argv[4:])
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="action", required=True)
    start = sub.add_parser("start")
    start.add_argument("--map", default="gm_construct")
    start.add_argument("--port", type=int, default=DEFAULT_PORT)
    rcon = sub.add_parser("rcon")
    rcon.add_argument("command")
    sub.add_parser("stop")
    args = ap.parse_args()
    try:
        if args.action == "start":
            server = make_server(args.map, args.port)
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
