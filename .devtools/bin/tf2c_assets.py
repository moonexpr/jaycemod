#!/usr/bin/env python3
"""Copy the few files Sandcastle takes from TF2 Classified into the addon.

The hostage HUD is TF2 Classified's VIP HUD (resource/ui/hudobjectivevip.res):
its track, home, getaway car and the Civilian's marker. Their materials are
TF2 Classified's own, so they ship in the addon (addons/sandcastle/materials),
copied from its paks by this tool; run it again after a TF2 Classified update.
Its announcer's VIP lines are TF2's own files, mounted already, and need
nothing here.

    python3 .devtools/bin/tf2c_assets.py [--tf2c PATH]

PATH is TF2 Classified's game folder (the one holding vpks/), by default the
dedicated server steamcmd downloads (app 3557020).
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from vpk import Vpk

REPO = Path(__file__).resolve().parents[2]
ADDON = REPO / "addons" / "sandcastle"
DEFAULT_TF2C = Path.home() / "Library/Application Support/Steam/steamapps/common/tf2classified-server/tf2classified"

ASSETS = [
    f"materials/hud/{stem}.{ext}"
    for stem in ("vip_track", "vip_home", "vip_car", "vip_civ", "vip_civ_bottom")
    for ext in ("vmt", "vtf")
]


class MissingAsset(Exception):
    pass


def extract(paks, wanted, dest: Path) -> list[Path]:
    """Each of wanted (pak paths) from the first of paks holding it, written
    under dest at the same path. Returns the paths written, in order."""
    index = {}
    for pak in paks:
        for name in pak.names():
            index.setdefault(name, pak)
    written = []
    for path in wanted:
        pak = index.get(path)
        if pak is None:
            raise MissingAsset(f"no TF2 Classified pak has {path}")
        out = dest / path
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_bytes(pak.read(path))
        written.append(out)
    return written


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--tf2c", type=Path, default=DEFAULT_TF2C)
    args = ap.parse_args()
    paks = [Vpk.open(d) for d in sorted((args.tf2c / "vpks").glob("*_dir.vpk"))]
    for path in extract(paks, ASSETS, ADDON):
        print(path.relative_to(REPO))
    return 0


if __name__ == "__main__":
    sys.exit(main())
