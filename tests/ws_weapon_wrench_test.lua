-- entities/weapons/weapon_wrench.lua: TF2's wrench. Its swing hurries or mends a teammate's building
-- (base_obj's Wrench) and hits anything else as a club.
local T = dofile("tests/harness.lua")
local Buildings = gameplay.buildings

local FILE = "addons/sandcastle/gamemodes/sandcastle/entities/weapons/weapon_wrench.lua"
local RED, BLUE = 2, 3

-- Enough of a Vector for a swing's line: added, and scaled.
local Vec = {}
Vec.__index = Vec
Vec.__add = function(a, b) return setmetatable({ a[1] + b[1], a[2] + b[2], a[3] + b[3] }, Vec) end
Vec.__mul = function(a, k) return setmetatable({ a[1] * k, a[2] * k, a[3] * k }, Vec) end
local function V(x, y, z) return setmetatable({ x, y, z }, Vec) end

-- The wrench in its owner's hands, RED, its swing landing on `hit` (an entity, or nil for the air).
local function Wrench(hit)
	local world = { sounds = {}, damage = {}, now = 10 }
	local SWEP = {}
	local owner = {
		team = RED,
		GetShootPos = function() return V(0, 0, 0) end,
		GetAimVector = function() return V(1, 0, 0) end,
		SetAnimation = function() end,
		LagCompensation = function() end,
	}
	local function Trace() return { Hit = hit ~= nil, Entity = hit, HitPos = {} } end
	local env = setmetatable({
		SWEP = SWEP, SERVER = true, CLIENT = false, AddCSLuaFile = function() end,
		ACT_VM_HITCENTER = 1, ACT_VM_MISSCENTER = 2, PLAYER_ATTACK1 = 0, DMG_CLUB = 128, MASK_SHOT_HULL = 1,
		CurTime = function() return world.now end,
		IsValid = function(ent) return ent ~= nil end,
		Vector = V,
		util = { TraceLine = Trace, TraceHull = Trace },
		WS = { TeamNumber = function(ent) return ent.team end },
		DamageInfo = function()
			local info = {}
			-- SetDamage(v) and the like set what Damage and the like read back.
			return setmetatable({}, { __index = function(_, key)
				if key:sub(1, 3) ~= "Set" then return info[key] end
				return function(_, value) info[key:sub(4)] = value end
			end })
		end,
		math = setmetatable({ random = function() return 1 end }, { __index = math }),
	}, { __index = _G })
	setfenv(assert(loadfile(FILE)), env)()
	function SWEP:GetOwner() return owner end
	function SWEP:SetNextPrimaryFire(at) world.nextFire = at end
	function SWEP:SendWeaponAnim(act) world.anim = act end
	function SWEP:EmitSound(sound) world.sounds[#world.sounds + 1] = sound end
	return SWEP, world
end

-- A building of team, answering the wrench as base_obj does: mended or not.
local function Building(team, mends)
	local building = { team = team, wrenched = 0 }
	function building:GetObjTeam() return self.team end
	function building:Wrench() self.wrenched = self.wrenched + 1 return mends end
	function building:TakeDamageInfo(info) self.hurt = info end
	function building:IsPlayer() return false end
	function building:IsNPC() return false end
	return building
end

T.test("a swing at a teammate's building tends it, never hurts it", function()
	local building = Building(RED, true)
	local wrench, world = Wrench(building)
	wrench:PrimaryAttack()
	T.eq(building.wrenched, 1, "tended")
	T.eq(building.hurt, nil, "unhurt")
	T.eq(world.nextFire, world.now + Buildings.WRENCH_INTERVAL, "at the wrench's pace")
	T.eq(world.anim, 1, "a hit")
end)

T.test("a teammate's building that needed nothing sounds otherwise than one tended", function()
	local tended, tendedWorld = Wrench(Building(RED, true))
	tended:PrimaryAttack()
	local whole, wholeWorld = Wrench(Building(RED, false))
	whole:PrimaryAttack()
	T.eq(tendedWorld.sounds[1] ~= wholeWorld.sounds[1], true, "told apart by ear")
end)

T.test("a swing at an enemy's building hits it as a club", function()
	local building = Building(BLUE, true)
	local wrench = Wrench(building)
	wrench:PrimaryAttack()
	T.eq(building.wrenched, 0, "never tended")
	T.eq(building.hurt.Damage, Buildings.WRENCH_DAMAGE, "the wrench's damage")
	T.eq(building.hurt.DamageType, 128, "a club's")
end)

T.test("a swing at nothing misses", function()
	local wrench, world = Wrench(nil)
	wrench:PrimaryAttack()
	T.eq(world.anim, 2, "a miss")
	T.eq(#world.sounds, 1, "its swing heard")
end)

T.finish()
