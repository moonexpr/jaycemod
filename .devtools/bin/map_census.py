#!/usr/bin/env python3
"""Census of the entity classes TF2 maps use that Sandcastle does not provide.

  map_census.py koth_ cp_               classes by number of maps, for maps with these prefixes
  map_census.py koth_ cp_ --all         every class, with who provides it

A class is provided when Sandcastle has entities/entities/<class>.lua (ours) or
GMod's server.dll names it (engine: team_control_point, trigger_catapult, ...).
Anything else a map places is MISSING; "tf2" marks classes TF2's FGD declares.
"""
import argparse
import re
from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path

from bsp_entities import parse_entity_lump, read_entity_lump

REPO = Path(__file__).resolve().parents[2]
OURS_DIR = REPO / "addon/gamemodes/sandcastle/entities/entities"
BOTTLE = Path.home() / "Library/Application Support/CrossOver/Bottles/Steam/drive_c/Steam/steamapps/common"
TF2 = BOTTLE / "Team Fortress 2"
GMOD_SERVER = BOTTLE / "GarrysMod/garrysmod/bin/win64/server.dll"
FGD_CLASS = re.compile(r"@\w+Class[^=]*=\s*(\w+)")


def entity_classes(entities) -> set[str]:
    return {e.classname.lower() for e in entities}


@dataclass(frozen=True)
class Provided:
    ours: set[str]
    engine: set[str]
    tf2: set[str]

    OURS, ENGINE, MISSING = "ours", "engine", "MISSING"

    @classmethod
    def installed(cls, classes: set[str]) -> "Provided":
        dll = GMOD_SERVER.read_bytes()
        engine = {c for c in classes if b"\x00" + c.encode() + b"\x00" in dll}
        ours = {p.stem.lower() for p in OURS_DIR.glob("*.lua")}
        tf2 = set(m.lower() for m in FGD_CLASS.findall((TF2 / "bin/tf.fgd").read_text(errors="ignore")))
        return cls(ours, engine, tf2)

    def status(self, cls: str) -> str:
        if cls in self.ours:
            return self.OURS
        if cls in self.engine:
            return self.ENGINE
        return self.MISSING


@dataclass(frozen=True)
class Census:
    maps_by_class: dict[str, list[str]] = field(default_factory=dict)

    @classmethod
    def of(cls, classes_by_map: dict[str, set[str]]) -> "Census":
        by_class: dict[str, list[str]] = {}
        for name in sorted(classes_by_map):
            for c in classes_by_map[name]:
                by_class.setdefault(c, []).append(name)
        return cls(by_class)

    def rows(self, provided: Provided, prefixes, only_missing: bool):
        out = []
        for c, maps in self.maps_by_class.items():
            if only_missing and provided.status(c) != Provided.MISSING:
                continue
            per_prefix = {p: sum(1 for m in maps if m.startswith(p)) for p in prefixes}
            out.append((c, len(maps), per_prefix, maps))
        return sorted(out, key=lambda r: (-r[1], r[0]))

    def missing(self, provided: Provided, prefixes):
        return self.rows(provided, prefixes, only_missing=True)


def load(prefixes) -> dict[str, set[str]]:
    classes = {}
    for bsp in sorted((TF2 / "tf/maps").glob("*.bsp")):
        if bsp.stem.startswith(tuple(prefixes)):
            classes[bsp.stem] = entity_classes(parse_entity_lump(read_entity_lump(bsp.read_bytes())))
    return classes


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("prefixes", nargs="+")
    ap.add_argument("--all", action="store_true")
    args = ap.parse_args()
    classes_by_map = load(args.prefixes)
    census = Census.of(classes_by_map)
    provided = Provided.installed(set(census.maps_by_class))
    print(f"maps: {len(classes_by_map)}")
    for c, n, per, maps in census.rows(provided, args.prefixes, only_missing=not args.all):
        split = " ".join(f"{p}{k}" for p, k in per.items())
        tag = "tf2" if c in provided.tf2 else ""
        few = ",".join(maps) if n <= 3 else ""
        print(f"{n:4d}  {c:40s} {provided.status(c):8s} {tag:4s} {split}  {few}")


if __name__ == "__main__":
    main()
