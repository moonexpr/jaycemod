-- The test suites by major system, which check_lua.sh runs a group at a
-- time (.devtools/bin/suites.lua resolves them; tests/suites_test.lua holds
-- every test to exactly one group and every source file to a claim).
--   tests:   a test's name (tests/<name>_test.lua), or a prefix ending in *;
--            the closest pattern wins, an exact name before any prefix
--   sources: the paths a group covers (a folder ending in /, or a path
--            prefix), which `check_lua.sh --changed` maps a changed file
--            through; the closest claim wins
local G = "addons/sandcastle/gamemodes/sandcastle/gamemode/"
local E = "addons/sandcastle/gamemodes/sandcastle/entities/"

return {
	{
		name = "foundation",
		about = "foundation's structures, formalisms and wetsands, Lua and native twins",
		tests = {
			"core_*", "list_*", "tree_*", "world_*", "cache_*", "graph_*", "math_*", "file_*", "encoding_*",
			"generator_*", "analysis_*", "transaction*", "configstore", "nodegraph", "wetsands_*", "foundation_*",
		},
		sources = { G .. "foundation/", G .. "shared_loader.lua", "native/" },
	},
	{
		name = "games",
		about = "games/: the gamemode core, gameplay models, combat and projectiles",
		tests = {
			"games_*", "bullet_steps", "combat_text", "crit_effects", "fixed_spread", "hit_sound", "jar",
			"weapon_*", "player_attributes", "players_conditions", "players_pickups", "players_ctf_capture_crits",
			"targeting",
		},
		sources = { G .. "games/", E .. "entities/tf_projectile_" },
	},
	{
		name = "nextsoldier",
		about = "NextSoldier, the soldier itself: movement, senses, body, behaviours",
		tests = { "nextsoldier_*" },
		sources = {
			G .. "nextsoldier/", "tests/fake_soldier.lua",
			E .. "entities/base_nextsoldier", E .. "entities/npc_nextsoldier", E .. "entities/npc_path",
			E .. "entities/ws_bot_navigator",
		},
	},
	{
		name = "war",
		about = "the AI war: the tactics engine (wartactics/) and features/aiwar",
		tests = { "wartactics_*", "aiwar_*", "features_aiwar_*" },
		sources = { G .. "wartactics/", G .. "features/aiwar/", G .. "ws/sh_war_soldier.lua", G .. "ws/sh_aiwar.lua", G .. "ws/cl_aiwar_slots.lua" },
	},
	{
		name = "rounds",
		about = "the round and its objectives: rounds, capture, koth, flag, payload, arena, mvm, the gamemode feature",
		tests = {
			"rounds_*", "gamemode_ready", "gamemode_round_players_ready", "gamemode_tournament", "gameplay",
			"games_gameplay_rounds_*", "games_gameplay_capture_*", "capture_*", "objective_snapshots", "koth", "flag",
			"mvm", "payload_mode", "spawn_*", "spectate_controller", "teams_controller", "players_teams*",
			"features_rounds_*", "features_capture_*", "features_arena_*", "features_payload_*",
		},
		sources = {
			G .. "games/gameplay/rounds", G .. "games/gameplay/capture", G .. "games/gameplay/spawn", G .. "games/gameplay/spectate",
			G .. "games/gameplay/teams",
			G .. "features/rounds/", G .. "features/capture/", G .. "features/koth/", G .. "features/flag/",
			G .. "features/payload/", G .. "features/arena/", G .. "features/mvm/", G .. "features/gamemode/",
			"tests/fake_objective.lua", "tests/fake_points.lua",
			E .. "entities/team_", E .. "entities/tf_logic_", E .. "entities/game_", E .. "entities/func_respawnroom",
			E .. "entities/func_capturezone", E .. "entities/trigger_capture_area", E .. "entities/item_teamflag",
			E .. "entities/tf_gamerules", E .. "entities/ws_gamerules", E .. "entities/edit_",
		},
	},
	{
		name = "features",
		about = "the other features: haunting bosses, holiday, spells, hazards, hostage, defuse, npc, nbdebug, tag, wheel",
		tests = {
			"features_*", "boss_*", "croc", "eyeball_boss", "ghost", "halloween_boss", "headless_hatman", "merasmus",
			"zombie", "fortune", "holiday_on_holiday", "spells_cast", "tag", "wheel", "trigger_ignite", "npc_*",
			"ns_debug_panel", "nbdebug_contract",
		},
		sources = { G .. "features/", G .. "vendor/", E, "tests/fake_actor.lua", "tests/fake_combatant.lua", "tests/fake_caster.lua" },
	},
	{
		name = "ws",
		about = "ws/: the always-loaded glue, the HUD, menus, editors and admin tools",
		tests = {
			"ws_*", "proxy", "proxy_registry", "radio_gesture", "match_control", "players_menu", "ui",
			"admin_properties", "permissions_adapter", "editor_*", "gameplay_settings", "tf_hud", "tf_materials",
			"vote_hud", "votes_controller", "freeze_panel", "sound_paths", "voices_controller", "nav_generate",
			"nav_progress_replay",
		},
		sources = { G .. "ws/", E .. "entities/ws_editor", E .. "entities/ws_gameplay_settings", E .. "entities/ws_proxy" },
	},
	{
		name = "addons",
		about = "the addons beside the gamemode: Team Tint and the response rules",
		tests = { "teamtint_*", "responserules*", "combine_voice_pack", "addons_cstrike_weapons*" },
		sources = { "addons/teamtint/", "addons/responserules/", "addons/cstrike_weapons/" },
	},
	{
		name = "tooling",
		about = "the test harness, the loaders' rules, the dev workbench and the server tools",
		tests = {
			"dev_*", "server_*", "harness", "suites", "loader_locals", "local_before_use", "hook_names",
			"client_load_order", "client_shipping", "content_downloads", "cfg_defaults", "feature_parts",
			"gamemode_manifest",
		},
		sources = {
			"tests/harness.lua", "tests/suites.lua", "tests/fixtures/", "addons/sandcastle_dev/", ".devtools/bin/",
			"addons/sandcastle/cfg/", G .. "init.lua", G .. "cl_init.lua", G .. "shared.lua",
		},
	},
}
