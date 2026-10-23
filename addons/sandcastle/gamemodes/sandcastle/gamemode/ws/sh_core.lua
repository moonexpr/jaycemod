-- Shared definitions for the TF2 map entities. Team numbers and round states
-- keep TF2's values (games.gameplay.teams, games.gameplay.rounds.state) so map keyvalues
-- (TeamNum) mean the same thing here.
-- WS and WS.require, the gamemode's require, come from shared_loader.lua,
-- which also loaded foundation's namespaces.

-- The game event library (WS.Events), which everything after this
-- line may use; shared.lua skips it among the other sh_ files.
include("sh_events.lua")

-- The gamemode's convars are replicated and notify (ws.replicated),
-- so a client's console knows every one: from here on, a convar the
-- gamemode's own files create gets FCVAR_REPLICATED and FCVAR_NOTIFY on
-- both realms (other addons' are
-- left as they are), and the server tells each ready client the ones only
-- it has (system_server_convars), which the client creates too.
do
	local Replicated = WS.require("ws.replicated")
	local E = WS.Events
	local FOLDER = GM.FolderName
	local CONVAR_BITS = 12
	local CreateEngineConVar = CreateConVar
	local ADDED = Replicated.Added(FCVAR_REPLICATED, FCVAR_NOTIFY)
	local created = {} -- server: the gamemode's convars, in creation order
	local pending -- server: those created since the last tell

	E.Define("system_server_convars", {
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
					E.Fire("system_server_convars", { convars = Records(pending) })
					pending = nil
				end)
			end
			pending[#pending + 1] = name
		end
		return cvar
	end

	if SERVER then
		E.Listen("system_client_ready", "ws_server_convars", function(_, ply)
			E.Fire("system_server_convars", { convars = Records(created) }, ply)
		end)
	else
		E.Listen("system_server_convars", "ws_server_convars", function(fields)
			for _, c in ipairs(fields.convars) do
				if not ConVarExists(c.name) then CreateConVar(c.name, c.value, FCVAR_REPLICATED, c.help) end
			end
		end)
	end
end

-- Per-map features (games.system.features): an entity calls WS.Feature on
-- first use, never at file top level, so a map loads only the controllers
-- and views its entities pull in. The server tells ready clients each new
-- feature with a client part (system_feature_load), and a joining client, once
-- ready (system_client_ready), every one loaded so far, in load order.
-- The HUD (client): every HUD element of the gamemode is a callback on
-- WS.HUD (games.list.drawlist) named by its place in a tree (game.match.
-- team_scores.blue_score; game.objective.*, game.notices.*, player.*,
-- debug.*), drawn by GM:HUDPaint in its band of HUD_ORDER, bottom first.
-- Code hides a branch with WS.HUD:HideElements(path) (a win screen hides
-- game.match.team_scores) and shows it with ShowElements; the player with
-- cl_hud_hidden, and cl_hud_print lists them (ws/cl_hud_hidden.lua). Made
-- here, before any module can add to it.
if CLIENT then
	WS.HUD = WS.require("games.list.drawlist").New()
	WS.HUD_ORDER = {
		WORLD = 100, -- over the world: damage numbers
		OBJECTIVES = 200, -- points, flags, carts, KOTH clocks
		ROUND = 300, -- the round's timer, scores and panels
		NOTICES = 400, -- votes, voices, the spectator's names, bosses, spells
		OVERLAY = 500, -- over every other: why you are not spawning
		DEBUG = 900, -- debug overlays
	}
end

local Features = WS.require("games.system.features")
local FEATURE_COUNT_BITS = 16

WS.Events.Define("system_feature_load", {
	names = WS.Events.List(WS.Events.String(), FEATURE_COUNT_BITS),
})

local FeatureFiles = {}

function FeatureFiles:Exists(path)
	return file.Exists(GAMEMODE_ROOT .. path, "LUA")
end

-- CompileFile rather than include, so an error in the file reaches the
-- caller. CompileFile prints a syntax error itself and returns no function:
-- the file's chunk, or nil.
function FeatureFiles:Compile(path)
	local chunk = CompileFile(GAMEMODE_ROOT .. path)
	if isfunction(chunk) then return chunk end
end

function FeatureFiles:Run(path)
	local chunk = self:Compile(path)
	if not chunk then error(path .. " did not compile", 0) end
	return chunk()
end

-- To every ready client.
function FeatureFiles:TellClients(name)
	WS.Events.Fire("system_feature_load", { names = { name } })
end

-- Kept across a Lua refresh, since entities hold the controllers it returned.
WS.FeatureLoader = WS.FeatureLoader
	or Features.New(SERVER and Features.SERVER or Features.CLIENT, FeatureFiles)

-- The server's controller or the client's view for a feature, loaded once.
function WS.Feature(name)
	return WS.FeatureLoader:Feature(name)
end

-- A realm root's part runner (games.system.features Parts): the root calls
-- local Part = WS.FeatureParts(getfenv(1), "<its feature>"), then
-- Part("sv_<part>", ...) for each part in order. getfenv(1), not the
-- helper's getfenv(2), so a tail call cannot lose hot swap's stubbed env.
function WS.FeatureParts(env, name)
	return Features.Parts(FeatureFiles, env, name)
end

-- Whether this map has loaded the feature, without loading it.
function WS.FeatureLoaded(name)
	return WS.FeatureLoader:IsLoaded(name)
end

-- collectgarbage("count") before and after a full collection, and the loaded
-- features, to compare maps' Lua RAM.
local function MemoryReport()
	local count = collectgarbage("count")
	collectgarbage("collect")
	return WS.FeatureLoader:MemoryReport(count, collectgarbage("count"))
end

if SERVER then
	WS.Events.Listen("system_client_ready", "ws_feature_load", function(_, ply)
		WS.Events.Fire("system_feature_load", { names = WS.FeatureLoader:ClientFeatures() }, ply)
	end)

	-- A full collection stalls the server, so players need the rules privilege.
	concommand.Add("ws_memory", function(ply)
		if not WS.Can(ply, WS.require("games.system.permissions").RULES) then return end
		local report = MemoryReport()
		print(report)
		if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, report) end
	end, nil, "Print the server's Lua memory and the features this map loaded")
else
	WS.Events.Listen("system_feature_load", "ws_feature_load", function(fields)
		for _, name in ipairs(fields.names) do WS.Feature(name) end
	end)

	concommand.Add("ws_memory_cl", function()
		print(MemoryReport())
	end, nil, "Print this client's Lua memory and the features it loaded")
end

-- Pure rule libraries (gamemode/foundation/), shared so client prediction and
-- drawing follow the same rules as the server.
WS.TeamRules = WS.require("games.gameplay.teams")
WS.PlayerRules = WS.require("games.gameplay.players")

-- TF2's team numbers and round states, as the rule libraries define them.
local Teams = WS.TeamRules
WS.TEAM_UNASSIGNED = Teams.UNASSIGNED
WS.TEAM_SPECTATOR = Teams.SPECTATOR
WS.TEAM_RED = Teams.RED
WS.TEAM_BLUE = Teams.BLUE
WS.TEAM_HALLOWEEN = Teams.HALLOWEEN
WS.STATE = WS.require("games.gameplay.rounds.state")

WS.TeamName = {
	[Teams.UNASSIGNED] = "Nobody",
	[Teams.SPECTATOR] = "Spectator",
	[Teams.RED] = "RED",
	[Teams.BLUE] = "BLU",
}
WS.TeamColor = {
	[Teams.UNASSIGNED] = Color(220, 220, 220),
	[Teams.RED] = Color(189, 59, 59),
	[Teams.BLUE] = Color(91, 122, 140),
}

local PLAYABLE = { [WS.TEAM_RED] = true, [WS.TEAM_BLUE] = true }

function WS.TeamOf(ent)
	if not IsValid(ent) then return WS.TEAM_UNASSIGNED end
	local t = ent:Team()
	if PLAYABLE[t] then return t end
	return WS.TEAM_UNASSIGNED
end

-- Teams.EnemyOf, with TEAM_UNASSIGNED for a team that does not play.
function WS.EnemyOf(team)
	return WS.TeamRules.EnemyOf(team) or WS.TEAM_UNASSIGNED
end

function WS.Active()
	return GetGlobal2Bool("ws_rounds_active", false)
end

function WS.State()
	return GetGlobal2Int("ws_round_state", WS.STATE.INIT)
end

-- Setup and overtime, as the rounds controller publishes them, so filters
-- and the AI war read them on any map (false without rounds).
function WS.InSetup()
	return GetGlobal2Bool("ws_round_in_setup", false)
end

function WS.InOvertime()
	return GetGlobal2Bool("ws_round_overtime", false)
end

-- The rounds halted, as in Sandbox mode (games.system.gamemode) and its
-- countdown to Gameplay mode: the rounds and timers stand still and the map
-- plays like Sandbox, its spawn doors and forcefields open to everyone.
function WS.GameplayStopped()
	return GetGlobal2Bool("ws_gameplay_halted", false)
end

-- Whether players watch as observers and pick teams now (games.gameplay.teams'
-- TeamPlay): rounds, in Gameplay mode, past INIT.
function WS.TeamPlay()
	return Teams.TeamPlay(WS.Active(), WS.GameplayStopped(), WS.State())
end

-- TF2's convar; the map's SetRoundRespawnFreezeEnabled input sets it.
-- Replicated, so client prediction freezes too.
WS.RestartFreeze = CreateConVar("tf_player_movement_restart_freeze", "1", FCVAR_REPLICATED,
	"When set, prevent player movement during round restart")

-- TF2's convar (teamplayroundbased_gamerules.cpp), replicated as there, so the
-- team menu disables the teams the server would refuse.
-- TF2's join convars, replicated so the team menu offers what the server
-- allows (CTFPlayer::HandleCommand_JoinTeam).
WS.ForceAutoTeam = CreateConVar("mp_forceautoteam", "0", { FCVAR_REPLICATED, FCVAR_NOTIFY },
	"Automatically assign players to teams when joining.", 0, 1)
WS.AllowSpectators = CreateConVar("mp_allowspectators", "1", { FCVAR_REPLICATED, FCVAR_NOTIFY },
	"toggles whether the server allows spectator mode or not", 0, 1)
WS.UnbalanceLimit = CreateConVar("mp_teams_unbalance_limit", "1", FCVAR_REPLICATED,
	"Teams are unbalanced when one team has this many more players than the other team. (0 disables check)", 0, 30)

-- Who won what the state celebrates: the match (GAME_OVER), else the round.
function WS.Winner(state)
	if state == WS.STATE.GAME_OVER then return GetGlobal2Int("ws_match_winner", WS.TEAM_UNASSIGNED) end
	return GetGlobal2Int("ws_round_winner", WS.TEAM_UNASSIGNED)
end

-- The input restrictions of the round states: during pre-round players may
-- look around and shoot but not move (CTFPlayer::CanPlayerMove); a bonus
-- round's opening freeze (ws_bonus_freeze_end) takes their attacks too; the
-- losing team cannot attack while the winners celebrate (TF2's humiliation).
function WS.RestrictCommand(ply, cmd)
	WS.RestrictStunned(ply, cmd)
	if CurTime() < GetGlobal2Float("ws_bonus_freeze_end", 0) then
		cmd:ClearMovement()
		cmd:RemoveKey(IN_JUMP)
		cmd:RemoveKey(IN_DUCK)
		cmd:RemoveKey(IN_ATTACK)
		cmd:RemoveKey(IN_ATTACK2)
		return
	end
	local state = WS.State()
	if state == WS.STATE.PREROUND then
		if not WS.RestartFreeze:GetBool() then return end
		cmd:ClearMovement()
		cmd:RemoveKey(IN_JUMP)
		cmd:RemoveKey(IN_DUCK)
	elseif WS.TeamRules.Humiliated(state, WS.Winner(state), WS.TeamOf(ply)) then
		cmd:RemoveKey(IN_ATTACK)
		cmd:RemoveKey(IN_ATTACK2)
	end
end

-- A stun's control effects (CTFPlayerShared::StunPlayer): TF_STUN_CONTROLS
-- takes movement and attacks, TF_STUN_LOSER_STATE attacks. The server sets
-- the NW2 vars (sv_teams_conditions.lua).
function WS.RestrictStunned(ply, cmd)
	if CurTime() >= ply:GetNW2Float("ws_stun_end_time", 0) then return end
	local flags = ply:GetNW2Int("ws_stun_flags", 0)
	local STUN = WS.PlayerRules.STUN
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
-- controller's ws_speed_scale) on the player's top speed, predicted on
-- both realms (TeamFortress_CalculateMaxSpeed, CTFGameMovement).
hook.Add("SetupMove", "ws_conditions", function(ply, mv)
	local boost = ply:GetNW2Bool("ws_speed_boosted", false)
	local scale = ply:GetNW2Float("ws_speed_scale", 1)
	local reduction = 0
	if CurTime() < ply:GetNW2Float("ws_stun_end_time", 0) then reduction = ply:GetNW2Float("ws_stun_speed_reduction", 0) end
	if not boost and reduction == 0 and scale == 1 then return end
	local speed = WS.PlayerRules.MaxSpeed(mv:GetMaxClientSpeed(), boost, reduction, scale)
	mv:SetMaxClientSpeed(speed)
	mv:SetMaxSpeed(speed)
end)
