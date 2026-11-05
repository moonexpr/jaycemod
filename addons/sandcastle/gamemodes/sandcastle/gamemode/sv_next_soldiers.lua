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
local BotSteering = WS.require("features.npc.bot_steering")
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

BotSteering.Apply(Soldier, { util = util, Vector = Vector, mask = MASK_PLAYERSOLID })

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
		points = self:StandOnRoute(points)
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
	-- its route over and its goal not reached: planned again
	if self.walk and not point then self.planned = nil end
	self.steer = point and self:SteerOn(pos, point)
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
	if self.head then
		-- its eyes are its head's, in Rust: its feet go their way under them
		cmd:SetViewAngles(Angle(eye.p, eye.y, 0))
		if out.moveYaw then
			local off = math.rad(out.moveYaw - eye.y)
			cmd:SetForwardMove(ply:GetRunSpeed() * math.cos(off))
			cmd:SetSideMove(-ply:GetRunSpeed() * math.sin(off))
		end
	elseif out.moveYaw then
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
	if not self.head then ply:SetEyeAngles(Angle(out.pitch, out.yaw, 0)) end
end

-- Its head, configured once and Rust's after: a request's priority, the seconds it holds
-- and what the LOOK_AT layer says of it.
local LOOK_SOURCES = {
	{ kind = "BodyFacing", priority = "BORING", seconds = 0.25, reason = "Body facing" },
	{ kind = "Friend", priority = "BORING", seconds = 2, range = 600, every = 8, reason = "Looking around at friend" },
}

local function LookConfig()
	return {
		settle = GetConVar("nb_head_aim_settle_duration"):GetFloat(),
		steady_rate = GetConVar("nb_head_aim_steady_max_rate"):GetFloat(),
		turn_rate = PlayerBody.TURN_RATE,
		interval = engine.TickInterval(),
		sources = LOOK_SOURCES,
	}
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
	nextsoldier.behavior.group_identity.Give(ply, nextsoldier.engine, ply)
	if nextsoldier.engine.Look then
		nextsoldier.engine.Look(ply, LookConfig())
		soldier.head = true
	end
	-- the body it was made with goes quietly: joining a team alive would kill it
	ply:KillSilent()
	WS.SetPlayerTeam(ply, team)
	return ply
end

hook.Add("WSNbDebugNpcs", "ws_next_soldiers", function(found)
	for ply, soldier in pairs(soldiers) do
		if IsValid(ply) then
			if not soldier.debug then
				soldier.debug = nextsoldier.behavior.action.DebugNpc(ply, nextsoldier.engine.Stack, nextsoldier.engine.GroupStack)
				if soldier.head then
					function soldier.debug:LookLines(now) return nextsoldier.engine.LookLines(ply, ply:Nick(), now) end
					function soldier.debug:WatchLook(on) nextsoldier.engine.LookWatch(ply, on) end
				end
			end
			found[ply] = soldier.debug
		end
	end
end)

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
