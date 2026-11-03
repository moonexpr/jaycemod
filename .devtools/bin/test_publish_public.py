import shutil
import subprocess
from pathlib import Path

SCRIPT = Path(__file__).with_name("publish_public.sh")

KEPT = "addons/sandcastle/init.lua"
EXCLUDED = [
    "native/vendor/source-sdk-2013/nav.h",
    "addons/sandcastle/gamemodes/sandcastle/gamemode/vendor/jazztronauts/lib.lua",
    "addons/sandcastle/gamemodes/sandcastle/content/sound/npc/combine_soldier/die1.wav",
    "addons/sandcastle/materials/hud/vip_car.vtf",
    "addons/sandcastle/materials/hud/vip_car.vmt",
]


def git(cwd: Path, *args: str) -> str:
    return subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True, text=True).stdout


def commit(repo: Path, files: list[str], message: str) -> None:
    for name in files:
        path = repo / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(message + name)
    git(repo, "add", "-A")
    git(repo, "-c", "user.name=T", "-c", "user.email=t@example.com", "commit", "--no-gpg-sign", "-qm", message)


def project(tmp_path: Path) -> tuple[Path, Path]:
    repo = tmp_path / "repo"
    repo.mkdir()
    git(repo, "init", "-q", "-b", "main")
    (repo / ".devtools/bin").mkdir(parents=True)
    shutil.copy(SCRIPT, repo / ".devtools/bin/publish_public.sh")
    commit(repo, [KEPT, *EXCLUDED], "first")
    remote = tmp_path / "remote.git"
    git(tmp_path, "init", "-q", "--bare", str(remote))
    return repo, remote


def publish(repo: Path, remote: Path) -> None:
    subprocess.run(["sh", str(repo / ".devtools/bin/publish_public.sh"), str(remote)], check=True, capture_output=True)


def test_published_history_holds_none_of_the_excluded_paths(tmp_path):
    repo, remote = project(tmp_path)
    publish(repo, remote)
    paths = set(git(remote, "log", "main", "--name-only", "--format=").split())
    assert KEPT in paths
    assert paths.isdisjoint(EXCLUDED)


def test_published_history_names_no_assistant(tmp_path):
    repo, remote = project(tmp_path)
    (repo / "b.lua").write_text("b")
    git(repo, "add", "-A")
    message = ("Work\n\nThe body stays, CLAUDE.md and all.\n\n"
               "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>\n"
               "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>\n"
               "Claude-Session: https://claude.ai/code/session_01abc\n")
    git(repo, "-c", "user.name=Claude", "-c", "user.email=noreply@anthropic.com",
        "commit", "--no-gpg-sign", "-qm", message)
    publish(repo, remote)
    log = git(remote, "log", "main", "--format=%an <%ae>|%cn <%ce>|%B")
    assert "anthropic" not in log and "Copilot" not in log and "Claude-Session" not in log
    assert git(remote, "log", "-1", "main", "--format=%an <%ae>").strip() == "John Chandara <john.chandara@icloud.com>"
    assert "The body stays, CLAUDE.md and all." in log


def test_a_later_publish_fast_forwards_the_one_before(tmp_path):
    repo, remote = project(tmp_path)
    publish(repo, remote)
    before = git(remote, "rev-parse", "main").strip()
    commit(repo, ["addons/sandcastle/later.lua"], "second")
    publish(repo, remote)
    git(remote, "merge-base", "--is-ancestor", before, "main")
    assert git(remote, "rev-list", "--count", "main").strip() == "2"
