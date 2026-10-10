"""strip_attribution.py: messages lose their Claude attribution, and a
history rewritten through it keeps every tree, parent shape and author."""
import subprocess
from pathlib import Path

from strip_attribution import Git, rewrite, stripped


def test_a_message_loses_its_co_author_and_session_lines():
    message = ("Fix the cart\n\nWhy it moved.\n\n"
               "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>\n"
               "Claude-Session: https://claude.ai/code/session_01ABC\n")
    assert stripped(message) == "Fix the cart\n\nWhy it moved.\n"


def test_a_generated_with_footer_goes_too():
    message = ("Add x\n\n🤖 Generated with [Claude Code](https://claude.com/claude-code)\n\n"
               "https://claude.ai/code/session_01ABC\n")
    assert stripped(message) == "Add x\n"


def test_a_message_without_attribution_is_unchanged():
    assert stripped("Add x\n\nCo-authored by the map's I/O.\n") == "Add x\n\nCo-authored by the map's I/O.\n"


def git(repo: Path, *args: str) -> str:
    return subprocess.run(["git", "-C", str(repo), *args], check=True, capture_output=True, text=True).stdout.strip()


def commit(repo: Path, name: str, message: str) -> None:
    (repo / name).write_text(name)
    git(repo, "add", name)
    git(repo, "commit", "-q", "--no-gpg-sign", "-m", message)


def test_a_rewrite_keeps_trees_merges_and_authors_and_drops_attribution(tmp_path):
    repo = tmp_path / "r"
    repo.mkdir()
    git(repo, "init", "-q", "-b", "main")
    git(repo, "config", "user.name", "Op")
    git(repo, "config", "user.email", "op@example.com")
    commit(repo, "a", "base")
    commit(repo, "b", "two\n\nCo-Authored-By: Claude <noreply@anthropic.com>")
    git(repo, "checkout", "-q", "-b", "side", "HEAD~1")
    commit(repo, "c", "side")
    git(repo, "checkout", "-q", "main")
    git(repo, "merge", "-q", "--no-gpg-sign", "--no-edit", "side")
    commit(repo, "d", "four\n\nClaude-Session: https://claude.ai/code/session_1")
    before = git(repo, "rev-parse", "main")

    after = rewrite(Git(repo, sign=False), git(repo, "rev-parse", "main~2"), before)

    assert git(repo, "rev-parse", f"{after}^{{tree}}") == git(repo, "rev-parse", f"{before}^{{tree}}")
    assert git(repo, "log", "--format=%B", after).count("Claude") == 0
    assert git(repo, "rev-list", "--merges", "--count", after) == "1"
    assert git(repo, "log", "--format=%an %ae %ad", before) == git(repo, "log", "--format=%an %ae %ad", after)
    assert git(repo, "rev-parse", f"{after}~3") == git(repo, "rev-parse", f"{before}~3")  # base untouched
