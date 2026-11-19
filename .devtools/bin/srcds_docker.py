#!/usr/bin/env python3
r"""The dedicated server on Linux, in a container: srcds.py --runtime docker.

  srcds.py --runtime docker start [...]      the same start, rcon, stop and console as under CrossOver

The image (DOCKERFILE_DIR, built the first time it is missing) is steamcmd's
on Ubuntu with Python. Each start runs one container per instance
(container_name), attached under srcds.py's supervisor, whose pty the
server's console writes to. In it, this module (enter):

1. installs or updates GMod's dedicated server, the x86-64 branch, into the
   volume GMOD_VOLUME (shared by every instance; steamcmd's own state is
   STEAMCMD_VOLUME), so a start after the first only checks for an update;
2. mounts TF2 from the operator's install (mount.cfg);
3. builds the server root with server_root.py's LINUX platform into the
   instance's own volume (root_volume): the same links as under CrossOver,
   to the repo, the Workshop downloads and TF2, each mounted at its host
   path so the links resolve in the container as they do on the host; the
   repo's binary modules are their linux64 builds (native_linux.sh);
   With --holylib, the root links HolyLib's plugin (holylib.py fetches it),
   and without, any link a run with it left is taken away;
4. becomes the server (srcds_run_x64 -norestart).

The game port is published at the address srcds.py binds (UDP, and TCP for
RCON); luadev's socket on 127.0.0.1 only, as under CrossOver, though inside
the container it listens on every interface (LUADEV_HOST_FILE).
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, List, Mapping, Optional

import server_root
from server_root import LINUX, LINUX_RUN, MAIN_INSTANCE, Instance, Layout

REPO = Path(__file__).resolve().parents[2]
DOCKERFILE_DIR = REPO / ".devtools" / "docker" / "srcds"
IMAGE = "sandcastle-srcds:1"  # its tag goes up with every change to the Dockerfile
CONTAINER_PREFIX = "sandcastle-srcds"
GMOD_VOLUME = "sandcastle-srcds-gmod"
STEAMCMD_VOLUME = "sandcastle-srcds-steamcmd"
CONTAINER_GMOD = Path("/srv/gmod")
CONTAINER_ROOT = Path("/srv/root")
CONTAINER_STEAMCMD = Path("/root/.local/share/Steam")
ALL_INTERFACES = "0.0.0.0"
LOCALHOST = "127.0.0.1"
GMOD_APP, GMOD_BRANCH = "4020", "x86-64"  # the 64-bit build, which the repo's modules are built for
STOP_GRACE = 10  # seconds docker stop gives the server before it kills it
ENTRY = Path(".devtools") / "bin" / "srcds_docker.py"
HOLYLIB_FLAG = "--holylib"  # the entry's: build the root with HolyLib's plugin


def container_name(instance: Instance) -> str:
    return CONTAINER_PREFIX + instance.suffix


def root_volume(instance: Instance) -> str:
    """The instance's server root: its data/ and cache/ outlive the container."""
    return f"{CONTAINER_PREFIX}-root{instance.suffix}"


@dataclass(frozen=True)
class HostPaths:
    """The host's folders a container mounts at the same path: the repo, the
    operator's Workshop downloads, steamcmd's (whose parent holds the packs of
    other apps), TF2's tf/, and a worktree's gamemode when one is run."""
    repo: Path
    workshop: Path
    maps: Path
    tf: Path
    gamemode: Optional[Path] = None

    @classmethod
    def of_host(cls, environ: Mapping[str, str] = os.environ) -> "HostPaths":
        override = environ.get(server_root.GAMEMODE_ENV)
        return cls(REPO, server_root.WORKSHOP, server_root.STEAMCMD_WORKSHOP, server_root.TF,
                   Path(override) if override else None)

    def argv(self) -> List[str]:
        args = ["--repo", str(self.repo), "--workshop", str(self.workshop), "--maps", str(self.maps),
                "--tf", str(self.tf)]
        return args + (["--gamemode", str(self.gamemode)] if self.gamemode else [])

    @classmethod
    def parse(cls, args: List[str]) -> "HostPaths":
        ap = argparse.ArgumentParser(add_help=False)
        for name in ("--repo", "--workshop", "--maps", "--tf"):
            ap.add_argument(name, type=Path, required=True)
        ap.add_argument("--gamemode", type=Path)
        known, _ = ap.parse_known_args(args)
        return cls(known.repo, known.workshop, known.maps, known.tf, known.gamemode)

    def mounts(self) -> List[str]:
        """docker -v values: the repo read-write (the server writes its data
        there, the scenarios), the rest read-only."""
        read_only = [self.workshop, self.maps.parent, self.tf] + ([self.gamemode] if self.gamemode else [])
        return [f"{self.repo}:{self.repo}"] + [f"{path}:{path}:ro" for path in read_only]


def run_argv(instance: Instance, host: str, port: int, server_args: List[str], paths: HostPaths,
             holylib: bool = False) -> List[str]:
    """`docker run` for the instance's container, bound at `host`, running
    srcds with `server_args` (which bind +ip 0.0.0.0: the container's own
    interface, which the published ports reach); `holylib`, its root built
    with HolyLib's plugin (server_root.py's LINUX_HOLYLIB)."""
    luadev = instance.luadev_port
    args = ["docker", "run", "--rm", "-i", "-t", "--init", "--name", container_name(instance),
            "--workdir", str(CONTAINER_ROOT),
            "-p", f"{host}:{port}:{port}/udp", "-p", f"{host}:{port}:{port}/tcp",
            "-p", f"{LOCALHOST}:{luadev}:{luadev}/tcp",
            "-v", f"{GMOD_VOLUME}:{CONTAINER_GMOD}", "-v", f"{STEAMCMD_VOLUME}:{CONTAINER_STEAMCMD}",
            "-v", f"{root_volume(instance)}:{CONTAINER_ROOT}"]
    for mount in paths.mounts():
        args += ["-v", mount]
    entry = ["python3", str(paths.repo / ENTRY), "--instance", str(instance.number)] + paths.argv()
    if holylib:
        entry.append(HOLYLIB_FLAG)
    return args + [IMAGE] + entry + ["--"] + server_args


def stop_command(instance: Instance) -> List[str]:
    return ["docker", "stop", "--time", str(STOP_GRACE), container_name(instance)]


Run = Callable[..., subprocess.CompletedProcess]


def ensure_image(run: Run = subprocess.run) -> None:
    """Builds IMAGE from DOCKERFILE_DIR when docker does not have it."""
    inspected = run(["docker", "image", "inspect", IMAGE], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if inspected.returncode != 0:
        run(["docker", "build", "-t", IMAGE, str(DOCKERFILE_DIR)], check=True)


# In the container ------------------------------------------------------------------------


def install_command() -> List[str]:
    return ["steamcmd", "+force_install_dir", str(CONTAINER_GMOD), "+login", "anonymous",
            "+app_update", GMOD_APP, "-beta", GMOD_BRANCH, "+quit"]


def mount_cfg(tf: Path) -> str:
    """GMod's mount.cfg: TF2's content from the operator's install."""
    return f'"mountcfg"\n{{\n\t"tf"\t"{tf}"\n}}\n'


MOUNT_CFG = CONTAINER_GMOD / "garrysmod" / "cfg" / "mount.cfg"


def container_layout(instance: Instance, paths: HostPaths, added_maps: Mapping[str, str],
                     holylib: bool = False) -> Layout:
    return Layout(CONTAINER_GMOD, CONTAINER_ROOT, paths.workshop, paths.repo / ".devtools" / "bin" / "server_root",
                  paths.tf, instance.luadev_port, paths.maps, paths.gamemode, added_maps, LINUX, ALL_INTERFACES,
                  holylib)


def server_command(server_args: List[str]) -> List[str]:
    return [str(CONTAINER_ROOT / LINUX_RUN), "-norestart"] + server_args


def enter(instance: Instance, paths: HostPaths, server_args: List[str], run: Run = subprocess.run,
          build: Callable[[Layout], Path] = server_root.build, execv: Callable = os.execv,
          mount_cfg_path: Path = MOUNT_CFG, holylib: bool = False) -> None:
    """Install, mount TF2, build the root (with HolyLib's plugin, or without), become the server."""
    run(install_command(), check=True)
    mount_cfg_path.write_text(mount_cfg(paths.tf))
    added = server_root.read_added_maps(paths.repo / ".devtools" / "artifacts" / "added_maps.json")
    build(container_layout(instance, paths, added, holylib))
    command = server_command(server_args)
    execv(command[0], command)


def main() -> int:
    args = sys.argv[1:]
    split = args.index("--")
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--instance", type=int, default=MAIN_INSTANCE)
    ap.add_argument(HOLYLIB_FLAG, action="store_true")
    known, _ = ap.parse_known_args(args[:split])
    enter(Instance(known.instance), HostPaths.parse(args[:split]), args[split + 1:], holylib=known.holylib)
    return 0


if __name__ == "__main__":
    sys.exit(main())
