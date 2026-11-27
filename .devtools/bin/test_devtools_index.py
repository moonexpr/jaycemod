"""The folder's index (.devtools/README.md) is current, and every tool in it says
what it is: claude-config2's `dt devtools/index --check`. A tool added without a
docstring, first comment or dt-brief line, or a README left stale, fails here."""
import subprocess
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]


def test_the_index_is_current_and_every_tool_has_a_line():
    done = subprocess.run(["dt", "devtools/index", "--project", str(REPO), "--check"], capture_output=True, text=True)
    assert done.returncode == 0, done.stderr + "\nrun: dt devtools/index"
