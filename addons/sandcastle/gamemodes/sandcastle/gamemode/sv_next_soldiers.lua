-- Bot players on the engine's own statechart (native/nextsoldier): a bot from
-- player.CreateNextSoldier runs nextsoldier.behavior.ctfbot's tree, and this is the
-- soldier those actions see, its keys pressed each tick as a player's. GMod has no
-- player locomotion for a NextBotPlayer, so its moves are ours: routes from a navigator
-- (ws_bot_navigator), its keys from its body (nextsoldier.body.player_body).
--   WS.AddNextSoldier(team[, name]) -> the bot, or nil without the binary or a slot
--   ns_soldier_add red|blue [name]
local CTFBot = nextsoldier.behavior.ctfbot
local PlayerBody = nextsoldier.body.player_body
local RouteWalk = nextsoldier.locomotion.route_walk
local Locomotion = nextsoldier.locomotion
local Movement = gameplay.movement
local TFBot = WS.require("foundation.wetsands.path.tfbot")

-- A route is planned at most this often, and again when its goal moved this far.
local REPLAN, REPLAN_DISTANCE = 1, 128
-- FollowPath is asked each update of its action: not asked for this long, it stands.
local FOLLOW_LAPSES = 0.5
-- A goal off the mesh is walked to as the nearest point of an area this near
-- (ctf_2fort's intel lies a unit past its area's edge).
local OFF_MESH_NEAR = 96
-- Its way is swept from a step above the floor, its own width, to its head; a
-- straight walk rises no more than a stair flight's step (the war's WalkClear), its
-- floor looked for a step above to two below its line, and a goal this near in a clear
-- line is walked straight at.
local LIFT, RISE, SWEEP_HEIGHT = Vector(0, 0, 20), 40, 36
local FOOTING_ABOVE, FOOTING_BELOW = Vector(0, 0, 18), Vector(0, 0, 36)
local DIRECT_RANGE = 256
-- A route's point this far below and this near is a drop to step off; a floor this far
-- beneath its feet still bears it, and a landing this far from the one meant is another.
local DROP_DEPTH, DROP_NEAR = 40, 48
local SOLE, FOOTHOLD, LANDING_SLACK = 2, 18, 24
-- Its body is TF2's, so it is priced as TF2's bots are: a stair's step, its crouch
-- jump, the fall it survives unhurt, and no ladder (its keys climb none).
local LIMITS = { stepHeight = Movement.TF2.stepHeight, jumpHeight = Movement.CrouchJump(Movement.TF2), deathDropHeight = 300 }

local Soldier = {}
Soldier.__index = Soldier

WS.require("features.flag.soldier").Apply(Soldier)

function Soldier:FlagCarrier() return self.ent end
function Soldier:SecondsAlive() return CurTime() - self.spawnedAt end
function Soldier:Now() return CurTime() end
function Soldier:RoundMode() return WS.Feature("rounds"):Mode().NAME end

function Soldier:FollowPath(goal)
	self.goal, self.followedAt = goal, CurTime()
	return "moving"
end

local function Point(v) return { x = v.x, y = v.y, z = v.z } end
local function ToVector(p) return Vector(p.x, p.y, p.z) end

function Soldier:WalkClear(from, to)
	if math.abs(to.z - from.z) > RISE then return false end
	local hullMin, hullMax = self.ent:GetHull()
	local mins, maxs = Movement.Sweep(hullMin, hullMax, SWEEP_HEIGHT)
	local tr = util.TraceHull({
		start = from + LIFT,
		endpos = to + LIFT,
		mins = ToVector(mins),
		maxs = ToVector(maxs),
		mask = MASK_PLAYERSOLID,
		filter = self.ent,
	})
	if tr.Hit then return false end
	for _, q in ipairs(RouteWalk.Footing(Point(from), Point(to))) do
		local at = ToVector(q)
		local floor = util.TraceLine({ start = at + FOOTING_ABOVE, endpos = at - FOOTING_BELOW, mask = MASK_PLAYERSOLID, filter = self.ent })
		if not floor.Hit then return false end
	end
	return true
end

-- Whether its whole body fits at q, over a floor.
function Soldier:Stands(q)
	local hullMin, hullMax = self.ent:GetHull()
	local mins, maxs = Movement.Sweep(hullMin, hullMax, SWEEP_HEIGHT)
	local at = ToVector(q)
	if util.TraceHull({ start = at + LIFT, endpos = at + LIFT, mins = mins, maxs = maxs, mask = MASK_PLAYERSOLID, filter = self.ent }).Hit then
		return false
	end
	return util.TraceLine({ start = at + FOOTING_ABOVE, endpos = at - FOOTING_BELOW, mask = MASK_PLAYERSOLID, filter = self.ent }).Hit
end

-- Whether no wall stands between two places on a route.
function Soldier:Reaches(p, q)
	return not util.TraceLine({ start = ToVector(p) + LIFT, endpos = ToVector(q) + LIFT, mask = MASK_PLAYERSOLID, filter = self.ent }).Hit
end

-- What a route is priced by (Path:Compute's generator): TF2's own path cost over what
-- its team knows, each step told whether its body fits; nil until the mesh is ready.
function Soldier:RouteCost()
	local ply = self.ent
	local team = ply:Team()
	local cost = WS.Feature("npc"):EngineCost(team, TFBot, LIMITS, {
		entIndex = ply:EntIndex(),
		now = CurTime(),
		team = team,
		route = TFBot.FASTEST_ROUTE,
		miniBoss = false,
		roundWon = false,
	})
	if not cost then return nil end
	local clearance = WS.NavHullClearance(ply, WS.ClipMasks().brushes)
	return function(area, fromArea, ladder, elevator, length)
		local fits
		if fromArea then
			fits = clearance:Area(area)
			if fits and not ladder then fits = clearance:Link(fromArea, area) end
		end
		return cost(area, fromArea, ladder, elevator, length, fits)
	end
end

-- The point it makes for on its way to point, veered off a jamb on one side of it.
function Soldier:Avoid(pos, point)
	local ply = self.ent
	local _, hullMax = ply:GetHull()
	local half = hullMax.x
	local mins, maxs = Vector(-half / 2, -half / 2, 0), Vector(half / 2, half / 2, SWEEP_HEIGHT)
	return Locomotion.Avoid(Point(pos), point, half, function(from, to)
		return util.TraceHull({
			start = ToVector(from) + LIFT,
			endpos = ToVector(to) + LIFT,
			mins = mins,
			maxs = maxs,
			mask = MASK_PLAYERSOLID,
			filter = ply,
		}).Hit
	end)
end

-- Where to walk to fall to a drop's landing, kept for that landing: nil with no way off.
function Soldier:StepOff(pos, landing)
	if self.stepOffOf == landing then return self.stepOffTo end
	local ply = self.ent
	local hullMin, hullMax = ply:GetHull()
	local mins, maxs = Vector(hullMin.x, hullMin.y, 0), Vector(hullMax.x, hullMax.y, SWEEP_HEIGHT)
	local function Trace(from, to)
		return util.TraceHull({ start = from, endpos = to, mins = mins, maxs = maxs, mask = MASK_PLAYERSOLID, filter = ply })
	end
	local function Clear(q)
		return not Trace(pos + LIFT, ToVector(q) + LIFT).Hit
	end
	local function Falls(q)
		local at = ToVector(q)
		local above = at + Vector(0, 0, SOLE)
		if Trace(above, at - Vector(0, 0, FOOTHOLD)).Hit then return false end
		local under = Trace(above, Vector(at.x, at.y, landing.z - LANDING_SLACK))
		return under.Hit and math.abs(under.HitPos.z - landing.z) <= LANDING_SLACK
	end
	self.stepOffOf, self.stepOffTo = landing, Locomotion.StepOff(Point(pos), landing, Clear, Falls)
	return self.stepOffTo
end

function Soldier:Navigator()
	local ply = self.ent
	if IsValid(ply.NSNavigator) then return ply.NSNavigator end
	local navigator = ents.Create("ws_bot_navigator")
	navigator:SetOwner(ply)
	navigator:SetPos(ply:GetPos())
	navigator:Spawn()
	ply.NSNavigator = navigator
	return navigator
end

local function OnMesh(goal)
	local area = navmesh.GetNearestNavArea(goal, false, OFF_MESH_NEAR, false, true)
	if not IsValid(area) then return goal end
	return area:GetClosestPointOnArea(goal)
end

-- The point its body makes for now on its way to its goal.
function Soldier:Steer(now)
	if not self.goal or now - self.followedAt > FOLLOW_LAPSES then
		self.goal, self.walk, self.planned, self.steer = nil, nil, nil, nil
		return
	end
	local ply = self.ent
	local pos = ply:GetPos()
	local goal = OnMesh(self.goal)
	if self.walk and self.walk:Stalled(Point(pos), now) then self.walk, self.planned = nil, nil end
	local stale = not self.planned or self.planned:Distance(goal) > REPLAN_DISTANCE
	local cost = stale and now >= self.nextPlan and self:Navigator():Settled() and self:RouteCost()
	if cost then
		self.planned, self.nextPlan = goal, now + REPLAN
		local route = self:Navigator():PlanRoute(goal, cost)
		local points = {}
		for i, v in ipairs(route or {}) do points[i] = Point(v) end
		points = Locomotion.StandPoints(points, function(q) return self:Stands(q) end, function(p, q) return self:Reaches(p, q) end)
		points = Locomotion.RoundCorners(points, function(a, b) return self:WalkClear(ToVector(a), ToVector(b)) end)
		if route and RouteWalk.Trivial(points, Point(pos), DIRECT_RANGE) then route = nil end
		self.walk = route and RouteWalk.New(points) or nil
		if not route then self.planned = nil end
	end
	if pos:Distance(goal) <= DIRECT_RANGE and self:WalkClear(pos, goal) then
		self.steer = Point(goal)
		return
	end
	local point = self.walk and self.walk:Next(Point(pos), function(q) return self:WalkClear(pos, ToVector(q)) end) or nil
	if point and Locomotion.DropBelow(Point(pos), point, DROP_DEPTH, DROP_NEAR) then
		point = self:StepOff(pos, point) or point
	elseif point then
		point = self:Avoid(pos, point)
	end
	self.steer = point
end

-- This tick's keys, from its body's command.
function Soldier:Drive(cmd)
	local ply, now, sense = self.ent, CurTime(), self.sense
	if now >= self.nextSteer then
		self.nextSteer = now + 0.1
		self:Steer(now)
	end
	local eye, velocity = ply:EyeAngles(), ply:GetVelocity()
	sense.pos, sense.eyePos = Point(ply:GetPos()), Point(ply:EyePos())
	sense.eye.pitch, sense.eye.yaw = eye.p, eye.y
	sense.speed, sense.climb, sense.onGround = velocity:Length2D(), velocity.z, ply:OnGround()
	sense.target = self.steer
	local out = self.body:Command(now, engine.TickInterval(), sense)
	if out.moveYaw then
		cmd:SetViewAngles(Angle(0, out.moveYaw, 0))
		cmd:SetForwardMove(ply:GetRunSpeed())
	else
		cmd:SetViewAngles(Angle(out.pitch, out.yaw, 0))
	end
	local buttons = 0
	if out.duck then buttons = bit.bor(buttons, IN_DUCK) end
	if out.jump then buttons = bit.bor(buttons, IN_JUMP) end
	if out.use then buttons = bit.bor(buttons, IN_USE) end
	cmd:SetButtons(buttons)
	ply:SetEyeAngles(Angle(out.pitch, out.yaw, 0))
end

local soldiers = setmetatable({}, { __mode = "k" })
local compiled

function WS.NextSoldierOf(ply) return soldiers[ply] end

function WS.AddNextSoldier(team, name)
	if not player.CreateNextSoldier then return nil end
	local ply = player.CreateNextSoldier(name or ("NextSoldier " .. (table.Count(soldiers) + 1)))
	if not IsValid(ply) then return nil end
	local soldier = setmetatable({
		ent = ply,
		body = PlayerBody.New(),
		sense = { eye = {} },
		spawnedAt = CurTime(),
		nextPlan = 0,
		nextSteer = 0,
		followedAt = 0,
	}, Soldier)
	soldiers[ply] = soldier
	compiled = compiled or CTFBot.Compile(wartactics.scenarios)
	nextsoldier.engine.Insert(ply, CTFBot.InitialAction(nextsoldier.engine, compiled), soldier)
	-- the body it was made with goes quietly: joining a team alive would kill it
	ply:KillSilent()
	WS.SetPlayerTeam(ply, team)
	return ply
end

hook.Add("StartCommand", "ws_next_soldiers", function(ply, cmd)
	local soldier = soldiers[ply]
	if not soldier then return end
	cmd:ClearButtons()
	cmd:ClearMovement()
	if ply:Alive() then soldier:Drive(cmd) end
end)

hook.Add("PlayerSpawn", "ws_next_soldiers", function(ply)
	local soldier = soldiers[ply]
	if soldier then soldier.spawnedAt, soldier.walk, soldier.planned = CurTime(), nil, nil end
end)

concommand.Add("ns_soldier_add", function(ply, _, args)
	if IsValid(ply) and not ply:IsSuperAdmin() then return end
	local team = args[1] == "red" and WS.TEAM_RED or WS.TEAM_BLUE
	local bot = WS.AddNextSoldier(team, args[2])
	print(bot and ("added " .. bot:Nick()) or "no NextSoldier: the binary, or no slot")
end, nil, "Adds a bot player on the engine's statechart: ns_soldier_add red|blue [name]")
