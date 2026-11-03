# Sandcastle

A Garry's Mod gamemode that plays Team Fortress 2's modes (payload, control
points, king of the hill, capture the flag, arena, Mann vs. Machine) on their
own maps, with Counter-Strike: Source's modes to follow, against and beside
**NextSoldier**: NextBot soldiers built after TF2's bots, organised into fire
teams and squads by an AI-war tactics engine.

It's for people who run or play on a GMod server with TF2 and CS:S mounted
and want those games' rounds with HL2's factions and AI soldiers filling the
teams.

## What's in it

| Path | What |
|---|---|
| `addons/sandcastle/` | The gamemode: rounds and objectives, the HUD and menus, the tactics engine |
| `addons/nextsoldier/` | NextSoldier, the NextBot soldier: its modules, its base entities, and the TF2 response rules it speaks by |
| `addons/wartactics/` | The tactics engine: the strategy the soldiers are organised by (fire teams, squads, lanes, posts), the scenarios addons register, and the tactical, squad and scenario monitors |
| `addons/teamtint/` | RED/BLU team shading for NPCs in TF2's style |
| `addons/cstrike_weapons/` | CS:S's weapons as SWEPs, from the game's own weapon scripts |
| `addons/sandcastle_dev/` | For development only, a workbench: live reloads that keep the game's state, saved scenarios, a gamerules harness |
| `native/` | Rust binary modules a server can load in place of the Lua twins of the core data structures and route searches |
| `tests/` | LuaJIT tests, run against the Lua modules and again against their native twins |
| `docs/` | Design notes and plans |

The code is layered bottom-up: `foundation` (generic data structures,
algorithms, codecs and maths, with no game nouns), the gameplay models in
`gamemode/includes/` (pure Lua, I/O through ports), NextSoldier (the soldier
itself), the tactics engine, and the features that wire them to GMod. A test
(`tests/foundation_layers_test.lua`) holds each module to its layer.
`CLAUDE.md` is the full index of the modules and their APIs.

Built with Lua (GLua on GMod's LuaJIT), Rust for the native modules, and
Python for the development tools in `.devtools/bin/`.

## Running it

1. Install Garry's Mod and mount Team Fortress 2 (and Counter-Strike: Source
   for its weapons).
2. Copy or link each folder in `addons/` into `garrysmod/addons/`.
3. Start a server or a local game on a TF2 map (`pl_`, `cp_`, `koth_`,
   `ctf_`, `mvm_`) and pick the Sandcastle gamemode. The main menu's
   settings turn on gameplay mode (`sv_gameplay_enabled`) and the AI war
   (`mp_aiwar_autostart`).

The native modules are optional; without them the server runs the Lua
twins. To build them, `cargo build --release` in `native/foundation` and
`native/wetsands`. `wetsands` reads values from the Source SDK 2013's
headers, which aren't in this repository: clone
[ValveSoftware/source-sdk-2013](https://github.com/ValveSoftware/source-sdk-2013)
and run `.devtools/bin/vendor_source_sdk.sh PATH_TO_CLONE` first.

## Tests

You'll need LuaJIT, plus Cargo for the native pass.

    .devtools/bin/check_lua.sh --list        # the test groups
    .devtools/bin/check_lua.sh foundation    # one group, Lua then native
    .devtools/bin/check_lua.sh --changed     # the groups your changes touch

## Plans

The work ahead is in [ROADMAP.md](ROADMAP.md), in the order it comes. Each
plan in `docs/` explains its own design.

## License

[Apache License 2.0](LICENSE).

## Credits

Third-party art and its licenses are listed in
`addons/sandcastle/gamemodes/sandcastle/credits.txt`. This public copy leaves
out material that isn't the author's to share: vendored third-party Lua and
the Source SDK's headers, a community voice pack built from Half-Life: Alyx's
recordings, and TF2 Classified's HUD art.
