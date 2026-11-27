"""The tools these tests cover live flat in bin/ and its folders (rooms/, check/) and import each
other by name; the tests import them the same way."""
import sys
from pathlib import Path

BIN = Path(__file__).resolve().parents[1] / "bin"
for folder in (BIN, BIN / "rooms", BIN / "check"):
    sys.path.insert(0, str(folder))
