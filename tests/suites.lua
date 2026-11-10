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
			"generator_*", "timer_*", "analysis_*", "transaction*", "configstore", "nodegraph", "wetsands_*", "foundation_*",
		},
		sources = { G .. "foundation/", G .. "shared_loader.lua", "native/" },
	},
	{
		name = "games",
		about = "includes/: the gamemode core, gameplay models and Lua API extensions",
		tests = {
			"games_*", "bullet_steps", "combat_text", "crit_effects", "fixed_spread", "hit_sound", "jar",
			"weapon_*", "player_attributes", "players_conditions", "players_pickups", "players_ctf_capture_crits",
			"targeting",
		},
		sources = {
			G .. "includes/gameplay/", G .. "includes/npc/", G .. "includes/system/",
			G .. "includes/extensions/", E .. "entities/tf_projectile_", E .. "entities/ent_projectile_",
		},
	},
	{
		name = "nextsoldier",
		about = "NextSoldier, the soldier itself (its addon): movement, senses, body, behaviours, the response rules it speaks by",
		tests = { "nextsoldier_*", "addons_nextsoldier", "responserules*", "combine_voice_pack" },
		sources = {
			"addons/nextsoldier/", G .. "sh_nextsoldier_host.lua", "tests/fake_soldier.lua", "tests/fake_room.lua", "tests/fake_legs.lua",
			E .. "entities/base_nextsoldier", E .. "entities/npc_nextsoldier", E .. "entities/npc_path", E .. "entities/npc_ctfbot",
			E .. "entities/ws_bot_navigator",
		},
	},
	{
		name = "war",
		about = "the AI war: the tactics engine (its addon) and features/aiwar",
		tests = { "wartactics_*", "addons_wartactics", "aiwar_*", "features_aiwar_*" },
		sources = { "addons/wartactics/", G .. "features/aiwar/", G .. "sh_war_soldier.lua", G .. "sh_aiwar.lua", G .. "cl_aiwar_slots.lua" },
	},
	{
		name = "rounds",
		about = "the round and its objectives, and the base gamemode's modules (net2): rounds, capture, koth, flag, payload, arena, mvm, the gamemode feature",
		tests = {
			"rounds_*", "gamemode_ready", "gamemode_round_players_ready", "gamemode_tournament", "gameplay",
			"games_gameplay_rounds_*", "games_gameplay_capture_*", "capture_*", "objective_snapshots", "koth", "flag", "round_manager", "game_timer", "net2", "game_events", "hit_audit",
			"mvm", "payload_mode", "spawn_*", "teams_controller", "players_teams*",
			"player_classes", "player_spectator",
			"features_rounds_*", "features_world_*", "features_capture_*", "features_arena_*", "features_payload_*",
		},
		sources = {
			G .. "includes/gameplay/rounds", G .. "includes/gameplay/capture", G .. "includes/gameplay/spawn",
			G .. "includes/gameplay/teams",
			G .. "init.lua", G .. "shared.lua", G .. "player_class/",
			G .. "sv_spawn_manager.lua", G .. "sv_teams.lua",
			G .. "features/rounds/", G .. "features/world/", G .. "features/capture/", G .. "features/koth/", G .. "features/flag/",
			G .. "features/payload/", G .. "features/arena/", G .. "features/mvm/", G .. "features/gamemode/",
			"tests/fake_objective.lua", "tests/fake_points.lua",
			E .. "entities/team_", E .. "entities/tf_logic_", E .. "entities/game_", E .. "entities/func_respawnroom",
			E .. "entities/func_capturezone", E .. "entities/trigger_capture_area", E .. "entities/item_teamflag",
			E .. "entities/info_observer_point", G .. "includes/modules/round_manager.lua", G .. "includes/modules/game_timer.lua",
			G .. "includes/modules/net2.lua", G .. "includes/modules/game_events.lua", G .. "includes/modules/hit_audit.lua",
			E .. "entities/tf_gamerules", E .. "entities/ws_gamerules", E .. "entities/edit_",
		},
	},
	{
		name = "features",
		about = "the other features: haunting bosses, holiday, spells, hazards, hostage, defuse, npc, nbdebug, tag, wheel",
		tests = {
			"features_*", "boss_*", "croc", "eyeball_boss", "ghost", "halloween_boss", "headless_hatman", "merasmus",
			"zombie", "fortune", "holiday_on_holiday", "spells_cast", "tag", "wheel", "trigger_ignite", "npc_*",
			"ns_debug_panel", "nbdebug_contract", "fgd_sandcastle",
		},
		sources = { G .. "features/", G .. "vendor/", E, "tests/fake_actor.lua", "tests/fake_builder.lua", "tests/fake_combatant.lua", "tests/fake_caster.lua" },
	},
	{
		name = "ws",
		about = "the gamemode's root modules: always-loaded glue, the HUD, menus, editors and admin tools",
		tests = {
			"ws_*", "proxy", "proxy_registry", "radio_gesture", "match_control", "match_tab", "players_menu", "ui",
			"admin_properties", "permissions_adapter", "editor_*", "gameplay_settings", "tf_hud", "tf_materials",
			"vote_hud", "votes_controller", "sound_paths", "voices_controller", "nav_generate",
			"nav_progress_replay", "demo_autorecord",
		},
		sources = {
			G .. "cl_", G .. "sh_", G .. "sv_", G .. "logging.lua", G .. "gamerules/", G .. "includes/game_manager.lua",
			G .. "includes/admin_notices.lua", G .. "includes/demo_autorecord.lua", G .. "includes/factions.lua", G .. "includes/friendly_id.lua",
			G .. "includes/kill_icons_sheet.lua", G .. "includes/localization.lua",
			G .. "includes/nav_clearance.lua", G .. "includes/nav_progress.lua",
			G .. "includes/ragdoll.lua", G .. "includes/replicated.lua",
			G .. "includes/scoreboard.lua", G .. "includes/settings.lua",
			G .. "includes/sound_paths.lua", G .. "includes/soundscapes.lua",
			G .. "includes/tf_hud.lua", G .. "includes/tf_materials.lua",
			G .. "includes/voices.lua", G .. "includes/vote_hud.lua",
			E .. "entities/info_ladder", E .. "entities/ws_editor", E .. "entities/ws_gameplay_settings", E .. "entities/ws_proxy",
		},
	},
	{
		name = "addons",
		about = "the addons beside the gamemode: Team Tint, the CS:S weapons and the model viewer",
		tests = { "teamtint_*", "addons_cstrike_weapons*", "model_viewer_*" },
		sources = { "addons/teamtint/", "addons/cstrike_weapons/", "addons/model_viewer/" },
	},
	{
		name = "tooling",
		about = "the test harness, the loaders' rules, the dev workbench and the server tools",
		tests = {
			"dev_*", "server_*", "harness", "suites", "loader_locals", "local_before_use", "hook_names",
			"client_load_order", "client_shipping", "content_downloads", "cfg_defaults", "feature_parts",
			"gamemode_manifest", "entity_baseclass",
		},
		sources = {
			"tests/harness.lua", "tests/suites.lua", "tests/fixtures/", "addons/sandcastle_dev/", "addons/ulx_luadev/", ".devtools/bin/",
			"addons/sandcastle/cfg/", G .. "cl_init.lua",
		},
	},
}
