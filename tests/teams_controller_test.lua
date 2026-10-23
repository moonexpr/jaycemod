-- ws/sv_teams.lua loaded in a fake GMod: its hooks are kept and called as
-- the engine and other addons would, timer.Simple's functions run when the
-- test says the tick has passed, and players are fakes.
local T = dofile("tests/harness.lua")
local Teams = gameplay.teams

local SOURCE = T.ROOT .. "ws/sv_teams.lua"
local RUNNER = 21 -- ULX's team for a user group, as one server has it

-- active: whether a game is on (WS.Active, and WS.TeamPlay: Gameplay mode).
local function Load(active)
	local hooks, deferred = {}, {}
	local ws = {
		TeamRules = Teams,
		UnbalanceLimit = { GetInt = function() return 1 end },
		TEAM_UNASSIGNED = Teams.UNASSIGNED,
		TEAM_SPECTATOR = Teams.SPECTATOR,
		TEAM_RED = Teams.RED,
		TEAM_BLUE = Teams.BLUE,
		Active = function() return active end,
		TeamPlay = function() return active end,
	}
	local env = setmetatable({
		WS = ws,
		hook = {
			Add = function(event, id, fn)
				hooks[event] = hooks[event] or {}
				hooks[event][id] = fn
			end,
		},
		timer = {
			Simple = function(_, fn) deferred[#deferred + 1] = fn end,
			Create = function() end,
		},
		concommand = { Add = function() end },
		CreateConVar = function() return { GetBool = function() return true end } end,
		FCVAR_NOTIFY = 256,
		IsValid = function(v) return v ~= nil end,
	}, { __index = _G })
	setfenv(assert(loadfile(SOURCE)), env)()
	local world = { hooks = hooks }
	-- every hook on event, as GMod calls them
	function world:Call(event, ...)
		for _, fn in pairs(self.hooks[event] or {}) do fn(...) end
	end
	-- the next tick: what timer.Simple(0) deferred runs
	function world:Tick()
		local due = deferred
		deferred = {}
		for _, fn in ipairs(due) do fn() end
	end
	return world
end

-- A player of Sandcastle's team, moved to another addon's.
local function Player(own, current)
	local ply = {
		wsTeam = own,
		team = current,
	}
	function ply:Team() return self.team end
	function ply:SetTeam(t) self.team = t end
	return ply
end

T.test("in a game, a player another addon moves as it spawns is put back a tick later", function()
	local world = Load(true)
	local ply = Player(Teams.BLUE, RUNNER)
	world:Call("PlayerSpawn", ply)
	world:Tick()
	T.eq(ply:Team(), Teams.BLUE, "back on BLU")
end)

-- ULX gives a player its group's team as UCL authenticates them, which can
-- come after their first spawn.
T.test("in a game, a player ULX moves as it authenticates them is put back a tick later", function()
	local world = Load(true)
	local ply = Player(Teams.RED, RUNNER)
	world:Call("UCLAuthed", ply)
	world:Tick()
	T.eq(ply:Team(), Teams.RED, "back on RED")
end)

T.test("in Sandbox mode, the other addon's team stays", function()
	local world = Load(false)
	local ply = Player(Teams.BLUE, RUNNER)
	world:Call("PlayerSpawn", ply)
	world:Call("UCLAuthed", ply)
	world:Tick()
	T.eq(ply:Team(), RUNNER, "still the Runner")
end)

T.finish()
