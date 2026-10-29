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

function ENT:Initialize()
	local Models = WS.require("features.hostage.models")
	self:SetModel(Models.Pick(self:EntIndex()))
	self:SetMaxHealth(UNHURT_HEALTH)
	self:SetHealth(UNHURT_HEALTH)
	self.loco:SetDesiredSpeed(SPEED)
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
	while path:IsValid() and IsValid(leader) and leader == self.leader and not self.rescued
		and self:GetPos():Distance(leader:GetPos()) > FOLLOW_GAP do
		if path:GetAge() > PATH_REFRESH then path:Compute(self, leader:GetPos()) end
		path:Update(self)
		if self.loco:IsStuck() then
			self:HandleStuck()
			return
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
		else
			self:StartActivity(ACT_IDLE)
			coroutine.wait(IDLE_WAIT)
		end
	end
end
