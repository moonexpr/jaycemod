-- Admin > Gameplay Settings: the round timer, respawn times, win conditions
-- and team scores as editable fields (wetsand_editor), shown in the
-- Utilities menu's Gameplay Settings panel (wetsand/sh_gameplay.lua, a
-- DEntityProperties of this entity). Not a world editor: the server keeps
-- one on every map, unseen and sent to every client, and only admins edit
-- it. The Game Rules and Round Timer editors keep their actions.
AddCSLuaFile()
DEFINE_BASECLASS("wetsand_editor")

ENT.Type = "anim"
ENT.Base = "wetsand_editor"

ENT.Spawnable = false
ENT.AdminOnly = true
ENT.PrintName = "Gameplay Settings"

local RED, BLUE = WETSAND.TEAM_RED, WETSAND.TEAM_BLUE
local TIME_MAX = 7200
local RESPAWN_MAX = 60
local BOTH_DEFAULT = 10 -- mp_respawnwavetime's default
local SCORE_MAX = 100
local WIN_LIMIT_MAX, MAX_ROUNDS_MAX, TIME_LIMIT_MAX = 100, 100, 240

-- A win condition: one of the rounds' convars (0: none).
local function WinCondition(name, convar, title, max)
	return {
		name = name, type = "Int", title = title, category = "Win conditions", min = 0, max = max,
		read = function() return GetConVar(convar):GetInt() end,
		write = function(_, v) GetConVar(convar):SetInt(v) end,
	}
end

ENT.Fields = {
	{
		name = "TimeLeft", type = "Int", title = "Time left (s)", category = "Round timer", min = 0, max = TIME_MAX,
		read = function(e) return math.ceil(e:TimeLeft()) end,
		write = function(e, v) e:SetTimeLeft(v) end,
	},
	{
		name = "Paused", type = "Bool", title = "Paused", category = "Round timer",
		read = function(e) return e:Paused() end,
		write = function(e, v) e:SetPaused(v) end,
	},
	{
		name = "RedRespawn", type = "Float", title = "RED respawn wave (s)", category = "Respawn times", min = 0, max = RESPAWN_MAX,
		read = function(e) return e:RespawnTime(RED) end,
		write = function(e, v) e:SetRespawnTime(RED, v) end,
	},
	{
		name = "BluRespawn", type = "Float", title = "BLU respawn wave (s)", category = "Respawn times", min = 0, max = RESPAWN_MAX,
		read = function(e) return e:RespawnTime(BLUE) end,
		write = function(e, v) e:SetRespawnTime(BLUE, v) end,
	},
	{
		name = "BothRespawn", type = "Float", title = "Both teams' respawn wave (s)", category = "Respawn times", min = 0, max = RESPAWN_MAX,
		default = BOTH_DEFAULT,
		write = function(e, v) e:SetRespawnTime(nil, v) end,
	},
	{
		name = "RespawnsDisabled", type = "Bool", title = "Disable respawns", category = "Respawn times",
		read = function(e) return e:RespawnsDisabled() end,
		write = function(e, v) e:SetRespawnsDisabled(v) end,
	},
	WinCondition("WinLimit", "mp_winlimit", "Rounds to win the match (0: no limit)", WIN_LIMIT_MAX),
	WinCondition("MaxRounds", "mp_maxrounds", "Rounds in the match (0: no limit)", MAX_ROUNDS_MAX),
	WinCondition("TimeLimit", "mp_timelimit", "Match time limit (min, 0: none)", TIME_LIMIT_MAX),
	{
		name = "RedScore", type = "Int", title = "RED score", category = "Team scores", min = 0, max = SCORE_MAX,
		read = function(e) return e:Score(RED) end,
		write = function(e, v) e:SetScore(RED, v) end,
	},
	{
		name = "BluScore", type = "Int", title = "BLU score", category = "Team scores", min = 0, max = SCORE_MAX,
		read = function(e) return e:Score(BLUE) end,
		write = function(e, v) e:SetScore(BLUE, v) end,
	},
}

if CLIENT then
	function ENT:Draw() end
	return
end

-- Unseen and untouchable, and on every client wherever it stands.
function ENT:Initialize()
	BaseClass.Initialize(self)
	self:SetNoDraw(true)
	self:SetNotSolid(true)
	self:SetMoveType(MOVETYPE_NONE)
end

function ENT:UpdateTransmitState()
	return TRANSMIT_ALWAYS
end
