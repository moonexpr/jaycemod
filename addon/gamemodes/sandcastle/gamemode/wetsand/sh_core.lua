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

-- Per-map features (foundation.features): an entity calls WETSAND.Feature on
-- first use, never at file top level, so a map loads only the controllers
-- and views its entities pull in. The server tells ready clients each new
-- feature with a client part, and a joining client, once ready, every one
-- loaded so far, in load order. Both directions use one net message: from a
-- client it means "ready", from the server a list of features to load.
local Features = WETSAND.require("foundation.features")
local FEATURE_NET = "wetsand_feature_load"
local FEATURE_COUNT_BITS = 16

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

local function ReadyPlayers()
	local ready = {}
	for _, ply in ipairs(player.GetAll()) do
		if ply.wetsandFeaturesReady then ready[#ready + 1] = ply end
	end
	return ready
end

local function SendFeatures(names, recipients)
	net.Start(FEATURE_NET)
	net.WriteUInt(#names, FEATURE_COUNT_BITS)
	for _, name in ipairs(names) do net.WriteString(name) end
	net.Send(recipients)
end

function FeatureFiles:TellClients(name)
	local ready = ReadyPlayers()
	if #ready > 0 then SendFeatures({ name }, ready) end
end

-- Kept across a Lua refresh, since entities hold the controllers it returned.
WETSAND.FeatureLoader = WETSAND.FeatureLoader
	or Features.New(SERVER and Features.SERVER or Features.CLIENT, FeatureFiles)

-- The server's controller or the client's view for a feature, loaded once.
function WETSAND.Feature(name)
	return WETSAND.FeatureLoader:Feature(name)
end

-- collectgarbage("count") before and after a full collection, and the loaded
-- features, to compare maps' Lua RAM.
local function MemoryReport()
	local count = collectgarbage("count")
	collectgarbage("collect")
	return WETSAND.FeatureLoader:MemoryReport(count, collectgarbage("count"))
end

if SERVER then
	util.AddNetworkString(FEATURE_NET)

	net.Receive(FEATURE_NET, function(_, ply)
		ply.wetsandFeaturesReady = true
		SendFeatures(WETSAND.FeatureLoader:ClientFeatures(), ply)
	end)

	-- A full collection stalls the server, so players need admin.
	concommand.Add("wetsand_memory", function(ply)
		if IsValid(ply) and not ply:IsAdmin() then return end
		local report = MemoryReport()
		print(report)
		if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, report) end
	end, nil, "Print the server's Lua memory and the features this map loaded")
else
	net.Receive(FEATURE_NET, function()
		local names = {}
		for i = 1, net.ReadUInt(FEATURE_COUNT_BITS) do names[i] = net.ReadString() end
		for _, name in ipairs(names) do WETSAND.Feature(name) end
	end)

	-- Net messages reach the client from InitPostEntity on.
	hook.Add("InitPostEntity", "wetsand_feature_load", function()
		net.Start(FEATURE_NET)
		net.SendToServer()
	end)

	concommand.Add("wetsand_memory_cl", function()
		print(MemoryReport())
	end, nil, "Print this client's Lua memory and the features it loaded")

	-- WETSAND.BroadcastSound's game sounds (announcer lines, win and lose
	-- music), played as the local player's own on every map, rounds or not.
	net.Receive("wetsand_pa_sound_file", function()
		local ply = LocalPlayer()
		if IsValid(ply) then ply:EmitSound(net.ReadString()) end
	end)
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
WETSAND.UnbalanceLimit = CreateConVar("mp_teams_unbalance_limit", "1", FCVAR_REPLICATED,
	"Teams are unbalanced when one team has this many more players than the other team. (0 disables check)", 0, 30)

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
	elseif state == WETSAND.STATE.TEAM_WIN then
		local winner = GetGlobal2Int("wetsand_round_winner", WETSAND.TEAM_UNASSIGNED)
		if winner ~= WETSAND.TEAM_UNASSIGNED and WETSAND.TeamOf(ply) ~= winner then
			cmd:RemoveKey(IN_ATTACK)
			cmd:RemoveKey(IN_ATTACK2)
		end
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

-- Speed boost and a stun's slow on the player's top speed, predicted on
-- both realms (TeamFortress_CalculateMaxSpeed, CTFGameMovement).
hook.Add("SetupMove", "wetsand_conditions", function(ply, mv)
	local boost = ply:GetNW2Bool("wetsand_speed_boosted", false)
	local reduction = 0
	if CurTime() < ply:GetNW2Float("wetsand_stun_end_time", 0) then reduction = ply:GetNW2Float("wetsand_stun_speed_reduction", 0) end
	if not boost and reduction == 0 then return end
	local speed = WETSAND.PlayerRules.MaxSpeed(mv:GetMaxClientSpeed(), boost, reduction)
	mv:SetMaxClientSpeed(speed)
	mv:SetMaxSpeed(speed)
end)
