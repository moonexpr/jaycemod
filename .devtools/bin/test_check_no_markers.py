"""check_no_markers.py against a scratch git repository shaped like this one."""
import subprocess
import sys
from pathlib import Path

import pytest

from gev2_marker import TAG

GUARD = Path(__file__).resolve().parent / "check_no_markers.py"
MARKER = f'WS_T2 = "save-1234" {TAG}\n'


def git(repo, *args):
    return subprocess.run(
        ["git", "-c", "user.name=t", "-c", "user.email=t@example.com", "-c", "commit.gpgsign=false", *args],
        cwd=repo, check=True, capture_output=True, text=True).stdout.strip()


def guard(repo, *args):
    return subprocess.run([sys.executable, str(GUARD), "--repo", str(repo), *args], capture_output=True, text=True)


@pytest.fixture
def repo(tmp_path):
    root = tmp_path / "repo"
    (root / "addons" / "sandcastle" /"features" / "capture").mkdir(parents=True)
    (root / "addons" / "sandcastle" /"features" / "capture" / "cl.lua").write_text("local View = {}\nreturn View\n")
    (root / "docs").mkdir()
    (root / "docs" / "notes.md").write_text("notes\n")
    git(root, "init", "-q")
    git(root, "add", "-A")
    git(root, "commit", "-qm", "files")
    return root


def view(repo):
    return repo / "addons" / "sandcastle" /"features" / "capture" / "cl.lua"


def test_a_staged_marker_line_fails(repo):
    assert guard(repo, "staged").returncode == 0
    view(repo).write_text(MARKER + view(repo).read_text())
    assert guard(repo, "staged").returncode == 0  # not staged yet
    git(repo, "add", "-A")
    result = guard(repo, "staged")
    assert result.returncode == 1
    assert "addons/sandcastle/features/capture/cl.lua" in result.stdout and TAG in result.stdout


def test_a_commit_in_the_range_with_a_marker_line_fails(repo):
    start = git(repo, "rev-parse", "HEAD")
    (repo / "docs" / "notes.md").write_text("notes\nmore\n")
    git(repo, "commit", "-qam", "clean work")
    assert guard(repo, "range", f"{start}..HEAD").returncode == 0
    view(repo).write_text(MARKER + view(repo).read_text())
    git(repo, "commit", "-qam", "the operator's commit swept up a marker")
    marked = git(repo, "rev-parse", "HEAD")
    view(repo).write_text("local View = {}\nreturn View\n")
    git(repo, "commit", "-qam", "removed again: the range still carried it")
    result = guard(repo, "range", f"{start}..HEAD")
    assert result.returncode == 1
    assert marked[:12] in result.stdout and "addons/sandcastle/features/capture/cl.lua" in result.stdout


def test_an_empty_range_passes(repo):
    assert guard(repo, "range", "HEAD..HEAD").returncode == 0


def test_the_tag_outside_addon_is_not_a_marker(repo):
    # Markers go only under addons/ (gev2_marker refuses anything else), so the
    # tools and docs that name the tag never trip the guard.
    start = git(repo, "rev-parse", "HEAD")
    (repo / "docs" / "notes.md").write_text(f"the tag is {TAG}\n")
    git(repo, "add", "-A")
    assert guard(repo, "staged").returncode == 0
    git(repo, "commit", "-qm", "docs")
    assert guard(repo, "range", f"{start}..HEAD").returncode == 0


def test_a_bad_range_is_an_error_not_a_pass(repo):
    result = guard(repo, "range", "no-such-commit..HEAD")
    assert result.returncode not in (0, 1)
