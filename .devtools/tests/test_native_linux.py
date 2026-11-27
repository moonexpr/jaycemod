"""native_linux.py: the repo's binary modules built for GMod's Linux server,
in a container on the server image's Ubuntu, where the server's root links
them from (gmod.toml). Nothing here runs docker: each command is checked as data."""
import subprocess

import native_linux
from native_linux import DOCKERFILE_DIR, IMAGE, LINUX_NATIVE_BINARIES, LINUX_TARGET, REPO, build_command, crates, \
    ensure_image


def test_every_win64_module_has_a_linux64_build_named_as_gmod_requires_it():
    from project import Project

    def module(name, suffix):
        return name.removeprefix("gmsv_").removesuffix(suffix)
    native = Project.load(REPO).native
    assert {module(name, "_win64.dll") for name in native["win64"]} <= \
        {module(name, "_linux64.dll") for name in native["linux64"]}
    for name, path in native["linux64"].items():
        assert name.endswith("_linux64.dll") and path.suffix == ".so" and LINUX_TARGET in path.parts, name


def test_every_crate_server_root_links_a_linux_build_of_is_built():
    assert crates() == [REPO / "native/ws_profile", REPO / "addons/foundation/native",
                        REPO / "addons/nextsoldier/native"]


def test_each_build_lands_where_server_root_links_it_from():
    for crate in crates():
        outputs = [path for path in LINUX_NATIVE_BINARIES.values() if path.is_relative_to(crate)]
        assert len(outputs) == 1, crate
        assert outputs[0].parent == crate / "target" / LINUX_TARGET / "release"


def test_the_profilers_library_is_named_for_its_crate():
    # cargo names a cdylib lib<name>.so after [package] name
    manifest = (REPO / "native/ws_profile/Cargo.toml").read_text()
    assert 'name = "wsprofile"' in manifest
    assert LINUX_NATIVE_BINARIES["gmsv_wsprofile_linux64.dll"].name == "libwsprofile.so"


def test_a_crate_is_built_for_linux_in_the_image_with_the_repo_at_its_own_path():
    crate = REPO / "addons/foundation/native"
    command = build_command(crate, 501, 20)
    assert command[:3] == ["docker", "run", "--rm"]
    assert command[command.index("-v") + 1] == f"{REPO}:{REPO}", "nextsoldier's crate reads foundation's by path"
    assert command[command.index("-w") + 1] == str(crate)
    assert command[command.index(IMAGE) + 1:] == ["cargo", "build", "--release", "--target", LINUX_TARGET]


def test_the_build_writes_as_the_operator_and_keeps_cargos_downloads_in_artifacts():
    command = build_command(REPO / "native/ws_profile", 501, 20)
    assert command[command.index("--user") + 1] == "501:20"
    assert f"CARGO_HOME={REPO / '.devtools/artifacts/docker/cargo'}" in command


def test_the_image_is_built_only_when_docker_lacks_it():
    calls = []

    def run(command, **kwargs):
        calls.append(command)
        return subprocess.CompletedProcess(command, 1 if command[1:3] == ["image", "inspect"] else 0)

    ensure_image(run)
    assert calls == [["docker", "image", "inspect", IMAGE], ["docker", "build", "-t", IMAGE, str(DOCKERFILE_DIR)]]


def test_the_dockerfile_is_where_the_image_is_built_from():
    assert (DOCKERFILE_DIR / "Dockerfile").is_file()


def test_the_builder_runs_the_server_images_ubuntu():
    builder = (DOCKERFILE_DIR / "Dockerfile").read_text()
    import gmod_plugin
    server = (gmod_plugin.PLUGIN / "docker/srcds/Dockerfile").read_text()
    assert "FROM ubuntu:22.04" in builder and "steamcmd/steamcmd:ubuntu-22" in server, \
        "a module built on a newer glibc than the server's may not load there"
