-- npc_pathfollower: NextSoldier's base on an errand, a bench for its
-- navigation (the operator's). It walks to a goal by the base's
-- locomotion and the war soldier's movement (WS.WarSoldier: its climbs,
-- vaults, hops and rappels), fights nothing and is no one's target, and
-- when it arrives or its time runs out it reports how it went: whether it
-- arrived, and every failure, recovery, nudge and mark on the way, each
-- with when and where. The report is printed, saved under data/ (REPORTS)
-- and told (hook NSPathFollowerDone(follower, report)); then it goes.
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

if CLIENT then return end

-- Within ARRIVE of its goal it has arrived.
local ARRIVE = 48
-- Gaining less than PROGRESS toward its goal in RECOVER_AFTER seconds, it
-- recovers: its path planned again; after NUDGE_AFTER recoveries running,
-- it is nudged as well (a hop or a vault toward its goal).
local PROGRESS, RECOVER_AFTER, NUDGE_AFTER = 32, 3, 2
-- A fall of more than this between two updates is marked.
local DROP_MARK = 64
local DEFAULT_SECONDS = 60
local REPORTS = "sandcastle/pathfollower/"

local function Point(v) return { x = math.Round(v.x), y = math.Round(v.y), z = math.Round(v.z) } end

-- A path's waypoints by kind (the engine's segment types).
local SEGMENT_KINDS = { [0] = "ground", "drop", "climb", "gap", "ladder up", "ladder down" }

local function PathKinds(path)
	local kinds = {}
	for _, segment in ipairs(path:GetAllSegments()) do
		local kind = SEGMENT_KINDS[segment.type] or tostring(segment.type)
		kinds[kind] = (kinds[kind] or 0) + 1
	end
	return kinds
end

local SoldierInitialize = ENT.CustomInitialize

function ENT:CustomInitialize()
	SoldierInitialize(self)
	self:SetNoTarget(true)
	self.NSRun = true
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
		progressDistance = self:GetPos():Distance(goal),
		recoveriesRunning = 0,
		failures = {}, recoveries = {}, nudges = {}, marks = {},
	}
	self.NSTarget = goal
end

-- Its one behaviour, in place of the base's intention: the errand.
function ENT:IntentionUpdate()
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
	local path = self:GetPath()
	if path ~= errand.path and path and path:IsValid() then
		errand.path = path
		self:NSNote("marks", "path planned", PathKinds(path))
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
	if errand.progressDistance - distance >= PROGRESS then
		errand.progressAt, errand.progressDistance, errand.recoveriesRunning = now, distance, 0
	elseif now - errand.progressAt >= RECOVER_AFTER then
		errand.progressAt = now
		errand.recoveriesRunning = errand.recoveriesRunning + 1
		self:NSRepath()
		self:NSNote("recoveries", "no headway: path planned again", string.format("%.0f units from the goal", distance))
		if errand.recoveriesRunning >= NUDGE_AFTER then
			self:NSHop(errand.goal)
			self:NSNote("nudges", "hop toward the goal", self.NSHopWhy)
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
	print(string.format("ns_pathfollower_send: #%d sent", follower:EntIndex()))
end, nil, "Send a path follower (NextSoldier's base, no fighting) from one point to another; it reports how it went when it arrives or its time runs out")
