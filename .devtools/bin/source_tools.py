"""Puts claude-config2's Source and GMod format readers on sys.path (its
app/sourcetools: bsp_entities, tf2_content, pe_rtti, elf_vtables, nav_convert...),
for this repo's tools that import them: import this module first. Found through
the dt drawer claude-config2 installs (~/.local/bin/devtools); SOURCE_TOOLS names
another folder. From a shell they are `dt source/<name>`.
"""
import os
import sys
from pathlib import Path

FOLDER = Path(os.environ.get("SOURCE_TOOLS") or Path.home() / ".local/bin/devtools/../../app/sourcetools").resolve()

if not (FOLDER / "bsp_entities.py").is_file():
    raise ImportError(f"claude-config2's source readers are not at {FOLDER}: install claude-config2, or set SOURCE_TOOLS")
if str(FOLDER) not in sys.path:
    sys.path.append(str(FOLDER))
