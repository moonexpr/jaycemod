"""check_totals.sh over a scratch repository whose check_lua.sh prints the
total kept in a file, so each commit's total is whatever that commit says."""
import shutil
import subprocess
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "check_totals.sh"

FAKE_CHECK_LUA = """#!/bin/sh
cd "$(dirname "$0")/../.." || exit 2
read passed failed < counts
echo "compiled 1 files"
echo "TOTAL $passed passed, $failed failed"
[ "$failed" -eq 0 ]
"""


def git(repo, *args):
    return subprocess.run(
        ["git", "-c", "user.name=t", "-c", "user.email=t@example.com", "-c", "commit.gpgsign=false", *args],
        cwd=repo, check=True, capture_output=True, text=True).stdout


def commit(repo, counts, subject):
    (repo / "counts").write_text(counts + "\n")
    git(repo, "add", "-A")
    git(repo, "commit", "-q", "--allow-empty", "-m", subject)
    return git(repo, "rev-parse", "--short", "HEAD").strip()


def scratch_repo(tmp_path):
    repo = tmp_path / "repo"
    bin_dir = repo / ".devtools" / "bin"
    bin_dir.mkdir(parents=True)
    shutil.copy(SCRIPT, bin_dir / "check_totals.sh")
    (bin_dir / "check_lua.sh").write_text(FAKE_CHECK_LUA)
    (bin_dir / "check_lua.sh").chmod(0o755)
    git(repo, "init", "-q", "-b", "main")
    commit(repo, "5 0", "the base")
    git(repo, "checkout", "-qb", "work")
    return repo


def run(repo):
    return subprocess.run([str(repo / ".devtools" / "bin" / "check_totals.sh"), "main"],
                          cwd=repo, capture_output=True, text=True)


def test_passes_while_no_commit_drops_its_parents_total(tmp_path):
    repo = scratch_repo(tmp_path)
    first = commit(repo, "6 0", "add a test")
    second = commit(repo, "6 0", "change no test")
    result = run(repo)
    assert result.returncode == 0, result.stdout + result.stderr
    lines = result.stdout.splitlines()
    assert f"{first} 6 add a test" in lines
    assert f"{second} 6 change no test" in lines


def test_fails_when_a_commit_drops_below_its_parent(tmp_path):
    repo = scratch_repo(tmp_path)
    commit(repo, "7 0", "add two tests")
    dropped = commit(repo, "6 0", "lose a test")
    result = run(repo)
    assert result.returncode == 1
    assert any(line.startswith(f"{dropped} 6 lose a test") and "below its parent's 7" in line
               for line in result.stdout.splitlines()), result.stdout


def test_fails_when_a_commits_lua_check_fails(tmp_path):
    repo = scratch_repo(tmp_path)
    failing = commit(repo, "6 1", "break a test")
    result = run(repo)
    assert result.returncode == 1
    assert any(line.startswith(f"{failing} 6 break a test") and "check_lua.sh failed" in line
               for line in result.stdout.splitlines()), result.stdout


def test_judges_each_commits_own_tree_not_the_working_copy(tmp_path):
    repo = scratch_repo(tmp_path)
    commit(repo, "6 0", "add a test")
    (repo / "counts").write_text("1 0\n")  # uncommitted, and lower
    assert run(repo).returncode == 0
