# .devtools

<!-- Written by `dt devtools/index`: edit the tools' first lines, not this file. -->

## Tools (57)

| Tool | What |
|---|---|
| `bin/aiwar_look_probe.lua` | What each part of a war bot's look costs (features/aiwar/sv_bots.lua's Controller:Look), for a |
| `bin/aiwar_tick_probe.lua` | What the AI war costs the server thread, measured for a window and then |
| `bin/aiwar_tree_probe.lua` | What a soldier's behaviour tree costs, by action and method, for a window and then put back, |
| `bin/bot_probe.lua` | What a player bot (player.CreateNextBot) can be made to do from |
| `bin/bot_status.lua` | The AI war's bot soldiers at a glance (features/aiwar/sv_bots.lua), on |
| `bin/check/check_engine_names.sh` | Whether Garry's Mod already defines a console name: searches the strings of |
| `bin/check/check_lua.sh` | Check groups of the test suites (tests/suites.lua, one group a major |
| `bin/check/check_lua_gate.py` | A PreToolUse hook (.claude/settings.json) that keeps an agent's Lua checks |
| `bin/check/check_names.py` | Check Sandcastle's own names in Lua: no TF2 in them, and every hook and networked var has both ends. |
| `bin/check/check_totals.sh` | check_totals.sh BASE: the LuaJIT test total never drops, commit by commit. |
| `bin/check/lua_format.py` | Format Lua (GLua) the way notcake formats gcompute and glib. |
| `bin/check/run_lua_tests.sh` | Run the given test files (tests/*_test.lua) under LuaJIT from the repo |
| `bin/check/suites.lua` | The test suites grouped by major system: tests/suites.lua names each |
| `bin/ctfbot_check.lua` | npc_ctfbot on a live server on an MvM map, as returned data: it is spawned by the |
| `bin/ctfbot_demo.lua` | npc_ctfbot to watch in game, on a server on an MvM map: it is spawned by the bomb, |
| `bin/engineer_defense.lua` | The engineers' defence bench: RED's engineers (npc_pathfollower on their legs, armed, building |
| `bin/gamemode_art.py` | Render the gamemode's menu art from its SVG master. |
| `bin/gmod_plugin.py` | Puts the gmod plugin's tools on sys.path, for this repo's benches and probes |
| `bin/hotswap_listing.lua` | Prints what `ws_hotswap_feature <feature>` would list on the server |
| `bin/kill_icons_art.py` | Draw HL2's weapons as TF2 kill icons, in PhotoCraft. |
| `bin/lane_audit.lua` | Audits the AI war's lanes on the running server (dt lua -f .devtools/bin/lane_audit.lua): |
| `bin/map_census.py` | Census of the entity classes TF2 maps use that Sandcastle does not provide. |
| `bin/map_view.py` | Render a view of a .vmf to a PNG, through hammer-mcp's render_vmf_view. |
| `bin/native_bench.lua` | Whether a native twin of a foundation module pays: each module's cases run |
| `bin/native_linux.py` | Build the repo's binary modules for GMod's Linux server (srcds.py --runtime docker). |
| `bin/nav_reach.lua` | What WS.NavLinkCrossable refuses on the running map, and what that cuts |
| `bin/navsearch_live_check.lua` | On the dedicated server, with the native foundation installed over |
| `bin/next_soldier_head_check.lua` | How a bot player's head goes with its feet, each tick, as data: how far its eyes are off |
| `bin/next_soldier_round_check.lua` | The assessment of bot players on the engine's statechart, as data a map change does |
| `bin/nextbot_layout.py` | NextSoldier's engine layout, read and checked offline: the vtable slots and field offsets |
| `bin/nextsoldier_components_check.lua` | actor.body, actor.vision and actor.intention (addons/nextsoldier/native, actor_bind.rs) on a |
| `bin/nextsoldier_engine_check.lua` | What the engine does with Actions addons/nextsoldier/native builds, checked on a live |
| `bin/ns_fixture_map.py` | Build ns_fixture, the NextSoldier pathing fixture map, through hammer-mcp. |
| `bin/profile_server.lua` | A function profiler for the dedicated server, run through server_lua.py: |
| `bin/publish_public.sh` | Publishes main to the public mirror (moonexpr/sandcastle-public) without |
| `bin/rooms/ambush.py` | Ambush hints: hiding spots beside the entrances an enemy squad comes through. |
| `bin/rooms/assault_view.py` | Draw an assault's placements on dev_3house's bench, one panel for each enemy position. |
| `bin/rooms/classes.py` | Room classes from the incursion: what each room is for when a round starts (docs/places-plan.md §2.3). |
| `bin/rooms/classes_view.py` | Class a dumped map's rooms from the incursion (classes.py) and draw them from above. |
| `bin/rooms/incursion.py` | Incursion: how each team walks into the map from its spawns (docs/places-plan.md §2.1). |
| `bin/rooms/incursion_view.py` | Draw each team's incursion routes over a dumped map's rooms, the baseline traffic. |
| `bin/rooms/places.py` | What each room is for when a round starts (docs/places-plan.md §2.3). |
| `bin/rooms/places_diff.py` | The rooms whose starting class changes between a revision of places.py and the working tree's, on a dump: |
| `bin/rooms/rooms_dump.lua` | The running map's room graph and windows (the AI war controller's |
| `bin/rooms/rooms_view.py` | Partition a dumped room graph with wartactics.rooms and draw it from above. |
| `bin/sdk_layout.py` | The Source SDK's NextBot classes laid out by a compiler, for both of GMod's ABIs, to |
| `bin/sound_pack.py` | Install a sound replacement pack's .wav files under a content sound/ folder, |
| `bin/source_tools.py` | Puts claude-config2's Source and GMod format readers on sys.path (its |
| `bin/squad_member_check.lua` | npc_pathfollower driven by its legs on a live server, as the Path Follower stool's Local mode |
| `bin/strip_attribution.py` | Rewrite a branch's history without Claude or Copilot attribution. |
| `bin/stuck_census.lua` | A census of who gets stuck, for `dt lua [--instance N] -f |
| `bin/stuck_report.lua` | What the stuck census (.devtools/bin/stuck_census.lua) has seen, for |
| `bin/tactical_behavior_check.lua` | The Path Follower stool's Tactical mode on a live server, read back as data: followers put in |
| `bin/teamtint_bake.py` | Bake Team Tint's team textures, and the addon's own (addons/teamtint). |
| `bin/tf2_server_content.py` | Extract the TF2 models a dedicated GMod server needs, for the in-game harness. |
| `bin/vendor_source_sdk.sh` | Copies the Source SDK 2013 files foundation's crate builds against from a local clone |
| `bin/war_round_check.lua` | An AI war round on a CTF map as data a map change does not lose: BLU's bots against nobody, |

## Experiments (10)

Each folder holds its scripts, a README and its results (`results/`, ignored by git).

| Experiment | Question | Status |
|---|---|---|
| `experiments/aiwar-bench/` | what does a change cost or gain the AI war, measured on the same fight: native foundation against the Lua twins, NPC soldiers against bot players, before against after, and how much the soldiers actually fight. | open |
| `experiments/dev-3house/` | do squads carry out room operations (muster, stage, assault, clear, evacuate) on a small known map, a stage at a time, and how do armed assaults on a held building go? | open |
| `experiments/devtools-audit/` | what lives in `.devtools/bin` and `.claude`, how the harness came to be this way, and whether it earns its keep. The answer is the report of 2026-11-13 (`.devtools/artifacts/devtools-report-2026-11-13.pdf`; a copy in iCloud), whose Section 10 the cleanup follows. | answered; kept until the cleanup it ordered is done, then deleted |
| `experiments/dustbowl-stage2/` | on cp_dustbowl's second stage, does BLU take its second point on its own? | open; likely answered, so close it when you agree |
| `experiments/foundation-bench/` | are the foundation modules the hand-rolled-code epic (#12) built faster than the code they replaced, as Lua twins and as native twins? | open |
| `experiments/hostage-survey/` | how does the AI war's hostage rescue play on each CS:S map, and where do the maps need hotfixes? | open |
| `experiments/ingame/` | do Sandcastle's features work in game, map by map? | open |
| `experiments/ns-bench/` | where do soldiers fail to walk on real geometry? | open |
| `experiments/routes/` | what do the server's route searches cost, and do they answer the same when told the blockers and spawn rooms as data up front instead of asking Lua rules area by area? | open |
| `experiments/stranding-ab/` | how often do the AI war's soldiers get stuck, one checkout's gamemode against another's? | open |
