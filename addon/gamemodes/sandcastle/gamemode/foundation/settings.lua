-- The server convars the menus may set: the Options and Utilities panels,
-- the C menu's bar (its Economy and Gameplay menus, and GMod's own NPCs and
-- Server menus, which on a dedicated server work only for the listen host),
-- and the AI War panel. A client cannot set a server's convar itself
-- ("Can't change replicated ConVar ... from console of client"), so a menu
-- sends ws_server_set name value, and the server sets it for a holder of the
-- setting's privilege (foundation.permissions), after Parse holds the value
-- to the range the menu's control offers. Every setting is an integer.
local floor, format, tonumber = math.floor, string.format, tonumber
local AiWar = require("foundation.aiwar")
local Slots = require("foundation.aiwar.slots")
local Permissions = require("foundation.permissions")
module(...)

local RULES = Permissions.RULES
local NEXTSOLDIER = Permissions.NEXTSOLDIER

local function Switch(privilege)
	return {
		min = 0,
		max = 1,
		privilege = privilege,
	}
end

local function Range(min, max, privilege)
	return {
		min = min,
		max = max,
		privilege = privilege,
	}
end

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

SETTINGS = {
	-- The AI War and NextSoldier.
	mp_aiwar_team_size = Range(Slots.CUSTOM_SIZE, AiWar.TEAM_SIZE_MAX, NEXTSOLDIER),
	ws_aiwar_debug_full = Switch(NEXTSOLDIER),
	ns_squads_auto_enabled = Switch(NEXTSOLDIER),
	ns_soldiers_paused = Switch(NEXTSOLDIER),
	ns_squads_min = Range(1, 8, NEXTSOLDIER),
	ns_squads_max = Range(1, 8, NEXTSOLDIER),
	ws_nodegraph_max_nodes = Range(64, 8192, NEXTSOLDIER),

	-- Gameplay rules: winning, bonus rounds, teams, votes and reports, respawns.
	mp_winlimit = Range(0, 100, RULES),
	mp_maxrounds = Range(0, 100, RULES),
	mp_timelimit = Range(0, 1440, RULES),
	mp_match_end_at_timelimit = Switch(RULES),
	mp_stalemate_enable = Switch(RULES),
	mp_stalemate_timelimit = Range(0, 1200, RULES),
	mp_round_fraglimit = Range(0, 1000, RULES),
	mp_round_cashlimit = Range(0, 1000000, RULES),
	mp_bonusroundtime = Range(5, 15, RULES),
	mp_autoteambalance = Switch(RULES),
	mp_teams_unbalance_limit = Range(0, 30, RULES),
	mp_scrambleteams_auto = Switch(RULES),
	mp_scrambleteams_auto_windifference = Range(1, 10, RULES),
	mp_allowspectators = Switch(RULES),
	mp_reports_kick_count = Range(1, 32, RULES),
	mp_vote_map_enabled = Switch(RULES),
	mp_vote_reset_enabled = Switch(RULES),
	mp_vote_scramble_enabled = Switch(RULES),
	mp_vote_support_enabled = Switch(RULES),
	mp_vote_difficulty_enabled = Switch(RULES),
	mp_vote_duration = Range(5, 120, RULES),
	mp_vote_cooldown = Range(0, 3600, RULES),
	mp_respawnwavetime = Range(0, 60, RULES),

	-- The C menu's Economy menu, for superadmins.
	mp_economy_enabled = Switch(Permissions.ECONOMY),
	mp_economy_credit_enabled = Switch(Permissions.ECONOMY),

	-- The C menu's Gameplay menu, for superadmins.
	mp_tampering_enabled = Switch(Permissions.GAMEPLAY),
	ns_soldiers_enabled = Switch(Permissions.GAMEPLAY),
	tf_weapon_criticals = Switch(Permissions.GAMEPLAY),
	tf_use_fixed_weaponspreads = Switch(Permissions.GAMEPLAY),
	sv_gameplay_disable_sandbox = Switch(Permissions.GAMEPLAY),
	sv_gameplay_enabled = Switch(Permissions.GAMEPLAY),
}

for i = 1, #PROXIED do SETTINGS[PROXIED[i]] = Switch(Permissions.SERVER_OPTIONS) end

-- Whether a player holding the privileges holds(name) answers for may
-- change the setting name; false for anything not a setting.
function Allowed(name, holds)
	local setting = SETTINGS[name]
	return setting ~= nil and holds(setting.privilege) == true
end

-- The convar's text for the value text names, rounded to a whole number;
-- or nil and why it is refused.
function Parse(name, text)
	local setting = SETTINGS[name]
	if not setting then return nil, format("%s is not a setting the menu may change", name) end
	local number = tonumber(text)
	if not number then return nil, format("%s takes a number, not %q", name, text) end
	local value = floor(number + 0.5)
	if value < setting.min or value > setting.max then
		return nil, format("%s takes %d to %d", name, setting.min, setting.max)
	end
	return format("%d", value)
end
