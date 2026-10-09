-- Shared definitions for the TF2 map entities. Team numbers and round states
-- keep TF2's values (foundation.teams, foundation.rounds.state) so map keyvalues
-- (TeamNum) mean the same thing here.
WETSAND = WETSAND or {}

-- Lua 5.1's require for the gamemode's module(...) files (gamemode/foundation/):
-- GMod's include passes no name to the chunk, so load it here, once, calling
-- it with the dotted name. Above its module(...) call the chunk sees this
-- require (GMod's own looks only in includes/modules/), to load its siblings.
-- GM exists only while the gamemode loads.
local GAMEMODE_ROOT = GM.FolderName .. "/gamemode/"
local CHUNK_ENV = setmetatable({}, { __index = _G })

function WETSAND.require(name)
	if package.loaded[name] == nil then
		local chunk = CompileFile(GAMEMODE_ROOT .. name:gsub("%.", "/") .. ".lua")
		setfenv(chunk, CHUNK_ENV)(name)
	end
	return package.loaded[name]
end
CHUNK_ENV.require = WETSAND.require

-- The game event library (WETSAND.Events), which everything after this
-- line may use; shared.lua skips it among the other sh_ files.
include("sh_events.lua")

-- The gamemode's convars are replicated and notify (foundation.replicated),
-- so a client's console knows every one: from here on, a convar the
-- gamemode's own files create gets FCVAR_REPLICATED and FCVAR_NOTIFY on
-- both realms (other addons' are
-- left as they are), and the server tells each ready client the ones only
-- it has (server_convars), which the client creates too.
do
	local Replicated = WETSAND.require("foundation.replicated")
	local E = WETSAND.Events
	local FOLDER = GM.FolderName
	local CONVAR_BITS = 12
	local CreateEngineConVar = CreateConVar
	local ADDED = Replicated.Added(FCVAR_REPLICATED, FCVAR_NOTIFY)
	local created = {} -- server: the gamemode's convars, in creation order
	local pending -- server: those created since the last tell

	E.Define("server_convars", {
		convars = E.List(E.Record({
			name = E.String(),
			value = E.String(),
			help = E.String(),
		}), CONVAR_BITS),
	})

	local function Records(names)
		local records = {}
		for i, name in ipairs(names) do
			local cvar = GetConVar(name)
			records[i] = { name = name, value = cvar:GetString(), help = cvar:GetHelpText() }
		end
		return records
	end

	function CreateConVar(name, default, flags, help, min, max)
		-- CreateClientConVar's tail call leaves its caller as the source
		local source = debug.getinfo(2, "S").source
		if not Replicated.Ours(source, FOLDER) or (CLIENT and Replicated.ClientOnly(source)) then
			return CreateEngineConVar(name, default, flags, help, min, max)
		end
		local cvar = CreateEngineConVar(name, default, Replicated.Flags(flags, ADDED), help, min, max)
		if SERVER and cvar then
			created[#created + 1] = name
			-- a feature that loads later creates its convars in one go: one tell
			if not pending then
				pending = {}
				timer.Simple(0, function()
					E.Fire("server_convars", { convars = Records(pending) })
					pending = nil
				end)
			end
			pending[#pending + 1] = name
		end
		return cvar
	end

	if SERVER then
		E.Listen("client_ready", "wetsand_server_convars", function(_, ply)
			E.Fire("server_convars", { convars = Records(created) }, ply)
		end)
	else
		E.Listen("server_convars", "wetsand_server_convars", function(fields)
			for _, c in ipairs(fields.convars) do
				if not ConVarExists(c.name) then CreateConVar(c.name, c.value, FCVAR_REPLICATED, c.help) end
			end
		end)
	end
end

-- Per-map features (foundation.features): an entity calls WETSAND.Feature on
-- first use, never at file top level, so a map loads only the controllers
-- and views its entities pull in. The server tells ready clients each new
-- feature with a client part (feature_load), and a joining client, once
-- ready (client_ready), every one loaded so far, in load order.
local Features = WETSAND.require("foundation.features")
local FEATURE_COUNT_BITS = 16

WETSAND.Events.Define("feature_load", {
	names = WETSAND.Events.List(WETSAND.Events.String(), FEATURE_COUNT_BITS),
})

local FeatureFiles = {}

function FeatureFiles:Exists(path)
	return file.Exists(GAMEMODE_ROOT .. path, "LUA")
end

-- CompileFile rather than include, so an error in the file reaches the
-- caller. CompileFile prints a syntax error itself and returns no function.
function FeatureFiles:Run(path)
	local chunk = CompileFile(GAMEMODE_ROOT .. path)
	if not isfunction(chunk) then error(path .. " did not compile", 0) end
	return chunk()
end

-- To every ready client.
function FeatureFiles:TellClients(name)
	WETSAND.Events.Fire("feature_load", { names = { name } })
end

-- Kept across a Lua refresh, since entities hold the controllers it returned.
WETSAND.FeatureLoader = WETSAND.FeatureLoader
	or Features.New(SERVER and Features.SERVER or Features.CLIENT, FeatureFiles)

-- The server's controller or the client's view for a feature, loaded once.
function WETSAND.Feature(name)
	return WETSAND.FeatureLoader:Feature(name)
end

-- Whether this map has loaded the feature, without loading it.
function WETSAND.FeatureLoaded(name)
	return WETSAND.FeatureLoader:IsLoaded(name)
end

-- collectgarbage("count") before and after a full collection, and the loaded
-- features, to compare maps' Lua RAM.
local function MemoryReport()
	local count = collectgarbage("count")
	collectgarbage("collect")
	return WETSAND.FeatureLoader:MemoryReport(count, collectgarbage("count"))
end

if SERVER then
	WETSAND.Events.Listen("client_ready", "wetsand_feature_load", function(_, ply)
		WETSAND.Events.Fire("feature_load", { names = WETSAND.FeatureLoader:ClientFeatures() }, ply)
	end)

	-- A full collection stalls the server, so players need admin.
	concommand.Add("wetsand_memory", function(ply)
		if IsValid(ply) and not ply:IsAdmin() then return end
		local report = MemoryReport()
		print(report)
		if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, report) end
	end, nil, "Print the server's Lua memory and the features this map loaded")
else
	WETSAND.Events.Listen("feature_load", "wetsand_feature_load", function(fields)
		for _, name in ipairs(fields.names) do WETSAND.Feature(name) end
	end)

	concommand.Add("wetsand_memory_cl", function()
		print(MemoryReport())
	end, nil, "Print this client's Lua memory and the features it loaded")
end

-- Pure rule libraries (gamemode/foundation/), shared so client prediction and
-- drawing follow the same rules as the server.
WETSAND.TeamRules = WETSAND.require("foundation.teams")
WETSAND.PlayerRules = WETSAND.require("foundation.players")

-- TF2's team numbers and round states, as the rule libraries define them.
local Teams = WETSAND.TeamRules
WETSAND.TEAM_UNASSIGNED = Teams.UNASSIGNED
WETSAND.TEAM_SPECTATOR = Teams.SPECTATOR
WETSAND.TEAM_RED = Teams.RED
WETSAND.TEAM_BLUE = Teams.BLUE
WETSAND.TEAM_HALLOWEEN = Teams.HALLOWEEN
WETSAND.STATE = WETSAND.require("foundation.rounds.state")

WETSAND.TeamName = {
	[Teams.UNASSIGNED] = "Nobody",
	[Teams.SPECTATOR] = "Spectator",
	[Teams.RED] = "RED",
	[Teams.BLUE] = "BLU",
}
WETSAND.TeamColor = {
	[Teams.UNASSIGNED] = Color(220, 220, 220),
	[Teams.RED] = Color(189, 59, 59),
	[Teams.BLUE] = Color(91, 122, 140),
}

local PLAYABLE = { [WETSAND.TEAM_RED] = true, [WETSAND.TEAM_BLUE] = true }

function WETSAND.TeamOf(ent)
	if not IsValid(ent) then return WETSAND.TEAM_UNASSIGNED end
	local t = ent:Team()
	if PLAYABLE[t] then return t end
	return WETSAND.TEAM_UNASSIGNED
end

function WETSAND.EnemyOf(team)
	if team == WETSAND.TEAM_RED then return WETSAND.TEAM_BLUE end
	if team == WETSAND.TEAM_BLUE then return WETSAND.TEAM_RED end
	return WETSAND.TEAM_UNASSIGNED
end

function WETSAND.Active()
	return GetGlobal2Bool("wetsand_rounds_active", false)
end

function WETSAND.State()
	return GetGlobal2Int("wetsand_round_state", WETSAND.STATE.INIT)
end

-- Setup and overtime, as the rounds controller publishes them, so filters
-- and the AI war read them on any map (false without rounds).
function WETSAND.InSetup()
	return GetGlobal2Bool("wetsand_round_in_setup", false)
end

function WETSAND.InOvertime()
	return GetGlobal2Bool("wetsand_round_overtime", false)
end

-- The rounds halted, as in Sandbox mode (foundation.gamemode) and its
-- countdown to Gameplay mode: the rounds and timers stand still and the map
-- plays like Sandbox, its spawn doors and forcefields open to everyone.
function WETSAND.GameplayStopped()
	return GetGlobal2Bool("wetsand_gameplay_halted", false)
end

-- TF2's convar; the map's SetRoundRespawnFreezeEnabled input sets it.
-- Replicated, so client prediction freezes too.
WETSAND.RestartFreeze = CreateConVar("tf_player_movement_restart_freeze", "1", FCVAR_REPLICATED,
	"When set, prevent player movement during round restart")

-- TF2's convar (teamplayroundbased_gamerules.cpp), replicated as there, so the
-- team menu disables the teams the server would refuse.
-- TF2's join convars, replicated so the team menu offers what the server
-- allows (CTFPlayer::HandleCommand_JoinTeam).
WETSAND.ForceAutoTeam = CreateConVar("mp_forceautoteam", "0", { FCVAR_REPLICATED, FCVAR_NOTIFY },
	"Automatically assign players to teams when joining.", 0, 1)
WETSAND.AllowSpectators = CreateConVar("mp_allowspectators", "1", { FCVAR_REPLICATED, FCVAR_NOTIFY },
	"toggles whether the server allows spectator mode or not", 0, 1)
WETSAND.UnbalanceLimit = CreateConVar("mp_teams_unbalance_limit", "1", FCVAR_REPLICATED,
	"Teams are unbalanced when one team has this many more players than the other team. (0 disables check)", 0, 30)

-- Who won what the state celebrates: the match (GAME_OVER), else the round.
function WETSAND.Winner(state)
	if state == WETSAND.STATE.GAME_OVER then return GetGlobal2Int("wetsand_match_winner", WETSAND.TEAM_UNASSIGNED) end
	return GetGlobal2Int("wetsand_round_winner", WETSAND.TEAM_UNASSIGNED)
end

-- The input restrictions of the round states: during pre-round players may
-- look around and shoot but not move (CTFPlayer::CanPlayerMove); the losing
-- team cannot attack while the winners celebrate (TF2's humiliation).
function WETSAND.RestrictCommand(ply, cmd)
	WETSAND.RestrictStunned(ply, cmd)
	local state = WETSAND.State()
	if state == WETSAND.STATE.PREROUND then
		if not WETSAND.RestartFreeze:GetBool() then return end
		cmd:ClearMovement()
		cmd:RemoveKey(IN_JUMP)
		cmd:RemoveKey(IN_DUCK)
	elseif WETSAND.TeamRules.Humiliated(state, WETSAND.Winner(state), WETSAND.TeamOf(ply)) then
		cmd:RemoveKey(IN_ATTACK)
		cmd:RemoveKey(IN_ATTACK2)
	end
end

-- A stun's control effects (CTFPlayerShared::StunPlayer): TF_STUN_CONTROLS
-- takes movement and attacks, TF_STUN_LOSER_STATE attacks. The server sets
-- the NW2 vars (sv_teams_conditions.lua).
function WETSAND.RestrictStunned(ply, cmd)
	if CurTime() >= ply:GetNW2Float("wetsand_stun_end_time", 0) then return end
	local flags = ply:GetNW2Int("wetsand_stun_flags", 0)
	local STUN = WETSAND.PlayerRules.STUN
	if bit.band(flags, STUN.CONTROLS) ~= 0 then
		cmd:ClearMovement()
		cmd:RemoveKey(IN_JUMP)
	end
	if bit.band(flags, STUN.CONTROLS + STUN.LOSER_STATE) ~= 0 then
		cmd:RemoveKey(IN_ATTACK)
		cmd:RemoveKey(IN_ATTACK2)
	end
end

-- Speed boost, a stun's slow and the move speed attributes (the attributes
-- controller's wetsand_speed_scale) on the player's top speed, predicted on
-- both realms (TeamFortress_CalculateMaxSpeed, CTFGameMovement).
hook.Add("SetupMove", "wetsand_conditions", function(ply, mv)
	local boost = ply:GetNW2Bool("wetsand_speed_boosted", false)
	local scale = ply:GetNW2Float("wetsand_speed_scale", 1)
	local reduction = 0
	if CurTime() < ply:GetNW2Float("wetsand_stun_end_time", 0) then reduction = ply:GetNW2Float("wetsand_stun_speed_reduction", 0) end
	if not boost and reduction == 0 and scale == 1 then return end
	local speed = WETSAND.PlayerRules.MaxSpeed(mv:GetMaxClientSpeed(), boost, reduction, scale)
	mv:SetMaxClientSpeed(speed)
	mv:SetMaxSpeed(speed)
end)
