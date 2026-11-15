#!/usr/bin/env python3
r"""Compile vm_build's sources with GMod's studiomdl under CrossOver, then check the model against them.

  model_compile.py SWEP.lua [--sources DIR] [--studiomdl PATH] [--dry-run]

studiomdl.exe is GMod's own (GarrysMod\bin, or bin\win64 on the x86-64 branch: whichever is there),
run in the bottle "GModServer" as srcds.py runs the server, never in "Steam", where the operator
plays. Its game is a folder of our own (.devtools/artifacts/vm_build/game, a gameinfo.txt that mounts
nothing), so it writes nothing in the shared install; the files it writes are moved into
addons/tf_weapons/models/ (gitignored: TF2's content, reshaped), and vm_build.check_compiled holds the
model to its sources. A check that fails exits 1; the model is in the addon all the same, to look at.

Unverified here (no studiomdl in this container): that GMod ships studiomdl.exe at either path, that it
compiles against a gameinfo.txt with no search path but its own, and that $bonemerge reaches the
compiled flags; the check reads the last one back.
"""
from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path, PurePosixPath
from typing import List, Optional, Sequence

import srcds
import vm_build
from mdl_rig import DEFAULT_VPKS, Library

REPO = Path(__file__).resolve().parents[2]
GAME = vm_build.OUT / "game"
ADDON = REPO / "addons" / "tf_weapons"
GMOD = srcds.BOTTLE_DIR / "drive_c" / "Steam" / "steamapps" / "common" / "GarrysMod"
STUDIOMDL = (GMOD / "bin" / "studiomdl.exe", GMOD / "bin" / "win64" / "studiomdl.exe")
# what studiomdl writes for a model: the model, its vertices and its strips for each renderer
EXTENSIONS = (".mdl", ".vvd", ".dx90.vtx", ".dx80.vtx", ".sw.vtx", ".phy")
GAMEINFO = '''"GameInfo"
{
	game "tf_weapons build"
	FileSystem
	{
		SteamAppId 4000
		SearchPaths
		{
			game+mod |gameinfo_path|.
		}
	}
}
'''


class CompileError(Exception):
    pass


def windows_path(path: Path, drive_c: Path = srcds.BOTTLE_DIR / "drive_c") -> str:
    r"""A Mac path as the bottle's programs see it: under its drive_c, C:\; anywhere else Z:\, which is /."""
    p = PurePosixPath(path)
    if not p.is_absolute():
        raise CompileError(f"{path}: not absolute")
    try:
        return "C:\\" + str(p.relative_to(PurePosixPath(drive_c))).replace("/", "\\")
    except ValueError:
        return "Z:" + str(p).replace("/", "\\")


def command(wine: Path, studiomdl: Path, game: Path, qc: Path) -> List[str]:
    return [str(wine), "--bottle", srcds.BOTTLE, "--no-gui", "--no-update", "--cx-app", windows_path(studiomdl),
            "-game", windows_path(game), "-nop4", "-verbose", windows_path(qc)]


def outputs(game: Path, name: str) -> List[Path]:
    """The files studiomdl wrote for models/tf_weapons/<name>.mdl (those it wrote: .phy only with $collisionmodel)."""
    stem = game / "models" / "tf_weapons" / name
    return [stem.with_name(name + ext) for ext in EXTENSIONS if stem.with_name(name + ext).exists()]


def first_existing(paths: Sequence[Path]) -> Optional[Path]:
    return next((p for p in paths if p.exists()), None)


def main(argv: Sequence[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("swep", type=Path)
    ap.add_argument("--sources", type=Path, help="vm_build's folder for this weapon (default: built now)")
    ap.add_argument("--studiomdl", type=Path, help="studiomdl.exe, a Mac path inside the bottle")
    ap.add_argument("--vpk", type=Path, action="append")
    ap.add_argument("--dry-run", action="store_true", help="print the command and stop")
    a = ap.parse_args(argv)
    name = a.swep.stem.replace("tf_weapon_", "v_tf_")
    lib = Library(a.vpk or DEFAULT_VPKS)
    sources = a.sources or vm_build.build(lib, a.swep, vm_build.OUT)
    qc = sources / f"{name}.qc"
    if not qc.exists():
        raise CompileError(f"{qc}: no QC (run vm_build.py first)")
    wine = first_existing([app / srcds.WINE_RELATIVE for app in srcds.CROSSOVER_APPS])
    studiomdl = a.studiomdl or first_existing(STUDIOMDL)
    if wine is None:
        raise CompileError("no CrossOver: " + ", ".join(str(app) for app in srcds.CROSSOVER_APPS))
    if studiomdl is None:
        raise CompileError("no studiomdl.exe at " + ", ".join(map(str, STUDIOMDL)) + " (pass --studiomdl)")
    GAME.mkdir(parents=True, exist_ok=True)
    (GAME / "gameinfo.txt").write_text(GAMEINFO)
    argv_ = command(wine, studiomdl, GAME, qc)
    print(" ".join(argv_))
    if a.dry_run:
        return 0
    for old in outputs(GAME, name):
        old.unlink()
    done = subprocess.run(argv_, cwd=sources)
    written = outputs(GAME, name)
    if done.returncode != 0 or not any(p.suffix == ".mdl" for p in written):
        raise CompileError(f"studiomdl exited {done.returncode}, wrote {[p.name for p in written]}")
    target = ADDON / "models" / "tf_weapons"
    target.mkdir(parents=True, exist_ok=True)
    for p in written:
        shutil.copy2(p, target / p.name)
    rows = vm_build.check_compiled(Library(a.vpk or DEFAULT_VPKS, [ADDON]), sources, f"models/tf_weapons/{name}.mdl")
    for check, passed, detail in rows:
        print(f"  {'ok  ' if passed else 'FAIL'} {check}: {detail}")
    return 0 if all(p for _, p, _ in rows) else 1


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except CompileError as e:
        print(f"model_compile: {e}", file=sys.stderr)
        sys.exit(2)
