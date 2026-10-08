"""gev2_marker.py against a scratch git repository shaped like this one."""
import subprocess

import pytest

import gev2_marker
from gev2_marker import Markers, Refused

VIEW = b"-- the capture view\r\nlocal View = {}\r\nreturn View"  # CRLF and no final newline, kept exactly
LINE = 'WETSAND_T1_COMPILE = "sent-1234"'


def git(repo, *args):
    return subprocess.run(
        ["git", "-c", "user.name=t", "-c", "user.email=t@example.com", "-c", "commit.gpgsign=false",
         "-c", "core.autocrlf=false", *args],
        cwd=repo, check=True, capture_output=True, text=True).stdout


@pytest.fixture
def repo(tmp_path):
    root = tmp_path / "repo"
    (root / "addon" / "features" / "capture").mkdir(parents=True)
    (root / "addon" / "features" / "capture" / "cl.lua").write_bytes(VIEW)
    (root / "addon" / "wetsand").mkdir()
    (root / "addon" / "wetsand" / "cl_spectate.lua").write_text("local lastMode\n")
    (root / "docs").mkdir()
    (root / "docs" / "notes.lua").write_text("x = 1\n")
    git(root, "init", "-q")
    git(root, "add", "-A")
    git(root, "commit", "-qm", "files")
    return root


@pytest.fixture
def markers(tmp_path):
    return Markers(tmp_path / "artifacts" / "gev2_marker.json")


def view(repo):
    return repo / "addon" / "features" / "capture" / "cl.lua"


def clean(repo):
    return git(repo, "status", "--porcelain") == ""


def test_refuses_a_file_with_uncommitted_changes(repo, markers):
    view(repo).write_bytes(VIEW + b"\n-- the operator's edit\n")
    with pytest.raises(Refused, match="uncommitted"):
        markers.set(view(repo), LINE)
    assert view(repo).read_bytes() == VIEW + b"\n-- the operator's edit\n"
    assert markers.marked() == []


def test_refuses_a_file_outside_addon(repo, markers, tmp_path):
    with pytest.raises(Refused, match="addon"):
        markers.set(repo / "docs" / "notes.lua", "y = 2")
    outside = tmp_path / "loose.lua"
    outside.write_text("x = 1\n")
    with pytest.raises(Refused):
        markers.set(outside, "y = 2")
    assert (repo / "docs" / "notes.lua").read_text() == "x = 1\n"
    assert outside.read_text() == "x = 1\n"


def test_refuses_a_second_set_before_restore(repo, markers):
    markers.set(view(repo), LINE)
    marked = view(repo).read_bytes()
    with pytest.raises(Refused, match="restore"):
        markers.set(view(repo), 'WETSAND_T1_COMPILE = "disk-1234"')
    assert view(repo).read_bytes() == marked
    markers.restore()
    markers.set(view(repo), 'WETSAND_T1_COMPILE = "disk-1234"')  # a new marker after a restore is fine
    assert b'"disk-1234"' in view(repo).read_bytes()


def test_restore_puts_back_the_exact_bytes(repo, markers):
    markers.set(view(repo), LINE)
    assert view(repo).read_bytes() != VIEW
    assert markers.restore() == []
    assert view(repo).read_bytes() == VIEW
    assert clean(repo)
    assert markers.marked() == []


def test_restore_after_a_failed_run_leaves_the_file_clean(repo, markers):
    with pytest.raises(RuntimeError):
        with markers.marking(view(repo), LINE):
            assert LINE.encode() in view(repo).read_bytes()
            raise RuntimeError("the probe failed")
    assert view(repo).read_bytes() == VIEW
    assert clean(repo)
    assert not markers.state_file.exists()


def test_a_marker_keeps_a_file_that_ends_in_return_compiling(repo, markers):
    # Lua allows nothing after a chunk's final return, so the marker goes on
    # the first line, not the last.
    markers.set(view(repo), LINE)
    assert view(repo).read_bytes().splitlines()[0].startswith(LINE.encode())
    assert subprocess.run(["luajit", "-b", str(view(repo)), "/dev/null"]).returncode == 0


def test_refuses_a_line_that_would_not_compile(repo, markers):
    with pytest.raises(Refused, match="compile"):
        markers.set(view(repo), "this is not lua")
    with pytest.raises(Refused):
        markers.set(view(repo), "x = 1\ny = 2")  # one line only
    assert view(repo).read_bytes() == VIEW
    assert markers.marked() == []


def test_two_files_are_marked_and_restored_together(repo, markers):
    spectate = repo / "addon" / "wetsand" / "cl_spectate.lua"
    markers.set(spectate, 'WETSAND_T1_INCLUDE = "sent-1234"')
    markers.set(view(repo), LINE)
    assert sorted(markers.marked()) == sorted([str(spectate), str(view(repo))])
    assert markers.restore() == []
    assert clean(repo)


def test_restore_leaves_a_file_changed_since_alone(repo, markers):
    markers.set(view(repo), LINE)
    view(repo).write_bytes(b"-- rewritten by hand\n")
    problems = markers.restore()
    assert problems and "changed since" in problems[0]
    assert view(repo).read_bytes() == b"-- rewritten by hand\n"
    assert markers.marked() == [str(view(repo))]  # still listed, to restore by hand


def test_every_marker_line_carries_the_do_not_commit_tag(repo, markers):
    assert gev2_marker.TAG == "-- GEV2_MARKER_DO_NOT_COMMIT"
    spectate = repo / "addon" / "wetsand" / "cl_spectate.lua"
    markers.set(spectate, 'WETSAND_T1_INCLUDE = "sent-1234"')
    markers.set(view(repo), 'WETSAND_T2 = "save-1234" -- the save step')
    for path in (spectate, view(repo)):
        first = path.read_bytes().splitlines()[0].decode()
        assert first.endswith(" " + gev2_marker.TAG), first
        assert subprocess.run(["luajit", "-b", str(path), "/dev/null"]).returncode == 0
    # The probes still read the marker's value from the tagged line.
    assert 'WETSAND_T2 = "save-1234"' in view(repo).read_text().splitlines()[0]
    assert markers.restore() == []
    assert clean(repo)


def test_refuses_a_file_that_is_not_lua(repo, markers):
    cfg = repo / "addon" / "settings.cfg"
    cfg.write_text("sv_cheats 0\n")
    git(repo, "add", "-A")
    git(repo, "commit", "-qm", "cfg")
    with pytest.raises(Refused, match="Lua"):
        markers.set(cfg, "sv_cheats 1")
    assert cfg.read_text() == "sv_cheats 0\n"


def test_git_runs_without_optional_locks(repo, markers, monkeypatch):
    seen = []
    real_run = subprocess.run

    def run(argv, *args, **kwargs):
        if argv[0] == "git":
            seen.append(kwargs.get("env") or {})
        return real_run(argv, *args, **kwargs)

    monkeypatch.setattr(gev2_marker.subprocess, "run", run)
    markers.set(view(repo), LINE)
    assert seen and all(env.get("GIT_OPTIONAL_LOCKS") == "0" for env in seen)
    assert not (repo / ".git" / "index.lock").exists()
