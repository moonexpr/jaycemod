-- npc_pathfollower: NextSoldier's non-combat pathing bench. Console errands
-- report their route and remove themselves; tool-managed followers switch
-- between Idle and Travel, optionally following the AI war's active lanes,
-- and remain alive for retargeting. The stool also draws their generated
-- path and local movement command.
--
-- follower:NSErrand(goal, seconds) sends a spawned one. From the console:
-- ns_pathfollower_send fromX fromY fromZ toX toY toZ [seconds].
AddCSLuaFile()

ENT.Base = "base_nextsoldier"
ENT.Type = "nextbot"
ENT.PrintName = "Path Follower"
ENT.Category = "Sandcastle"
ENT.Spawnable = false
ENT.Models = { "models/player/combine_soldier.mdl" }
ENT.Weapons = {}
ENT.Factions = {}
ENT.DefaultRelationship = D_NU
ENT.RagdollOnDeath = false

WS.WarSoldier(ENT)
local WarSoldierUpdateAnimation = ENT.OnUpdateAnimation

if CLIENT then
	local LANE_COLOR = Color(255, 190, 60)
	local COMMAND_COLOR = Color(255, 90, 210)
	local TARGET_COLOR = Color(120, 255, 120)
	local BEAM_MATERIAL = Material("models/wireframe")

	local function DrawLine(from, to, color, width)
		render.DrawLine(from, to, color)
	end

	local function DrawPoints(points, color, radius, width)
		for i, point in ipairs(points) do
			if points[i + 1] then DrawLine(point, points[i + 1], color, width) end
			render.DrawWireframeSphere(point, radius, 5, 5, color, false)
		end
	end

	function ENT:Draw()
		self:DrawModel()
		if not self:GetNW2Bool("NSPathFollowerDebug", false) then return end

		DrawPoints(self.nsDebugLanePoints or {}, LANE_COLOR, 5, 8)

		local origin = self:GetPos() + Vector(0, 0, 3)
		local direction = self:GetNW2Vector("NSPathFollowerCommand", vector_origin)
		direction.z = 0
		if direction:Length2DSqr() > 0 then
			direction:Normalize()
			local tip = origin + direction * 80
			local side = Vector(-direction.y, direction.x, 0) * 9
			DrawLine(origin, tip, COMMAND_COLOR, 6)
			DrawLine(tip, tip - direction * 16 + side, COMMAND_COLOR, 6)
			DrawLine(tip, tip - direction * 16 - side, COMMAND_COLOR, 6)
		end

		if self:GetNW2String("NSPathFollowerBehavior", "Idle") == "Travel" then
			render.DrawWireframeSphere(self:GetNW2Vector("NSPathFollowerGoal", vector_origin), 12, 8, 8, TARGET_COLOR, false)
		end
	end
	return
end

-- Within ARRIVE of its goal it has arrived.
local ARRIVE = 48
-- Moving less than PROGRESS in RECOVER_AFTER seconds, it recovers: its path
-- planned again; after NUDGE_AFTER recoveries running, it is nudged as well
-- (a hop or a vault toward its path's next waypoint). Headway is movement,
-- not nearing the goal: a stairway winding away from the goal is headway.
local PROGRESS, RECOVER_AFTER, NUDGE_AFTER = 32, 3, 2
-- A fall of more than this between two updates is marked.
local DROP_MARK = 64
local DEFAULT_SECONDS = 60
local REPORTS = "sandcastle/pathfollower/"
local DEBUG_COMMAND_SYNC = 0.1
local MAX_DEBUG_POINTS = 2047
local debugEventWarningSent = false
local RUN_ACTIVITY_MODELS = {
	["models/player/scout.mdl"] = true,
	["models/bots/headless_hatman.mdl"] = true,
}

local function Point(v) return { x = math.Round(v.x), y = math.Round(v.y), z = math.Round(v.z) } end
local function AsVector(p) return Vector(p.x, p.y, p.z) end

-- A path's waypoints by kind (the engine's segment types).
local SEGMENT_KINDS = { [0] = "ground", "drop", "climb", "gap", "ladder up", "ladder down" }
local Lanes = wartactics.lanes
local SoldierSteer = ENT.NSSteer

function ENT:OnUpdateAnimation()
	local act, rate = WarSoldierUpdateAnimation(self)
	if act ~= nil then return act, rate end
	if RUN_ACTIVITY_MODELS[self:GetModel()] then
		if self.loco:GetVelocity():Length2D() > 1 then
			return ACT_MP_RUN_PRIMARY, 1.0
		else
			return ACT_MP_STAND_PRIMARY, 1.0
		end
	end
end

local function NearestPoint(points, position)
	local best, distance
	for i, point in ipairs(points) do
		local candidate = position:DistToSqr(AsVector(point))
		if not distance or candidate < distance then best, distance = i, candidate end
	end
	return best, distance and math.sqrt(distance) or math.huge
end

local function LaneRoute(team, from, goal)
	local aiwar = WS.Feature("aiwar")
	if not aiwar.war then return nil, aiwar end
	local lanes = aiwar.laneSets and aiwar.laneSets[team]
	if not lanes then return nil, aiwar end

	local best, bestCost
	for _, lane in ipairs(lanes) do
		if #lane.points > 1 then
			local first, fromDistance = NearestPoint(lane.points, from)
			local last, goalDistance = NearestPoint(lane.points, goal)
			if last >= first then
				local distance = fromDistance + goalDistance
				for i = first + 1, last do
					distance = distance + AsVector(lane.points[i - 1]):Distance(AsVector(lane.points[i]))
				end
				if not bestCost or distance < bestCost then
					best, bestCost = { kind = lane.kind, points = {} }, distance
					for i = first, last do best.points[#best.points + 1] = lane.points[i] end
				end
			end
		end
	end
	return best, aiwar
end

local function EventPoints(points)
	local result = {}
	for i = 1, math.min(#points, MAX_DEBUG_POINTS) do result[i] = AsVector(points[i]) end
	return result
end

local function SendLaneDebug(self)
	if not WS.PathFollowerDebugEventReady then
		if not debugEventWarningSent then
			ErrorNoHalt("[npc_pathfollower] debug event is not loaded; the overlay needs the gamemode's shared files to reload\n")
			debugEventWarningSent = true
		end
		return
	end
	WS.Events.Fire("game_ns_pathfollower_debug", {
		follower = self,
		-- Keep the event shape stable; PathFollower:Draw handles the live path.
		path = {},
		lane = EventPoints(self.nsDebugLanePoints or {}),
	}, self:GetPos())
end

local function NearestLaneTarget(route, position, index)
	if not route then return nil, index end
	index = Lanes.Next(route, { x = position.x, y = position.y, z = position.z }, index)
	local point = Lanes.Target(route, { x = position.x, y = position.y, z = position.z }, index)
	return point, index
end

local function PathKinds(path)
	local kinds = {}
	for _, segment in ipairs(path:GetAllSegments()) do
		local kind = SEGMENT_KINDS[segment.type] or tostring(segment.type)
		kinds[kind] = (kinds[kind] or 0) + 1
	end
	return kinds
end

-- Where a path leaves the ground (a drop, climb, gap or ladder), each with
-- its kind and waypoint, in order: the steps an errand fails on.
local function PathSteps(path)
	local steps = {}
	for _, segment in ipairs(path:GetAllSegments()) do
		if segment.type ~= 0 then
			steps[#steps + 1] = { kind = SEGMENT_KINDS[segment.type] or tostring(segment.type), pos = Point(segment.pos) }
		end
	end
	return steps
end

local SoldierInitialize = ENT.CustomInitialize

function ENT:CustomInitialize()
	SoldierInitialize(self)
	self:SetNoTarget(true)
	self.NSRun = true
	if self.NSToolManaged then
		self:SetNW2Bool("NSPathFollowerDebug", true)
		self:NSSetBehavior("Idle")
	end
end

function ENT:NSSetBehavior(name)
	local previous = self.nsBehavior
	self.nsBehavior = name
	self:NSDebugBehaviorChanged(previous, name)
	self:SetNW2String("NSPathFollowerBehavior", name)
	if name == "Idle" then
		self.NSTarget = nil
		self.nsGoal = nil
		self.nsLaneRoute = nil
		self.nsLaneIndex = nil
		self.NSPathCost = nil
		self:SetNW2Vector("NSPathFollowerGoal", vector_origin)
		self:SetNW2Vector("NSPathFollowerCommand", vector_origin)
		self.nsDebugLanePoints = {}
		SendLaneDebug(self)
		self:NSRepath()
		self.nsFollowedAt = 0
	elseif name ~= "Travel" then
		error("unknown path follower behavior " .. tostring(name), 2)
	end
end

function ENT:NSSetGoal(goal)
	local route, aiwar = LaneRoute(self.NSLaneTeam, self:GetPos(), goal)
	local previous = self.nsBehavior
	self.nsGoal = goal
	self.nsLaneRoute = route
	self.nsLaneIndex = 1
	self.nsBehavior = "Travel"
	self:NSDebugBehaviorChanged(previous, "Travel")
	self:SetNW2String("NSPathFollowerBehavior", "Travel")
	self:SetNW2Vector("NSPathFollowerGoal", goal)
	self.nsDebugLanePoints = route and route.points or {}
	self:SetNW2Vector("NSPathFollowerCommand", vector_origin)
	SendLaneDebug(self)
	self.NSPathCost = nil
	if aiwar and self.NSLaneTeam ~= nil then
		local TFBot = WS.require("foundation.wetsands.path.tfbot")
		local team = self.NSLaneTeam
		self.NSPathCost = aiwar:SoldierPathCost(team, function()
			return {
				entIndex = self:EntIndex(),
				now = CurTime(),
				team = team,
				route = TFBot.FASTEST_ROUTE,
				miniBoss = false,
				roundWon = false,
				winningTeam = WS.TEAM_UNASSIGNED,
			}
		end)
	end
	self.NSPathGoal = nil
	self:NSRepath()
end

local function StopAt(self)
	self:NSSetBehavior("Idle")
	local velocity = self.loco:GetVelocity()
	self.loco:SetVelocity(Vector(0, 0, velocity.z))
end

function ENT:NSUpdateToolBehavior()
	if self.nsBehavior == "Idle" then
		local velocity = self.loco:GetVelocity()
		if velocity.x ~= 0 or velocity.y ~= 0 then self.loco:SetVelocity(Vector(0, 0, velocity.z)) end
		return
	end

	local target = self.nsGoal
	local lanePoint
	lanePoint, self.nsLaneIndex = NearestLaneTarget(self.nsLaneRoute, self:GetPos(), self.nsLaneIndex)
	if lanePoint then
		target = AsVector(lanePoint)
	else
		self.nsLaneRoute = nil
	end
	self.NSTarget = target
	self:NSSteer()

	if self:GetPos():DistToSqr(self.nsGoal) <= ARRIVE * ARRIVE then
		StopAt(self)
	end
end

function ENT:NSSyncDebug()
	local now = CurTime()
	local path = self:GetPath()
	if path and path:IsValid() then path:Draw() end

	if now >= (self.nsNextDebugCommand or 0) then
		self.nsNextDebugCommand = now + DEBUG_COMMAND_SYNC
		local goal = path and path:IsValid() and path:GetCurrentGoal()
		local target = goal and goal.pos or self.NSTarget
		local direction = target and (target - self:GetPos()) or vector_origin
		direction.z = 0
		if direction:Length2DSqr() > 0 then direction:Normalize() end
		self:SetNW2Vector("NSPathFollowerCommand", direction)
	end
end

function ENT:NSSteer(enemy)
	local result = SoldierSteer(self, enemy)
	if self.NSToolManaged then self:NSSyncDebug() end
	return result
end

-- One entry of the report's lists, with when (seconds into the errand) and
-- where.
function ENT:NSNote(list, what, detail)
	local errand = self.nsErrand
	errand[list][#errand[list] + 1] = { at = math.Round(CurTime() - errand.started, 2), pos = Point(self:GetPos()), what = what, detail = detail }
end

function ENT:NSErrand(goal, seconds)
	local now = CurTime()
	self.nsErrand = {
		goal = goal,
		from = self:GetPos(),
		started = now,
		deadline = now + (seconds or DEFAULT_SECONDS),
		nearest = self:GetPos():Distance(goal),
		progressAt = now,
		progressPos = self:GetPos(),
		recoveriesRunning = 0,
		failures = {}, recoveries = {}, nudges = {}, marks = {},
	}
	self.NSTarget = goal
end

-- Its one behaviour, in place of the base's intention: the errand.
function ENT:IntentionUpdate()
	if self.NSToolManaged then return self:NSUpdateToolBehavior() end
	local errand = self.nsErrand
	if not errand or errand.done then return end
	local now, pos = CurTime(), self:GetPos()
	local distance = pos:Distance(errand.goal)
	if distance < errand.nearest then errand.nearest = distance end
	if distance <= ARRIVE then return self:NSFinish("arrived") end
	if now >= errand.deadline then return self:NSFinish("timed out") end
	if errand.lastZ and errand.lastZ - pos.z > DROP_MARK then self:NSNote("marks", "dropped", string.format("%.0f units", errand.lastZ - pos.z)) end
	errand.lastZ = pos.z
	if self.NSRappelling and not errand.rappelling then self:NSNote("marks", "rappelled") end
	errand.rappelling = self.NSRappelling
	self.NSTarget = errand.goal
	self:NSSteer()
	-- a path planned again marked only when it goes another way (its waypoints' kinds)
	local path = self:GetPath()
	if path ~= errand.path and path and path:IsValid() then
		errand.path = path
		local kinds = PathKinds(path)
		local shape = util.TableToJSON(kinds)
		if shape ~= errand.shape then
			errand.shape = shape
			self:NSNote("marks", "path planned", { kinds = kinds, steps = PathSteps(path) })
		end
	end
	local result = self.NSMoveResult
	if result ~= errand.result then
		errand.result = result
		if result == "unreachable" then
			self:NSNote("failures", "no path to the goal")
		elseif result == "vaulted" or result == "hopped" then
			self:NSNote("nudges", result)
		elseif result == "obstacle" then
			self:NSNote("marks", "held by an obstacle")
		end
	end
	if pos:Distance(errand.progressPos) >= PROGRESS then
		errand.progressAt, errand.progressPos, errand.recoveriesRunning = now, pos, 0
	elseif now - errand.progressAt >= RECOVER_AFTER then
		errand.progressAt = now
		errand.recoveriesRunning = errand.recoveriesRunning + 1
		self:NSRepath()
		self:NSNote("recoveries", "no headway: path planned again", string.format("%.0f units from the goal", distance))
		if errand.recoveriesRunning >= NUDGE_AFTER then
			local waypoint = path and path:IsValid() and path:GetCurrentGoal()
			self:NSHop(waypoint and waypoint.pos or errand.goal)
			self:NSNote("nudges", "hop toward the next waypoint", self.NSHopWhy)
		end
	end
end

-- Arrived or out of time: the report, printed, saved and told; then it goes.
function ENT:NSFinish(status)
	local errand = self.nsErrand
	errand.done = true
	if status ~= "arrived" then self:NSNote("failures", status, string.format("%.0f units from the goal", self:GetPos():Distance(errand.goal))) end
	local report = {
		map = game.GetMap(),
		status = status,
		seconds = math.Round(CurTime() - errand.started, 2),
		from = Point(errand.from),
		goal = Point(errand.goal),
		ended = Point(self:GetPos()),
		nearest = math.Round(errand.nearest),
		failures = errand.failures,
		recoveries = errand.recoveries,
		nudges = errand.nudges,
		marks = errand.marks,
	}
	local json = util.TableToJSON(report, true)
	MsgN("[npc_pathfollower] " .. status .. ":\n" .. json)
	file.CreateDir(REPORTS)
	file.Write(string.format("%s%s_%d_%d.json", REPORTS, report.map, self:EntIndex(), os.time()), json)
	self.nsReport = report
	hook.Run("NSPathFollowerDone", self, report)
	SafeRemoveEntityDelayed(self, 0)
end

concommand.Add("ns_pathfollower_send", function(ply, _, args)
	if IsValid(ply) and not ply:IsSuperAdmin() then return end
	local n = {}
	for i = 1, 7 do n[i] = tonumber(args[i]) end
	if not (n[1] and n[2] and n[3] and n[4] and n[5] and n[6]) then
		print("ns_pathfollower_send fromX fromY fromZ toX toY toZ [seconds]")
		return
	end
	local follower = ents.Create("npc_pathfollower")
	follower:SetPos(Vector(n[1], n[2], n[3]))
	follower:Spawn()
	follower:NSErrand(Vector(n[4], n[5], n[6]), n[7])
	ply:AddCleanup("NPC", follower)
	print(string.format("ns_pathfollower_send: #%d sent", follower:EntIndex()))
end, nil, "Send a path follower (NextSoldier's base, no fighting) from one point to another; it reports how it went when it arrives or its time runs out")
