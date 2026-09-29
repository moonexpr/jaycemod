-- The AI war's soldier: a DrGBase human NextBot (drgbase_nextbot_human,
-- github.com/Dragoteryx/drgbase, which the AI war requires) that fights as
-- DrGBase's human AI does (aiming, firing, reloading, chasing and keeping
-- its distance by weapon) while the war's orders steer it. The controller
-- (features/aiwar) sets WetsandTarget, a position to go to, WetsandRun,
-- whether to run there, and WetsandDisarmed, whether it may attack (a
-- losing side's humiliation). With a target, the soldier walks it whatever
-- else it does, firing on the way at an enemy in sight; without one it is
-- left to DrGBase: fighting an enemy, else standing.
-- wetsand_drg_combine and wetsand_drg_rebel are its two sides.
if not DrGBase then return end

ENT.Base = "drgbase_nextbot_human"
ENT.Type = "nextbot"
ENT.PrintName = "Sandcastle Soldier"
ENT.Category = "Sandcastle"
ENT.Spawnable = false

ENT.SpawnHealth = 100
ENT.WalkSpeed = 90
ENT.RunSpeed = 220
ENT.RagdollOnDeath = true

local GOAL_TOLERANCE = 32

if SERVER then
	AddCSLuaFile()

	-- Walks the controller's target, if it has one: true when it does.
	function ENT:WetsandSteer()
		local target = self.WetsandTarget
		if not target then return false end
		self.WetsandMoveResult = self:FollowPath(target, GOAL_TOLERANCE)
		return true
	end

	-- No enemy: the target, else stand (DrGBase would wander off at random).
	function ENT:OnIdle()
		self:WetsandSteer()
	end

	-- An enemy: with a target the soldier keeps to it, and HandleEnemy
	-- still aims and fires at the enemy in sight; without one, DrGBase's
	-- own chase, retreat and facing.
	function ENT:OnChaseEnemy()
		return self:WetsandSteer()
	end

	function ENT:OnAvoidEnemy()
		return self:WetsandSteer()
	end

	function ENT:OnIdleEnemy()
		return self:WetsandSteer()
	end

	-- Returning true skips DrGBase's firing: the humiliated do not attack.
	function ENT:OnRangeAttack()
		if self.WetsandDisarmed then return true end
	end

	function ENT:OnMeleeAttack()
		if self.WetsandDisarmed then return true end
	end

	function ENT:ShouldRun()
		if self.WetsandRun ~= nil then return self.WetsandRun end
		return self:HasEnemy()
	end
end
