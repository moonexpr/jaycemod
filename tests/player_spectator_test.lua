local T = dofile("tests/harness.lua")
local ROOT = T.ROOT

local function Load(server)
	local definition
	local ws = {
		TEAM_UNASSIGNED = 0,
		TEAM_SPECTATOR = 1,
		TeamPlay = function() return true end,
		FeatureLoaded = function() return false end,
	}
	local hooks, timers, players, points = {}, {}, {}, {}
	local env = setmetatable({
		WS = ws,
		TEAM_UNASSIGNED = 0,
		TEAM_SPECTATOR = 1,
		OBS_MODE_NONE = 0,
		OBS_MODE_FIXED = 3,
		OBS_MODE_ROAMING = 6,
		OBS_MODE_CHASE = 5,
		OBS_MODE_IN_EYE = 4,
		IN_ATTACK = 1,
		IN_ATTACK2 = 2,
		FL_NOTARGET = 1024,
		SERVER = server,
		IsValid = function(value) return value ~= nil and value.valid ~= false end,
		DEFINE_BASECLASS = function() end,
		hook = { Add = function(event, name, fn) hooks[event .. ":" .. name] = fn end },
		timer = { Simple = function(_, fn) timers[#timers + 1] = fn end },
		player = { GetAll = function() return players end },
		ents = { FindByClass = function() return points end },
		player_manager = {
			RegisterClass = function(_, class) definition = class end,
			SetPlayerClass = function(ply, class) ply.playerClass = class end,
			GetPlayerClass = function(ply) return ply.playerClass end,
			RunClass = function(ply, method, ...)
				return definition[method]({ Player = ply }, ...)
			end,
		},
	}, { __index = _G })
	setfenv(assert(loadfile(ROOT .. "player_class/player_spectator.lua")), env)()

	local ply = { wsTeam = 0, team = 0, alive = false, index = 1 }
	function ply:Team() return self.team end
	function ply:SetTeam(team) self.team = team end
	function ply:StripWeapons() self.stripped = true end
	function ply:RemoveAllAmmo() self.ammoRemoved = true end
	function ply:Spectate(mode) self.observerMode = mode end
	function ply:SpectateEntity(target) self.observerTarget = target end
	function ply:GetObserverMode() return self.observerMode or 0 end
	function ply:GetObserverTarget() return self.observerTarget end
	function ply:AddFlags(flags) self.flags = flags end
	function ply:RemoveFlags(flags) if self.flags == flags then self.flags = 0 end end
	function ply:Alive() return self.alive end
	function ply:IsPlayer() return true end
	function ply:EntIndex() return self.index end
	function ply:SetPos(pos) self.pos = pos end
	function ply:SetEyeAngles(angles) self.angles = angles end
	function ply:SetFOV(fov) self.fov = fov end
	players[1] = ply

	local function NewPoint(index, team)
		return {
			index = index,
			IsEnabled = function() return true end,
			TeamNum = function() return team end,
			AssociatedEntity = function() return nil end,
			IsPlayer = function() return false end,
			GetClass = function() return "info_observer_point" end,
			GetPos = function() return { x = index, y = 0, z = 0 } end,
			GetAngles = function() return { p = 0, y = index, r = 0 } end,
			FOV = function() return 90 end,
		}
	end

	return ws.Spectator, ply, {
		hooks = hooks,
		timers = timers,
		players = players,
		points = points,
		NewPoint = NewPoint,
	}
end

T.test("spawn selects the right class and native spectator spawn behavior", function()
	local spectator, ply = Load(false)
	ply.flags = 1024
	ply.wsSpectatorNoTarget = true
	spectator.PrepareSpawn(ply)
	T.eq(ply.flags, 0, "normal spawns clear the observer-only NPC flag")

	T.eq(spectator.SelectSpawnClass(ply, true, false), true, "unassigned player observes")
	T.eq(ply.playerClass, "player_spectator", "selects spectator class")
	spectator.SpawnAsSpectator(ply)
	T.eq(ply.observerMode, 3, "unassigned player uses fixed mode")
	T.eq(ply.stripped, true, "spectator spawn strips weapons")

	ply.team = 2
	T.eq(spectator.SelectSpawnClass(ply, true, true), true, "sandbox class selection preserves observer state")
	T.eq(ply.playerClass, "player_sandcastle", "sandbox class takes precedence")
	spectator.SpawnAsSpectator(ply)
	T.eq(ply.playerClass, "player_sandcastle", "observer spawn preserves the selected Sandbox class")
	T.eq(ply.observerMode, 6, "a teamed observer uses roaming mode")
	T.eq(spectator.SelectSpawnClass(ply, false, false), false, "sandbox play mode is not team observation")
	T.eq(ply.playerClass, "player_combatant", "gameplay class selection")
end)

T.test("gamemode spawn bypasses Sandbox's player_sandbox class override", function()
	local file = assert(io.open(ROOT .. "init.lua"))
	local source = file:read("*a")
	file:close()
	T.eq(source:find("self.BaseClass.BaseClass.PlayerSpawn(self, ply, transition)", 1, true) ~= nil,
		true, "the selected class reaches the base gamemode spawn")
end)

T.test("team observer transitions use the class's native mode behavior", function()
	local spectator, ply = Load(false)
	ply.team = 2
	spectator.Enter(ply, 1)
	T.eq(ply.playerClass, "player_spectator", "observer transition selects class")
	T.eq(ply.observerMode, 6, "spectator team uses roaming mode")
	T.eq(ply.stripped, true, "observer transition strips weapons")

	spectator.Enter(ply, 0)
	T.eq(ply.observerMode, 3, "unassigned team uses fixed mode")
end)

T.test("death keeps the ragdoll and switches to observer on the next tick", function()
	local spectator, ply, state = Load(true)
	ply.team = 2
	spectator.AfterPlayerDeath(ply)
	T.eq(ply.playerClass, nil, "class remains unchanged until the next tick")
	T.eq(#state.timers, 1, "observer transition is deferred")

	state.timers[1]()
	T.eq(ply.playerClass, "player_spectator", "death selects the spectator class")
	T.eq(ply.observerMode, 3, "no target leaves a team player in fixed observer mode")
	T.eq(ply.flags, 1024, "spectators are hidden from NPC targeting")
end)

T.test("observer cycling wraps through team points and living teammates", function()
	local spectator, ply, state = Load(true)
	ply.team = 2
	ply.playerClass = "player_spectator"
	ply.observerMode = 3
	local point = state.NewPoint(10, 2)
	local teammate = {
		team = 2,
		index = 2,
		Alive = function() return true end,
		Team = function(self) return self.team end,
		EntIndex = function(self) return self.index end,
		IsPlayer = function() return true end,
	}
	state.points[1] = point
	state.players[2] = teammate
	ply.observerTarget = point

	T.eq(spectator.CycleTarget(ply, true), teammate, "reverse wraps from the first point to the teammate")
	T.eq(ply.observerMode, 5, "players use chase mode")
	T.eq(spectator.CycleTarget(ply, false), point, "forward wraps from the teammate to the point")
	T.eq(ply.observerMode, 3, "observer points use fixed mode")
	T.eq(ply.pos.x, 10, "point camera follows its position")

	teammate.team = 3
	T.eq(spectator.CanUsePoint(ply, point), true, "same-team observer points are available")
	ply.team = 1
	T.eq(spectator.CanUsePoint(ply, point), true, "spectator team may use any observer point")
	T.eq(state.hooks["PlayerUse:player_spectator"](ply), false, "spectators cannot use map entities")
end)

T.finish()
