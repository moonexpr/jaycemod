-- ws/sv_spectate.lua loaded in a fake GMod: its hooks are kept and called as
-- the engine would; a fake player answers what the tests read and takes
-- every other call silently.
local T = dofile("tests/harness.lua")
local Teams = T.require("foundation.teams")
local STATE = T.require("foundation.rounds.state")

local SOURCE = T.ROOT .. "ws/sv_spectate.lua"
local FL_NOTARGET = 16384 -- GMod's
local NOOP = function() end

local function Load()
	local hooks = {}
	local ws = setmetatable({
		require = T.require,
		TEAM_SPECTATOR = Teams.SPECTATOR,
		TEAM_UNASSIGNED = Teams.UNASSIGNED,
		Active = function() return true end,
		STATE = STATE,
		State = function() return STATE.RND_RUNNING end,
	}, { __index = function() return NOOP end })
	local env = setmetatable({
		WS = ws,
		hook = {
			Add = function(event, id, fn)
				hooks[event] = hooks[event] or {}
				hooks[event][id] = fn
			end,
		},
		concommand = { Add = NOOP },
		GetConVar = function() return { GetInt = function() return 1 end, GetBool = function() return true end } end,
		CreateConVar = function() return { GetInt = function() return 1 end, GetBool = function() return true end } end,
		player = {
			GetAll = function() return {} end,
			Iterator = function() return ipairs({}) end,
		},
		ents = {
			FindByClass = function() return {} end,
			GetAll = function() return {} end,
			Iterator = function() return ipairs({}) end,
		},
		FL_NOTARGET = FL_NOTARGET,
		OBS_MODE_NONE = 0,
		OBS_MODE_FIXED = 3,
		OBS_MODE_IN_EYE = 4,
		OBS_MODE_CHASE = 5,
		OBS_MODE_ROAMING = 6,
		NULL = false,
		IsValid = function(v) return v ~= nil and v ~= false end,
		CurTime = function() return 0 end,
		Vector = function(x, y, z) return { x = x, y = y, z = z } end,
		IN_ATTACK = 1,
		IN_JUMP = 2,
		IN_ATTACK2 = 2048,
		IN_RELOAD = 8192,
	}, { __index = _G })
	setfenv(assert(loadfile(SOURCE)), env)()
	return ws, hooks
end

-- A player on team, its flags kept; any other method does nothing.
local function Player(team, flags)
	local ply = {
		team = team,
		flags = flags or 0,
	}
	function ply:Team() return self.team end
	function ply:IsFlagSet(flag) return bit.band(self.flags, flag) ~= 0 end
	function ply:AddFlags(flag) self.flags = bit.bor(self.flags, flag) end
	function ply:RemoveFlags(flag) self.flags = bit.band(self.flags, bit.bnot(flag)) end
	function ply:IsPlayer() return true end
	return setmetatable(ply, { __index = function() return NOOP end })
end

T.test("an observer is no one's target, and is again once it stops", function()
	local ws = Load()
	local ply = Player(Teams.BLUE)
	ws.StartObserving(ply)
	T.eq(ply:IsFlagSet(FL_NOTARGET), true, "observing")
	ws.StopObserving(ply)
	T.eq(ply:IsFlagSet(FL_NOTARGET), false, "playing")
end)

T.test("a dead player watching is no one's target, until they spawn", function()
	local _, hooks = Load()
	local ply = Player(Teams.BLUE)
	hooks.PostPlayerDeath.ws_spectate(ply)
	T.eq(ply:IsFlagSet(FL_NOTARGET), true, "dead and watching")
	hooks.PlayerSpawn.ws_spectate(ply)
	T.eq(ply:IsFlagSet(FL_NOTARGET), false, "spawned")
end)

T.test("an admin's own notarget outlasts observing", function()
	local ws = Load()
	local ply = Player(Teams.BLUE, FL_NOTARGET)
	ws.StartObserving(ply)
	ws.StopObserving(ply)
	T.eq(ply:IsFlagSet(FL_NOTARGET), true, "still notarget")
end)

T.test("a player watching as the game stops is a target again once they spawn", function()
	local ws, hooks = Load()
	local ply = Player(Teams.BLUE)
	hooks.PostPlayerDeath.ws_spectate(ply)
	ws.Active = function() return false end
	hooks.PlayerSpawn.ws_spectate(ply)
	T.eq(ply:IsFlagSet(FL_NOTARGET), false, "spawned in Sandbox mode")
end)

T.finish()
