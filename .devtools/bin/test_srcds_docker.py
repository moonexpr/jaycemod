"""srcds_docker.py: the Linux server in a container. The host side composes
`docker run`; the container side installs GMod, builds the root and starts
the server. Nothing here runs docker or steamcmd: each is a command checked
as data, or a fake."""
import subprocess
from pathlib import Path

import pytest

import srcds_docker
from server_root import LINUX, LINUX_RUN, Instance
from srcds_docker import (
    CONTAINER_GMOD,
    CONTAINER_ROOT,
    DOCKERFILE_DIR,
    GMOD_VOLUME,
    IMAGE,
    STEAMCMD_VOLUME,
    HostPaths,
    container_layout,
    container_name,
    enter,
    ensure_image,
    install_command,
    mount_cfg,
    root_volume,
    run_argv,
    server_command,
    stop_command,
)

PATHS = HostPaths(
    repo=Path("/Users/op/jaycemod"),
    workshop=Path("/Users/op/Steam/workshop/content/4000"),
    maps=Path("/Users/op/steamcmd/workshop/content/4000"),
    tf=Path("/Users/op/Team Fortress 2/tf"),
)
SERVER_ARGS = ["-console", "-game", "garrysmod", "-port", "27025", "+ip", "0.0.0.0", "+map", "gm_construct"]


def argv(instance=Instance(1), host="0.0.0.0", port=27025, paths=PATHS):
    return run_argv(instance, host, port, SERVER_ARGS, paths)


def values(args, flag):
    return [args[i + 1] for i, a in enumerate(args) if a == flag]


def test_runs_one_named_container_per_instance_removed_when_it_stops():
    args = argv()
    assert args[:2] == ["docker", "run"]
    assert "--rm" in args
    assert values(args, "--name") == [container_name(Instance(1))]
    assert container_name(Instance(1)) != container_name(Instance(2))


# The supervisor gives docker a pty, as it gave wine one: the console is a
# terminal inside the container too, and the log holds it.
def test_the_console_is_a_terminal():
    args = argv()
    assert "-i" in args and "-t" in args


def test_the_game_port_is_published_at_the_bound_address_for_udp_and_rcons_tcp():
    published = values(argv(host="100.64.0.7"), "-p")
    assert "100.64.0.7:27025:27025/udp" in published
    assert "100.64.0.7:27025:27025/tcp" in published


def test_luadevs_socket_is_published_on_this_machine_only():
    for number in (1, 2):
        instance = Instance(number)
        port = instance.luadev_port
        assert f"127.0.0.1:{port}:{port}/tcp" in values(argv(instance), "-p")
        assert not any(p.endswith(f":{port}/udp") or p.startswith(f"0.0.0.0:{port}") for p in values(argv(instance), "-p"))


def test_gmod_is_installed_once_for_every_instance_and_each_root_is_its_own():
    volumes = values(argv(), "-v")
    assert f"{GMOD_VOLUME}:{CONTAINER_GMOD}" in volumes
    assert f"{STEAMCMD_VOLUME}:{srcds_docker.CONTAINER_STEAMCMD}" in volumes
    assert f"{root_volume(Instance(1))}:{CONTAINER_ROOT}" in volumes
    assert f"{root_volume(Instance(2))}:{CONTAINER_ROOT}" in values(argv(Instance(2)), "-v")
    assert root_volume(Instance(1)) != root_volume(Instance(2))


# The root's links point into the repo and the downloads by their host paths,
# so the container mounts each at the same path: the links resolve there too.
def test_the_repo_and_the_downloads_are_mounted_where_they_are_on_the_host():
    volumes = values(argv(), "-v")
    assert f"{PATHS.repo}:{PATHS.repo}" in volumes, "the server writes the repo's data (scenarios)"
    for path in (PATHS.workshop, PATHS.maps.parent, PATHS.tf):
        assert f"{path}:{path}:ro" in volumes, path


def test_a_gamemode_override_is_mounted_and_named_to_the_build():
    override = Path("/Users/op/worktree/addons/sandcastle/gamemodes/sandcastle")
    args = argv(paths=HostPaths(PATHS.repo, PATHS.workshop, PATHS.maps, PATHS.tf, override))
    assert f"{override}:{override}:ro" in values(args, "-v")
    assert values(args, "--gamemode") == [str(override)]
    assert "--gamemode" not in argv()


def test_the_container_runs_this_module_then_the_servers_arguments():
    args = argv(Instance(2))
    at = args.index(IMAGE)
    assert args[at + 1:at + 3] == ["python3", str(PATHS.repo / ".devtools/bin/srcds_docker.py")]
    assert args[args.index("--") + 1:] == SERVER_ARGS
    entry = args[at + 3:args.index("--")]
    assert values(entry, "--instance") == ["2"]
    assert HostPaths.parse(entry) == PATHS


def test_host_paths_round_trip_through_the_containers_arguments():
    override = HostPaths(PATHS.repo, PATHS.workshop, PATHS.maps, PATHS.tf, Path("/w/sandcastle"))
    for paths in (PATHS, override):
        assert HostPaths.parse(paths.argv()) == paths


def test_the_image_is_built_only_when_docker_lacks_it():
    calls = []

    def run(command, **kwargs):
        calls.append(command)
        return subprocess.CompletedProcess(command, 1 if command[1:3] == ["image", "inspect"] else 0)

    ensure_image(run)
    assert calls == [["docker", "image", "inspect", IMAGE], ["docker", "build", "-t", IMAGE, str(DOCKERFILE_DIR)]]
    calls.clear()
    ensure_image(lambda command, **kwargs: calls.append(command) or subprocess.CompletedProcess(command, 0))
    assert calls == [["docker", "image", "inspect", IMAGE]]


def test_the_dockerfile_is_where_the_image_is_built_from():
    assert (DOCKERFILE_DIR / "Dockerfile").is_file()


def test_stopping_names_only_the_instances_container():
    assert stop_command(Instance(2)) == ["docker", "stop", "--time", str(srcds_docker.STOP_GRACE), container_name(Instance(2))]


# The container side --------------------------------------------------------------------


def test_gmod_is_the_64_bit_dedicated_server_installed_into_its_volume():
    command = install_command()
    assert command[0] == "steamcmd"
    assert values(command, "+force_install_dir") == [str(CONTAINER_GMOD)]
    assert command[command.index("+app_update") + 1:command.index("+app_update") + 4] == ["4020", "-beta", "x86-64"]
    assert command[-1] == "+quit"
    assert command.index("+force_install_dir") < command.index("+login"), "steamcmd wants the folder first"


def test_tf2_is_mounted_from_the_operators_install():
    text = mount_cfg(PATHS.tf)
    assert '"tf"' in text and f'"{PATHS.tf}"' in text


def test_the_containers_layout_is_the_linux_servers_on_the_mounted_paths():
    layout = container_layout(Instance(2), PATHS, added_maps={"gm_x": "1"})
    assert layout.platform is LINUX
    assert (layout.shared, layout.root) == (CONTAINER_GMOD, CONTAINER_ROOT)
    assert (layout.workshop, layout.maps, layout.tf) == (PATHS.workshop, PATHS.maps, PATHS.tf)
    assert layout.luadev_port == Instance(2).luadev_port
    assert layout.luadev_host == "0.0.0.0"
    assert layout.lua == PATHS.repo / ".devtools/bin/server_root"
    assert layout.added_maps == {"gm_x": "1"}


def test_the_server_starts_from_the_root_without_restarting_itself():
    command = server_command(SERVER_ARGS)
    assert command[0] == str(CONTAINER_ROOT / LINUX_RUN)
    assert command[1:] == ["-norestart"] + SERVER_ARGS
    assert values(argv(), "--workdir") == [str(CONTAINER_ROOT)]


class Container:
    """A fake container: what enter runs, writes, builds and execs, in order."""

    def __init__(self, tmp_path, install_fails=False):
        self.steps, self.cfg = [], tmp_path / "mount.cfg"
        self.install_fails = install_fails

    def run(self, command, check):
        self.steps.append(("run", command[0]))
        if self.install_fails and check:
            raise subprocess.CalledProcessError(8, command)

    def build(self, layout):
        self.steps.append(("build", layout.root))

    def execv(self, program, args):
        self.steps.append(("exec", program, tuple(args)))


def test_entering_installs_mounts_tf2_builds_the_root_and_becomes_the_server(tmp_path):
    box = Container(tmp_path)
    enter(Instance(1), PATHS, SERVER_ARGS, run=box.run, build=box.build, execv=box.execv, mount_cfg_path=box.cfg)
    command = server_command(SERVER_ARGS)
    assert box.steps == [("run", "steamcmd"), ("build", CONTAINER_ROOT), ("exec", command[0], tuple(command))]
    assert box.cfg.read_text() == mount_cfg(PATHS.tf)


def test_a_failed_install_starts_nothing(tmp_path):
    box = Container(tmp_path, install_fails=True)
    with pytest.raises(subprocess.CalledProcessError):
        enter(Instance(1), PATHS, SERVER_ARGS, run=box.run, build=box.build, execv=box.execv, mount_cfg_path=box.cfg)
    assert box.steps == [("run", "steamcmd")]
