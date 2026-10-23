-- The server convars the menus may set: the Options and Utilities panels,
-- the C menu's bar (its Economy and Gameplay menus, and GMod's own NPCs and
-- Server menus, which on a dedicated server work only for the listen host),
-- and the AI War panel. A client cannot set a server's convar itself
-- ("Can't change replicated ConVar ... from console of client"), so a menu
-- sends ws_server_set name value, and the server sets it for a holder of the
-- setting's privilege (games.system.permissions), after Parse holds the value
-- to the range the menu's control offers. Every setting is an integer, kept
-- in a foundation.configstore whose guards are privileges.
local ConfigStore = require("foundation.configstore")
local AiWar = require("features.aiwar.model")
local Slots = require("features.aiwar.slots")
local Permissions = require("games.system.permissions")
module(...)

local RULES = Permissions.RULES
local NEXTSOLDIER = Permissions.NEXTSOLDIER
local ECONOMY = Permissions.ECONOMY
local GAMEPLAY = Permissions.GAMEPLAY

-- GMod's own NPCs and Server menus' options (lua/autorun/menubar.lua's
-- host-only ones), in their menus' order.
PROXIED = {
	"ai_disabled",
	"ai_ignoreplayers",
	"ai_serverragdolls",
	"npc_citizen_auto_player_squad",
	"sv_allowcslua",
	"mp_falldamage",
	"gmod_suit",
	"sbox_weapons",
	"sbox_godmode",
	"sbox_playershurtplayers",
	"sbox_noclip",
}

-- Each setting: setting[name] -> { min, max, guard (its privilege) }, and
-- for name, setting in SETTINGS() walks them by name.
SETTINGS = ConfigStore.New("the settings the menus may change")

-- The AI War and NextSoldier.
SETTINGS:Range("mp_aiwar_team_size", Slots.CUSTOM_SIZE, AiWar.TEAM_SIZE_MAX, NEXTSOLDIER)
SETTINGS:Switch("ws_aiwar_debug_full", NEXTSOLDIER)
SETTINGS:Switch("ns_squads_auto_enabled", NEXTSOLDIER)
SETTINGS:Switch("ns_soldiers_paused", NEXTSOLDIER)
SETTINGS:Range("ns_squads_min", 1, 8, NEXTSOLDIER)
SETTINGS:Range("ns_squads_max", 1, 8, NEXTSOLDIER)
SETTINGS:Range("ws_nodegraph_max_nodes", 64, 8192, NEXTSOLDIER)

-- Gameplay rules: winning, bonus rounds, teams, votes and reports, respawns.
SETTINGS:Range("mp_winlimit", 0, 100, RULES)
SETTINGS:Range("mp_maxrounds", 0, 100, RULES)
SETTINGS:Range("mp_timelimit", 0, 1440, RULES)
SETTINGS:Switch("mp_match_end_at_timelimit", RULES)
SETTINGS:Switch("mp_stalemate_enable", RULES)
SETTINGS:Switch("mp_deathmatch_enable", RULES)
SETTINGS:Range("mp_stalemate_timelimit", 0, 1200, RULES)
SETTINGS:Range("mp_round_fraglimit", 0, 1000, RULES)
SETTINGS:Range("mp_round_cashlimit", 0, 1000000, RULES)
SETTINGS:Range("mp_bonusroundtime", 5, 15, RULES)
SETTINGS:Switch("mp_autoteambalance", RULES)
SETTINGS:Range("mp_teams_unbalance_limit", 0, 30, RULES)
SETTINGS:Switch("mp_scrambleteams_auto", RULES)
SETTINGS:Range("mp_scrambleteams_auto_windifference", 1, 10, RULES)
SETTINGS:Switch("mp_allowspectators", RULES)
SETTINGS:Switch("mp_friendlyfire", RULES)
SETTINGS:Range("mp_reports_kick_count", 1, 32, RULES)
SETTINGS:Switch("mp_vote_map_enabled", RULES)
SETTINGS:Switch("mp_vote_reset_enabled", RULES)
SETTINGS:Switch("mp_vote_scramble_enabled", RULES)
SETTINGS:Switch("mp_vote_support_enabled", RULES)
SETTINGS:Switch("mp_vote_difficulty_enabled", RULES)
SETTINGS:Range("mp_vote_duration", 5, 120, RULES)
SETTINGS:Range("mp_vote_cooldown", 0, 3600, RULES)
SETTINGS:Range("mp_respawnwavetime", 0, 60, RULES)

-- Round control.
SETTINGS:Range("mp_round_reward_money", 0, 100000, Permissions.ROUND)

-- The C menu's Economy menu, for superadmins.
SETTINGS:Switch("mp_economy_enabled", ECONOMY)
SETTINGS:Switch("mp_economy_credit_enabled", ECONOMY)

-- The C menu's Gameplay menu, for superadmins.
SETTINGS:Switch("mp_tampering_enabled", GAMEPLAY)
SETTINGS:Switch("ns_soldiers_enabled", GAMEPLAY)
SETTINGS:Switch("tf_weapon_criticals", GAMEPLAY)
SETTINGS:Switch("tf_use_fixed_weaponspreads", GAMEPLAY)
SETTINGS:Switch("sv_gameplay_disable_sandbox", GAMEPLAY)
SETTINGS:Switch("sv_gameplay_enabled", GAMEPLAY)

-- GMod's NPCs and Server menus' options, behind server_options.
for i = 1, #PROXIED do SETTINGS:Switch(PROXIED[i], Permissions.SERVER_OPTIONS) end

-- Whether a player holding the privileges holds(name) answers for may
-- change the setting name; false for anything not a setting.
function Allowed(name, holds)
	return SETTINGS:Allowed(name, holds)
end

-- The convar's text for the value text names, rounded to a whole number;
-- or nil and why it is refused.
function Parse(name, text)
	return SETTINGS:Parse(name, text)
end
