#!/usr/bin/env python3
"""Extract the TF2 models a dedicated GMod server needs, for the in-game harness.

  tf2_server_content.py MAP...      write .devtools/artifacts/tf2-server-content/

GMod's dedicated server mounts only what cfg/mount.cfg lists, and the
operator's lists only TF2's download folder; it ignores the TF2 VPKs that
gameinfo.txt names (GMod builds its own search path). So on the server
every TF2 model is missing: props have no physics, NPCs have no sequences,
spell pickups do not animate. The harness may write only under
garrysmod/data/ws_tests/, so it cannot mount this folder itself; it is
ready for whoever may add it as an addon or a mount.cfg path.

Only what the server reads is extracted: .mdl, .phy, .ani and .vvd of the
models named by the maps' entities, by the addon's Lua, and under the
directories in PREFIXES, with every model they include ($includemodel).
Static props are left out (their collision comes from the same .phy files,
but there are thousands); the report says so.
"""
from __future__ import annotations

import argparse
import struct
import sys
from pathlib import Path
from typing import Iterable, List, Mapping, Set, Tuple

import bsp_entities
from tf2_content import Kind, Vpk, references_in_lua

__all__ = [
    "INCLUDE_COUNT_OFFSET",
    "MODEL_SUFFIXES",
    "OUT_DIR",
    "include_models",
    "model_names_in_entities",
    "write_content",
]

REPO = Path(__file__).resolve().parents[2]
OUT_DIR = REPO / ".devtools" / "artifacts" / "tf2-server-content"
TF_DIR = Path.home() / (
    "Library/Application Support/CrossOver/Bottles/Steam/"
    "drive_c/Steam/steamapps/common/Team Fortress 2/tf"
)
MISC_VPK = "tf2_misc_dir.vpk"
MODEL_SUFFIXES = (".mdl", ".phy", ".ani", ".vvd")
# Whole directories of models the gamemode spawns by name built at run time.
PREFIXES = (
    "models/bots/",
    "models/props_halloween/",
    "models/items/",
    "models/props_trainyard/bomb_",
    "models/props_mvm/",
    "models/weapons/c_models/c_bigaxe/",
)
# studiohdr_t (public/studio.h): numincludemodels, then includemodelindex.
INCLUDE_COUNT_OFFSET = 336
GROUP = struct.Struct("<ii")  # mstudiomodelgroup_t: szlabelindex, sznameindex


def include_models(mdl: bytes) -> List[str]:
    if len(mdl) < INCLUDE_COUNT_OFFSET + 8:
        return []
    count, index = struct.unpack_from("<ii", mdl, INCLUDE_COUNT_OFFSET)
    names = []
    for i in range(count):
        at = index + GROUP.size * i
        _, name_at = GROUP.unpack_from(mdl, at)
        start = at + name_at
        names.append(mdl[start:mdl.index(b"\0", start)].decode("latin-1"))
    return names


def model_names_in_entities(entities: Iterable[Mapping[str, str]]) -> Set[str]:
    names = set()
    for e in entities:
        model = e.get("model", "").lower().replace("\\", "/")
        if model.startswith("models/") and model.endswith(".mdl"):
            names.add(model)
    return names


def write_content(vpk, models: Set[str], out: Path) -> Tuple[int, List[str]]:
    """Writes each model with its siblings and includes; returns the files
    written and the models not in the VPK."""
    written, missing, seen = 0, [], set()
    pending = sorted(models)
    while pending:
        name = pending.pop()
        if name in seen:
            continue
        seen.add(name)
        if name not in vpk:
            missing.append(name)
            continue
        stem = name[: -len(".mdl")]
        for suffix in MODEL_SUFFIXES:
            file = stem + suffix
            if file in vpk:
                data = vpk.read(file)
                target = out / file
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(data)
                written += 1
                if suffix == ".mdl":
                    pending += [n.lower() for n in include_models(data) if n.lower() not in seen]
    return written, sorted(missing)


def wanted_models(vpk: Vpk, maps: Iterable[str]) -> Set[str]:
    models = set()
    for name in maps:
        bsp = TF_DIR / "maps" / f"{name}.bsp"
        if bsp.exists():
            entities = bsp_entities.parse_entity_lump(bsp_entities.read_entity_lump(bsp.read_bytes()))
            models |= model_names_in_entities({k.lower(): v for k, v in e.pairs} for e in entities)
    for lua in (REPO / "addon").rglob("*.lua"):
        for ref in references_in_lua(lua.read_text(errors="replace"), str(lua)):
            if ref.kind is Kind.MODEL:
                name = ref.name.lower()
                models.add(name if name.startswith("models/") else f"models/{name}")
    models |= {n for n in vpk.names if n.endswith(".mdl") and n.startswith(PREFIXES)}
    return models


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("maps", nargs="+")
    args = ap.parse_args()
    vpk = Vpk.open(TF_DIR / MISC_VPK)
    written, missing = write_content(vpk, wanted_models(vpk, args.maps), OUT_DIR)
    print(f"{written} files in {OUT_DIR}; {len(missing)} models named but not in {MISC_VPK}")
    for name in missing:
        print(f"  missing: {name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
