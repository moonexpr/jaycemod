-- Who may do what. Every admin control is a named privilege with a default
-- rank. ws/sh_permissions.lua registers them with CAMI, the common admin mod
-- interface, so ULX, SAM or ServerGuard can hand any of them to any rank;
-- with no admin mod, CAMI's own fallback applies the default rank. Who holds
-- a privilege is therefore the admin mod's answer, passed in as holds(name).
-- This model adds only what a rank cannot express:
-- - Sandbox mode lets everyone spawn.
-- - With gameplay tampering switched off (mp_tampering_enabled 0), no player
--   may tamper, superadmins included; a holder of the gameplay toggles may
--   switch it back on.
local PlayMode = require("games.system.play_mode")
local Sets = require("foundation.map.sets")
local ipairs = ipairs
module(...)

-- CAMI's MinAccess names for the three ranks it knows.
RANK_PLAYER, RANK_ADMIN, RANK_SUPERADMIN = "user", "admin", "superadmin"

ROUND = "sandcastle.round"
MATCH = "sandcastle.match"
TAMPER = "sandcastle.tamper"
NEXTSOLDIER = "sandcastle.nextsoldier"
RULES = "sandcastle.rules"
PLAYERS = "sandcastle.players"
SERVER_OPTIONS = "sandcastle.server_options"
ECONOMY = "sandcastle.economy"
GAMEPLAY = "sandcastle.gameplay"
NPC_DEBUG = "sandcastle.npc_debug"
SPAWN = "sandcastle.spawn"
BUILD = "sandcastle.build"

-- Why a privilege is refused.
REASON_RANK = "rank"
REASON_TAMPERING_OFF = "tampering_off"

-- In registration order, as an admin mod lists them.
PRIVILEGES = {
	{
		name = ROUND,
		rank = RANK_ADMIN,
		description = "Sandcastle: control the round (sudden death, restart, round rewards).",
	},
	{
		name = MATCH,
		rank = RANK_ADMIN,
		description = "Sandcastle: control the match (begin, stop, force a winner, editor actions).",
	},
	{
		name = TAMPER,
		rank = RANK_ADMIN,
		description = "Sandcastle: tamper with live gameplay (move the payload, change the clock, respawns).",
	},
	{
		name = NEXTSOLDIER,
		rank = RANK_ADMIN,
		description = "Sandcastle: run the AI war and its NextSoldier soldiers.",
	},
	{
		name = RULES,
		rank = RANK_ADMIN,
		description = "Sandcastle: change the gameplay rules and server settings.",
	},
	{
		name = PLAYERS,
		rank = RANK_ADMIN,
		description = "Sandcastle: kick, ban, spectate and give money to players.",
	},
	{
		name = SERVER_OPTIONS,
		rank = RANK_ADMIN,
		description = "Sandcastle: GMod's NPCs and Server menu options, on a dedicated server.",
	},
	{
		name = ECONOMY,
		rank = RANK_SUPERADMIN,
		description = "Sandcastle: switch deficit spending or the whole economy on and off.",
	},
	{
		name = GAMEPLAY,
		rank = RANK_SUPERADMIN,
		description = "Sandcastle: switch tampering, NextSoldier, criticals, spread and the modes on and off.",
	},
	{
		name = NPC_DEBUG,
		rank = RANK_SUPERADMIN,
		description = "Sandcastle: debug NextSoldier soldiers and NPCs.",
	},
	{
		name = SPAWN,
		rank = RANK_ADMIN,
		description = "Sandcastle: spawn things in Gameplay mode (everyone may in Sandbox mode).",
	},
	{
		name = BUILD,
		rank = RANK_ADMIN,
		description = "Sandcastle: place a game on any map with the game builder.",
	},
}

local NAMES = {}
for i, privilege in ipairs(PRIVILEGES) do NAMES[i] = privilege.name end
local PRIVILEGE = Sets.Named("permissions privilege", NAMES)

-- Whether the privilege name is allowed: true, or false and a REASON_.
-- holds(name) is the admin mod's answer; facts = { mode, tamperingEnabled }.
function Allows(name, holds, facts)
	PRIVILEGE:Check(name)
	if name == SPAWN and PlayMode.IsSandbox(facts.mode) then return true end
	if not holds(name) then return false, REASON_RANK end
	if name == TAMPER and not facts.tamperingEnabled then return false, REASON_TAMPERING_OFF end
	return true
end
