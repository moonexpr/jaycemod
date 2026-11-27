"""Puts the gmod plugin's tools on sys.path, for this repo's benches and probes
that import them (srcds, server_lua, server_root, instances, vpk...): import
this module first. The plugin lives in claude-config2 (plugins/gmod), found
through the dt drawer it installs (~/.local/bin/devtools); GMOD_PLUGIN names
another plugin folder.
"""
import os
import sys
from pathlib import Path

PLUGIN = Path(os.environ.get("GMOD_PLUGIN") or Path.home() / ".local/bin/devtools/../../plugins/gmod").resolve()
BIN = PLUGIN / "bin"

if not (BIN / "srcds.py").is_file():
    raise ImportError(f"the gmod plugin's tools are not at {BIN}: install claude-config2, or set GMOD_PLUGIN")
if str(BIN) not in sys.path:
    sys.path.append(str(BIN))
