local T = dofile("tests/harness.lua")
local ROOT = T.ROOT

local function Load(server, client)
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
		CLIENT = client,
		LocalPlayer = function() return players[1] end,
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
	function ply:EyeAngles() return self.eye or "the client's aim" end
	function ply:SetNW2Angle(key, angles) self.nw2 = self.nw2 or {} self.nw2[key] = angles end
	function ply:GetNW2Angle(key, default)
		local held = self.nw2 and self.nw2[key]
		if held == nil then return default end
		return held
	end
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
			GetAngles = function(self)
			self.angles = self.angles or { p = 0, y = index, r = 0 }
			return self.angles
		end,
			FOV = function() return 90 end,
		}
	end

	return ws.Spectator, ply, {
		class = definition,
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

local function NewCmd()
	local cmd = { mouseX = 7, mouseY = -3, angles = "the client's aim" }
	function cmd:SetMouseX(x) self.mouseX = x end
	function cmd:SetMouseY(y) self.mouseY = y end
	function cmd:SetViewAngles(angles) self.angles = angles end
	return cmd
end

local function NewMove()
	local mv = { angles = "the client's aim", moveAngles = "the client's aim" }
	function mv:SetAngles(angles) self.angles = angles end
	function mv:SetMoveAngles(angles) self.moveAngles = angles end
	return mv
end

T.test("a fixed camera's move ignores the mouse in every move step", function()
	local spectator, ply, state = Load(true)
	ply.team = 2
	ply.playerClass = "player_spectator"
	local point = state.NewPoint(10, 2)
	spectator.Observe(ply, point)
	local held = ply:GetNW2Angle("wsSpectatorFixedAngles")
	T.eq(held.y, 10, "the camera's angles are networked to the client")

	local cmd, mv = NewCmd(), NewMove()
	state.class.StartMove({ Player = ply }, mv, cmd)
	T.eq(cmd.mouseX, 0, "StartMove drops mouse x")
	T.eq(cmd.mouseY, 0, "StartMove drops mouse y")
	T.eq(cmd.angles, held, "StartMove holds the command's aim")
	T.eq(mv.angles, held, "StartMove holds the move's angles")
	T.eq(mv.moveAngles, held, "StartMove holds the move's direction")

	mv = NewMove()
	T.eq(state.class.Move({ Player = ply }, mv), true, "a fixed camera skips the engine's movement")
	T.eq(mv.angles, held, "Move holds the move's angles")

	mv = NewMove()
	T.eq(state.class.FinishMove({ Player = ply }, mv), nil,
		"the engine still finishes the move, which records the buttons KeyPress reads")
	T.eq(mv.angles, held, "FinishMove leaves the player the held angles")
end)

T.test("other observer modes keep the mouse and the engine's movement", function()
	local _, ply, state = Load(true)
	ply.playerClass = "player_spectator"
	for _, mode in ipairs({ 4, 5, 6 }) do
		ply.observerMode = mode
		local cmd, mv = NewCmd(), NewMove()
		state.class.StartMove({ Player = ply }, mv, cmd)
		T.eq(cmd.mouseX, 7, "mouse kept in mode " .. mode)
		T.eq(cmd.angles, "the client's aim", "aim kept in mode " .. mode)
		T.eq(state.class.Move({ Player = ply }, mv), nil, "engine moves in mode " .. mode)
		T.eq(state.class.FinishMove({ Player = ply }, mv), nil, "engine finishes in mode " .. mode)
		T.eq(mv.angles, "the client's aim", "angles kept in mode " .. mode)
	end
end)

T.test("a fixed camera with no target holds the view it was entered with", function()
	local spectator, ply = Load(true)
	ply.team = 2
	ply.eye = { p = 1, y = 2, r = 0 }
	spectator.Observe(ply, nil)
	T.eq(ply:GetNW2Angle("wsSpectatorFixedAngles"), ply.eye, "no target: Observe holds the view")

	ply.team = 0
	ply.eye = { p = 3, y = 4, r = 0 }
	spectator.SpawnAsSpectator(ply)
	T.eq(ply:GetNW2Angle("wsSpectatorFixedAngles"), ply.eye, "unassigned spawn holds the view")

	ply.eye = { p = 5, y = 6, r = 0 }
	spectator.Enter(ply, 0)
	T.eq(ply:GetNW2Angle("wsSpectatorFixedAngles"), ply.eye, "unassigned team holds the view")
end)

T.test("the point camera's Think snaps the view only when the point turns", function()
	local spectator, ply, state = Load(true)
	ply.team = 2
	ply.playerClass = "player_spectator"
	local point = state.NewPoint(10, 2)
	spectator.Observe(ply, point)
	local snaps = 0
	function ply:SetEyeAngles(angles) self.angles = angles snaps = snaps + 1 end

	local think = state.hooks["Think:player_spectator_point_camera"]
	think()
	think()
	T.eq(snaps, 0, "a still camera sends no angle fix, so nothing fights the client")

	local turned = { p = 0, y = 90, r = 0 }
	point.GetAngles = function() return turned end
	think()
	T.eq(snaps, 1, "a camera that turned moves the view once")
	T.eq(ply:GetNW2Angle("wsSpectatorFixedAngles"), turned, "the turned angles are networked")
	think()
	T.eq(snaps, 1, "and no more")
end)

T.test("both realms hold the command before the engine reads its angles into the eyes", function()
	for _, server in ipairs({ true, false }) do
		local _, ply, state = Load(server, not server)
		local start = state.hooks["StartCommand:player_spectator"]
		ply.playerClass = "player_spectator"
		ply.observerMode = 3
		local held = { p = 0, y = 45, r = 0 }
		ply:SetNW2Angle("wsSpectatorFixedAngles", held)

		local cmd = NewCmd()
		start(ply, cmd)
		T.eq(cmd.angles, held, "a fixed camera's command holds the aim")
		T.eq(cmd.mouseX, 0, "and carries no mouse")

		ply.observerMode = 6
		cmd = NewCmd()
		start(ply, cmd)
		T.eq(cmd.angles, "the client's aim", "roaming keeps its aim")

		ply.observerMode = 3
		ply.playerClass = "player_combatant"
		cmd = NewCmd()
		start(ply, cmd)
		T.eq(cmd.angles, "the client's aim", "another class keeps its aim")
	end
end)

T.test("the client's mouse never reaches a fixed camera's view", function()
	local _, ply, state = Load(false, true)
	local apply = state.hooks["InputMouseApply:player_spectator"]
	ply.playerClass = "player_spectator"
	ply.observerMode = 3
	local held = { p = 0, y = 45, r = 0 }
	ply:SetNW2Angle("wsSpectatorFixedAngles", held)

	local cmd = NewCmd()
	T.eq(apply(cmd, 7, -3, "the client's aim"), true, "the engine does not apply the mouse")
	T.eq(cmd.mouseX, 0, "mouse x dropped")
	T.eq(cmd.mouseY, 0, "mouse y dropped")
	T.eq(cmd.angles, held, "the view stays where the server holds it")

	cmd = NewCmd()
	state.class.CreateMove({ Player = ply }, cmd)
	T.eq(cmd.angles, held, "CreateMove sends the held aim")
	T.eq(cmd.mouseX, 0, "CreateMove sends no mouse")

	ply.observerMode = 6
	cmd = NewCmd()
	T.eq(apply(cmd, 7, -3, "the client's aim"), nil, "roaming keeps the mouse")
	T.eq(cmd.mouseX, 7, "roaming's mouse kept")
	state.class.CreateMove({ Player = ply }, cmd)
	T.eq(cmd.angles, "the client's aim", "roaming's aim kept")

	ply.observerMode = 3
	ply.playerClass = "player_combatant"
	cmd = NewCmd()
	T.eq(apply(cmd, 7, -3, "the client's aim"), nil, "another class keeps the mouse")
end)

T.finish()
