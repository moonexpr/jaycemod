#!/usr/bin/env python3
"""Move modules between foundation's namespaces and game/.

docs/foundation-game-split-plan.md: each module (and its test) moves with
`git mv`, and every Lua file under addons/, tests/ and .devtools/bin/ has the
old name rewritten, dotted (foundation.core.structs.heap) and slashed
(foundation/core/structs/heap, and core/structs/heap for a move within
foundation, as the layers test names modules). Moves run in order, so a name
moved twice (core/pathfinder, then npc/pathfinder) reaches its last place. A
second run finds nothing to move and nothing to rewrite, so it can run again
over files merged in later.

    foundation_rename.py [--dry-run]
"""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
from dataclasses import dataclass
from functools import cached_property
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
GAMEMODE = Path("addons/sandcastle/gamemodes/sandcastle/gamemode")
FOUNDATION = "foundation/"
TESTS = Path("tests")
SEARCHED = ("addons", "tests", ".devtools/bin")


@dataclass(frozen=True)
class Move:
    """A module's path under gamemode/, before and after, without .lua."""

    old: str
    new: str

    def __post_init__(self) -> None:
        for path in (self.old, self.new):
            if not re.fullmatch(r"(foundation|game|games|features|ws)(/[a-z_][a-z0-9_]*)+", path):
                raise ValueError(f"not a module path under the gamemode's module trees: {path!r}")

    @property
    def files(self) -> tuple[Path, Path]:
        return GAMEMODE / f"{self.old}.lua", GAMEMODE / f"{self.new}.lua"

    @property
    def tests(self) -> tuple[Path, Path]:
        """foundation/<path> is tested in <path>_test.lua, game/<path> in game_<path>_test.lua."""

        def test(path: str) -> Path:
            name = path.removeprefix(FOUNDATION)
            return TESTS / f"{name.replace('/', '_')}_test.lua"

        return test(self.old), test(self.new)

    @property
    def within_foundation(self) -> bool:
        return self.old.startswith(FOUNDATION) and self.new.startswith(FOUNDATION)

    @cached_property
    def substitutions(self) -> tuple[tuple[re.Pattern[str], str], ...]:
        """Each old spelling's pattern and its new spelling, compiled once."""
        test_old, test_new = (p.stem for p in self.tests)
        dotted_old, dotted_new = (p.replace("/", ".") for p in (self.old, self.new))
        pairs = [
            (rf"(?<![\w]){re.escape(test_old)}(?![\w])", test_new),
            # not a module under this one (foundation.npc.actor is not foundation.npc's)
            (rf"(?<![\w.]){re.escape(dotted_old)}(?![\w]|\.\w)", dotted_new),
            (rf"(?<![\w.]){re.escape(self.old)}(?![\w/])", self.new),
        ]
        if self.within_foundation:
            bare_old, bare_new = (p.removeprefix(FOUNDATION) for p in (self.old, self.new))
            pairs.append((rf"(?<![\w./]){re.escape(bare_old)}(?![\w/])", bare_new))
        return tuple((re.compile(pattern), new) for pattern, new in pairs)

    @cached_property
    def needles(self) -> tuple[str, ...]:
        """Plain text one of the old spellings contains: a file without any is skipped."""
        test_old = self.tests[0].stem
        return (test_old, self.old.replace("/", "."), self.old.removeprefix(FOUNDATION))

    def rewrite(self, text: str) -> str:
        if not any(needle in text for needle in self.needles):
            return text
        for pattern, new in self.substitutions:
            text = pattern.sub(new, text)
        return text


def within_foundation(old: str, new: str) -> Move:
    return Move(FOUNDATION + old, FOUNDATION + new)


MOVES = tuple(
    within_foundation(old, new)
    for old, new in (
        ("core/meta/class", "core/class"),
        ("core/meta/port", "core/port"),
        ("core/meta/constants", "core/constants"),
        ("core/meta/enum", "core/enum"),
        ("core/math/geometry", "math/geometry"),
        ("core/math/scalar", "math/scalar"),
        ("core/math/stats", "math/stats"),
        ("core/math/random", "math/weighted"),
        ("core/math/polynomial", "math/polynomial"),
        ("core/math/matrix", "math/matrix"),
        ("core/structs/polyline", "math/polyline"),
        ("core/structs/queue", "list/queue"),
        ("core/structs/ring", "list/ring"),
        ("core/structs/chain", "list/chain"),
        ("core/structs/slots", "list/slots"),
        ("core/scheduler", "list/schedule"),
        ("core/structs/heap", "tree/heap"),
        ("core/structs/tree", "tree/avl"),
        ("core/structs/sets", "map/sets"),
        ("core/structs/pairmap", "map/pairmap"),
        ("core/structs/grid", "map/grid"),
        ("core/structs/lease", "map/lease"),
        ("core/graph", "graph/search"),
        ("core/structs/cache", "cache/base"),
        ("core/structs/lru", "cache/lru"),
        ("core/structs/expiring", "cache/expiring"),
        ("core/structs/memo", "cache/memo"),
        ("core/cfsm", "generator/state_machine"),
        ("core/parsers/cursor", "encoding/cursor"),
        ("core/parsers/utf16", "encoding/utf16"),
        ("core/parsers/keyvalues", "encoding/keyvalues"),
        ("core/parsers/consolecfg", "encoding/consolecfg"),
        ("core/parsers/cvarfile", "encoding/cvarfile"),
        ("core/gma", "encoding/gma"),
        ("core/buffer", "file/buffer"),
        ("core/analytics", "analysis/analytics"),
        ("core/memory", "analysis/memory"),
        ("core/pathfinder", "npc/pathfinder"),
        ("npc/pathfinder", "graph/pathfinder"),
        ("core/transaction", "transaction"),
    )
) + tuple(
    Move(old, new)
    for old, new in (
        ("foundation/core/drawlist", "game/list/drawlist"),
        ("foundation/core/map_io", "game/world/io"),
        ("foundation/core/snapshot", "game/world/snapshot"),
        ("foundation/core/tactics", "game/gameplay/tactics"),
        ("foundation/core/hfsm", "game/generator/hfsm"),
        ("foundation/pathfinder/astar", "game/npc/astar"),
        # GMod has a game library, and module(...) builds a module's dotted
        # path in the globals: the tree is games/.
        ("game/list/drawlist", "games/list/drawlist"),
        ("game/world/io", "games/world/io"),
        ("game/world/snapshot", "games/world/snapshot"),
        ("game/gameplay/tactics", "games/gameplay/tactics"),
        ("game/generator/hfsm", "games/generator/hfsm"),
        ("game/npc/astar", "games/npc/astar"),
        ("game/timer/countdown", "games/timer/countdown"),
        ("game/timer/interval", "games/timer/interval"),
    )
) + tuple(
    Move(f"foundation/{old}", f"games/{new}")
    for old, new in (
        ("events", "system/events"),
        ("features", "system/features"),
        ("gamemode", "system/gamemode"),
        ("permissions", "system/permissions"),
        ("play_mode", "system/play_mode"),
        ("spawn_manager", "system/spawn_manager"),
        ("idle", "system/idle"),
        ("rounds", "gameplay/rounds"),
        ("rounds/state", "gameplay/rounds/state"),
        ("rounds/timer", "gameplay/rounds/timer"),
        ("rounds/limits", "gameplay/rounds/limits"),
        ("teams", "gameplay/teams"),
        ("spawn", "gameplay/spawn"),
        ("spectate", "gameplay/spectate"),
        ("respawn_modifiers", "gameplay/respawn_modifiers"),
        ("arrivals", "gameplay/arrivals"),
        ("loadout", "gameplay/loadout"),
        ("economy", "gameplay/economy"),
        ("kill_credit", "gameplay/kill_credit"),
        ("kill_icons", "gameplay/kill_icons"),
        ("vote", "gameplay/vote"),
        ("reports", "gameplay/reports"),
        ("player_analytics", "gameplay/player_analytics"),
        ("players", "gameplay/players"),
        ("players/attributes", "gameplay/players/attributes"),
        ("players/condition_effects", "gameplay/players/condition_effects"),
        ("capture", "gameplay/capture"),
        ("capture/area", "gameplay/capture/area"),
        ("capture/master", "gameplay/capture/master"),
        ("capture/point_timer", "gameplay/capture/point_timer"),
        ("combat", "gameplay/combat"),
        ("combat/bullet_steps", "gameplay/combat/bullet_steps"),
        ("combat/combat_text", "gameplay/combat/combat_text"),
        ("combat/crit_effects", "gameplay/combat/crit_effects"),
        ("combat/fixed_spread", "gameplay/combat/fixed_spread"),
        ("combat/hit_sound", "gameplay/combat/hit_sound"),
        ("combat/impact", "gameplay/combat/impact"),
        ("combat/weapon_balance", "gameplay/combat/weapon_balance"),
        ("combat/weapon_mimic", "gameplay/combat/weapon_mimic"),
        ("combat/weapon_slot_filter", "gameplay/combat/weapon_slot_filter"),
        ("projectile", "gameplay/projectile"),
        ("projectile/grenade", "gameplay/projectile/grenade"),
        ("projectile/jar", "gameplay/projectile/jar"),
        ("projectile/pipe", "gameplay/projectile/pipe"),
        ("projectile/rocket", "gameplay/projectile/rocket"),
        ("npc", "npc/nextbot"),
        ("npc/actor", "npc/actor"),
        ("npc/combatant", "npc/combatant"),
        ("npc/targeting", "npc/targeting"),
        ("wartactics", "ns/tactics"),
        ("aiwar/squad", "ns/squad"),
        ("aiwar/lanes", "ns/lanes"),
        ("aiwar/speech", "ns/speech"),
        ("aiwar/hearing", "ns/hearing"),
        ("aiwar/explore", "ns/explore"),
        ("aiwar/hunt", "ns/hunt"),
        ("aiwar/posts", "ns/posts"),
        ("aiwar/zone", "ns/zone"),
        ("ns/tuning", "ns/tuning"),
        ("nav_gaps", "ns/nav_gaps"),
        ("npc/path", "ns/path"),
        ("npc/path/ground", "ns/path/ground"),
        ("npc/path/hl2", "ns/path/hl2"),
        ("npc/path/scatter", "ns/path/scatter"),
        ("npc/path/tfbot", "ns/path/tfbot"),
        ("npc/brushes", "ns/brushes"),
        ("npc/clip", "ns/clip"),
        ("npc/detour", "ns/detour"),
        ("npc/doors", "ns/doors"),
        ("npc/leap", "ns/leap"),
        ("npc/noise", "ns/noise"),
        ("npc/portal", "ns/portal"),
        ("npc/probe", "ns/probe"),
        ("npc/rappel", "ns/rappel"),
        ("npc/reach_memo", "ns/reach_memo"),
        ("npc/route_record", "ns/route_record"),
    )
) + tuple(
    # Out of foundation, too close to game logic: to the features and ws/
    # files that run them. A feature's root model is its model.lua.
    Move(f"foundation/{old}", new)
    for old, new in (
        ("hazards", "features/hazards/model"),
        ("hazards/croc", "features/hazards/croc"),
        ("hazards/generic_bomb", "features/hazards/generic_bomb"),
        ("hazards/ignite", "features/hazards/ignite"),
        ("hazards/pumpkin_bomb", "features/hazards/pumpkin_bomb"),
        ("hazards/zapper", "features/hazards/zapper"),
        ("holiday", "features/holiday/model"),
        ("holiday/fortune", "features/holiday/fortune"),
        ("holiday/gift", "features/holiday/gift"),
        ("holiday/halloween", "features/holiday/halloween"),
        ("holiday/wheel", "features/wheel/model"),
        ("spells", "features/spells/model"),
        ("spells/athletic", "features/spells/athletic"),
        ("spells/bats", "features/spells/bats"),
        ("spells/blastjump", "features/spells/blastjump"),
        ("spells/caster", "features/spells/caster"),
        ("spells/fireball", "features/spells/fireball"),
        ("spells/halloween", "features/spells/halloween"),
        ("spells/lightning", "features/spells/lightning"),
        ("spells/meteor", "features/spells/meteor"),
        ("spells/mirv", "features/spells/mirv"),
        ("spells/overheal", "features/spells/overheal"),
        ("spells/skeleton_horde", "features/spells/skeleton_horde"),
        ("spells/spawn_boss", "features/spells/spawn_boss"),
        ("spells/stealth", "features/spells/stealth"),
        ("spells/teleport", "features/spells/teleport"),
        ("projectile/orb", "features/spells/orb"),
        ("payload", "features/payload/model"),
        ("payload/hud", "features/payload/hud"),
        ("payload/race", "features/payload/race"),
        ("rounds/payload", "features/payload/round"),
        ("rounds/arena", "features/arena/round"),
        ("rounds/control_points", "features/rounds/control_points"),
        ("rounds/destruction", "features/rounds/destruction"),
        ("rounds/text", "features/rounds/text"),
        ("aiwar", "features/aiwar/model"),
        ("aiwar/slots", "features/aiwar/slots"),
        ("aiwar/spawns", "features/aiwar/spawns"),
        ("aiwar/scenario", "features/aiwar/scenario"),
        ("aiwar/scenario/arena", "features/aiwar/scenario/arena"),
        ("aiwar/scenario/control_points", "features/aiwar/scenario/control_points"),
        ("aiwar/scenario/ctf", "features/aiwar/scenario/ctf"),
        ("aiwar/scenario/deathmatch", "features/aiwar/scenario/deathmatch"),
        ("aiwar/scenario/freeform", "features/aiwar/scenario/freeform"),
        ("aiwar/scenario/koth", "features/aiwar/scenario/koth"),
        ("aiwar/scenario/mvm", "features/aiwar/scenario/mvm"),
        ("aiwar/scenario/payload", "features/aiwar/scenario/payload"),
        ("aiwar/health", "features/aiwar/health"),
        ("aiwar/marksmanship", "features/aiwar/marksmanship"),
        ("aiwar/arms", "features/aiwar/arms"),
        ("aiwar/orders", "features/aiwar/orders"),
        ("aiwar/soldier", "features/aiwar/soldier"),
        ("aiwar/overlay", "features/nbdebug/aiwar_overlay"),
        ("kill_feed", "features/aiwar/kill_feed"),
        ("ns/inspect", "features/aiwar/inspect"),
        ("replicated", "ws/replicated"),
        ("factions", "ws/factions"),
        ("scoreboard", "ws/scoreboard"),
        ("nav_progress", "ws/nav_progress"),
        ("admin_notices", "ws/admin_notices"),
        ("localization", "ws/localization"),
        ("settings", "ws/settings"),
        ("capture/hud", "features/capture/hud"),
    )
) + tuple(
    # foundation's map namespace is world, beside games' world.
    within_foundation(f"map/{name}", f"world/{name}")
    for name in ("sets", "pairmap", "grid", "lease")
) + tuple(
    # NextSoldier's namespace says its name.
    Move(f"games/ns/{name}", f"games/nextsoldier/{name}")
    for name in (
        "tactics", "tuning", "squad", "lanes", "speech", "hearing", "explore",
        "hunt", "posts", "zone", "nav_gaps", "path", "path/ground", "path/hl2",
        "path/scatter", "path/tfbot", "brushes", "clip", "detour", "doors",
        "leap", "noise", "portal", "probe", "rappel", "reach_memo", "route_record",
    )
)


class Conflict(Exception):
    """A move whose destination is taken, or whose module is nowhere."""


def planned_moves() -> list[tuple[Path, Path]]:
    """The git moves to make, in order, each seeing the moves before it."""
    moved_in: set[Path] = set()
    moved_out: set[Path] = set()

    def exists(path: Path) -> bool:
        return path in moved_in or ((REPO / path).exists() and path not in moved_out)

    pairs = []
    for move in MOVES:
        for (old, new), is_module in ((move.files, True), (move.tests, False)):
            if exists(old) and exists(new):
                raise Conflict(f"{new} exists; {old} cannot move there")
            if exists(old):
                pairs.append((old, new))
                moved_out.add(old)
                moved_in.add(new)
            elif is_module and not exists(new) and not any(
                later.old == move.new for later in MOVES
            ):
                raise Conflict(f"neither {old} nor {new} exists")
    return pairs


def lua_files() -> list[Path]:
    return sorted(p for root in SEARCHED for p in (REPO / root).rglob("*.lua"))


def rewrite_all(dry_run: bool) -> list[Path]:
    changed = []
    for path in lua_files():
        text = path.read_text()
        new = text
        for move in MOVES:
            new = move.rewrite(new)
        if new != text:
            changed.append(path.relative_to(REPO))
            if not dry_run:
                path.write_text(new)
    return changed


def remove_empty_dirs() -> None:
    for root in (REPO / GAMEMODE / "foundation", REPO / GAMEMODE / "game", REPO / GAMEMODE / "games"):
        if not root.exists():
            continue
        for directory in sorted(root.rglob("*"), reverse=True):
            if directory.is_dir() and not any(directory.iterdir()):
                directory.rmdir()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    try:
        moves = planned_moves()
    except Conflict as e:
        print(f"refused: {e}", file=sys.stderr)
        return 1
    for old, new in moves:
        print(f"move {old} -> {new}")
        if not args.dry_run:
            (REPO / new).parent.mkdir(parents=True, exist_ok=True)
            subprocess.run(["git", "mv", str(old), str(new)], cwd=REPO, check=True)
    changed = rewrite_all(args.dry_run)
    for path in changed:
        print(f"rewrite {path}")
    if not args.dry_run:
        remove_empty_dirs()
    print(f"{len(moves)} moved, {len(changed)} rewritten")
    return 0


if __name__ == "__main__":
    sys.exit(main())
