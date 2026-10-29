-- hostage_entity (CS:S): a hostage. A binding to the hostage controller
-- (features.hostage), which says whom it follows; it walks the nav mesh to
-- that soldier and stands otherwise. It cannot be hurt: RED keeps it, BLU
-- frees it, and the rescue is decided by the rules, not by a corpse.
AddCSLuaFile()

ENT.Type = "nextbot"
ENT.Base = "base_nextbot"
ENT.Spawnable = false

if CLIENT then return end

-- The hostage stops this far from its rescuer.
local FOLLOW_GAP = 90
local SPEED = 190
local PATH_REFRESH = 0.4
local IDLE_WAIT = 0.2
local UNHURT_HEALTH = 1000000
-- A player's body: the models' own bounds reach below the floor.
local HULL_MINS, HULL_MAXS = Vector(-13, -13, 0), Vector(13, 13, 72)
local STEP_HEIGHT, DROP_HEIGHT = 18, 400
-- A hostage that has not moved this long, with its rescuer away, is put on its
-- path's next point.
local STUCK_SECONDS, STUCK_MOVED_SQR = 2, 25
local HOP_LIFT = Vector(0, 0, 4)

function ENT:Initialize()
	local Models = WS.require("features.hostage.models")
	self:SetModel(Models.Pick(self:EntIndex()))
	self:SetCollisionBounds(HULL_MINS, HULL_MAXS)
	self:SetMaxHealth(UNHURT_HEALTH)
	self:SetHealth(UNHURT_HEALTH)
	self.loco:SetDesiredSpeed(SPEED)
	self.loco:SetStepHeight(STEP_HEIGHT)
	self.loco:SetDeathDropHeight(DROP_HEIGHT)
	self.hostage = WS.Feature("hostage")
	self.hostage:Bind(self)
end

function ENT:OnRemove()
	if self.hostage then self.hostage:Unbind(self) end
end

-- Whom the hostage follows (an entity), or nil.
function ENT:SetLeader(leader)
	self.leader = leader
end

-- Led into the rescue zone: out of the round.
function ENT:Rescued()
	self.rescued = true
	self.leader = nil
	self:SetNoDraw(true)
	self:SetNotSolid(true)
end

function ENT:FollowLeader(leader)
	local path = Path("Follow")
	path:SetMinLookAheadDistance(100)
	path:SetGoalTolerance(FOLLOW_GAP * 0.6)
	path:Compute(self, leader:GetPos())
	local lastPos, lastMoved = self:GetPos(), CurTime()
	while path:IsValid() and IsValid(leader) and leader == self.leader and not self.rescued
		and self:GetPos():Distance(leader:GetPos()) > FOLLOW_GAP do
		if path:GetAge() > PATH_REFRESH then path:Compute(self, leader:GetPos()) end
		path:Update(self)
		if self:GetPos():DistToSqr(lastPos) > STUCK_MOVED_SQR then
			lastPos, lastMoved = self:GetPos(), CurTime()
		elseif CurTime() - lastMoved > STUCK_SECONDS then
			local goal = path:GetCurrentGoal()
			if goal then self:SetPos(goal.pos + HOP_LIFT) end
			lastPos, lastMoved = self:GetPos(), CurTime()
		end
		coroutine.yield()
	end
end

function ENT:RunBehaviour()
	while true do
		local leader = self.leader
		if not self.rescued and IsValid(leader) and self:GetPos():Distance(leader:GetPos()) > FOLLOW_GAP then
			self:StartActivity(ACT_RUN)
			self.loco:SetDesiredSpeed(SPEED)
			self:FollowLeader(leader)
			-- no path, or the leader reached: never spin without yielding
			coroutine.wait(IDLE_WAIT)
		else
			self:StartActivity(ACT_IDLE)
			coroutine.wait(IDLE_WAIT)
		end
	end
end
