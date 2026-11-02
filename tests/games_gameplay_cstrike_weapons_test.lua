-- CS:S weapons are ordinary SWEP definitions with grouped terminal stats.
local T = dofile("tests/harness.lua")

local CLASSES = {
	"weapon_glock", "weapon_usp", "weapon_p228", "weapon_deagle", "weapon_elite", "weapon_fiveseven",
	"weapon_m3", "weapon_xm1014", "weapon_mac10", "weapon_tmp", "weapon_mp5navy", "weapon_ump45", "weapon_p90",
	"weapon_galil", "weapon_famas", "weapon_ak47", "weapon_m4a1", "weapon_sg552", "weapon_aug",
	"weapon_scout", "weapon_awp", "weapon_g3sg1", "weapon_sg550", "weapon_m249",
	"weapon_knife", "weapon_hegrenade", "weapon_flashbang", "weapon_smokegrenade",
}

local function Definition(class)
	local path = "addons/cstrike_weapons/lua/weapons/" .. class .. ".lua"
	local env = {
		SWEP = {},
		AddCSLuaFile = function() end,
		Model = function(model) return { precached = model } end,
	}
	setmetatable(env, { __index = _G })
	setfenv(assert(loadfile(path)), env)()
	return env.SWEP
end

local function Base()
	local env = {
		SWEP = {},
		AddCSLuaFile = function() end,
		CLIENT = false,
		DMG_BULLET = 1,
		TRACER_LINE_AND_WHIZ = 2,
		ACT_VM_ATTACH_SILENCER = 3,
		ACT_VM_DETACH_SILENCER = 4,
		HITGROUP_GENERIC = 0,
		HITGROUP_HEAD = 1,
		HITGROUP_CHEST = 2,
		HITGROUP_STOMACH = 3,
		HITGROUP_LEFTARM = 4,
		HITGROUP_RIGHTARM = 5,
		HITGROUP_LEFTLEG = 6,
		HITGROUP_RIGHTLEG = 7,
		HITGROUP_GEAR = 10,
		SERVER = false,
		CurTime = function() return 10 end,
		game = { AddAmmoType = function() end },
		util = { SharedRandom = function() return 0.5 end },
	}
	setmetatable(env, { __index = _G })
	setfenv(assert(loadfile("addons/cstrike_weapons/lua/weapons/base_cstrike.lua")), env)()
	return env.SWEP
end

T.test("all CS:S weapons are terminal SWEP definitions with grouped stats", function()
	for _, class in ipairs(CLASSES) do
		local definition = Definition(class)
		T.eq(definition.CStrikeWeapon, true, class .. " identifies its damage behavior")
		T.eq(definition.PrintName ~= nil, true, class .. " has a display name")
		T.eq(definition.ViewModel.precached ~= nil, true, class .. " precaches its view model")
		T.eq(definition.WorldModel.precached ~= nil, true, class .. " precaches its world model")
		T.eq(definition.CSS, nil, class .. " has no local CSS table")
		T.eq(definition.NextSoldier, nil, class .. " has no NextSoldier stats table")
		T.eq(definition.Arms, nil, class .. " has no AI stats table")
		T.eq(definition.Grenade, nil, class .. " has no grenade stats table")
		T.eq(type(definition.Primary), "table", class .. " uses the standard SWEP Primary table")
		T.eq(type(definition.Secondary), "table", class .. " uses the standard SWEP Secondary table")
		for key, value in pairs(definition) do
			if type(value) == "table" and key ~= "Primary" and key ~= "Secondary"
				and key ~= "ViewModel" and key ~= "WorldModel" and key ~= "Stats" then
				error(class .. " stores stats in nested " .. key)
			end
		end
		if definition.CStrikeType == "Knife" then
			T.eq(definition.Base, "base_cstrike_melee", "knife shares melee behavior")
			T.eq(definition.SlashDamage, 15, "slash damage")
			T.eq(definition.StabDamage, 65, "stab damage")
		elseif definition.CStrikeType == "Grenade" then
			T.eq(definition.Base, "base_cstrike_grenade", class .. " shares grenade behavior")
			T.eq(type(definition.GrenadeFuse), "number", class .. " owns its fuse")
			T.eq(type(definition.GrenadeProjectile), "string", class .. " owns its projectile class")
		else
			T.eq(definition.Base, "base_cstrike", class .. " shares firearm behavior")
			T.eq(type(definition.Stats.Ballistics.Damage), "number", class .. " owns its damage")
			T.eq(type(definition.Stats.Accuracy.Stand), "number", class .. " owns its accuracy")
			T.eq(type(definition.SoldierDamage), "number", class .. " owns soldier damage")
			T.eq(type(definition.AIReach), "number", class .. " owns AI reach")
		end
	end
end)

T.test("terminal SWEPs group firearm modes and stats", function()
	local ak = Definition("weapon_ak47")
	T.eq(ak.Stats.Ballistics.Damage, 36)
	T.eq(ak.Primary.ClipSize, 30)
	T.eq(ak.Stats.Accuracy.Stand, 0.00916)
	T.eq(ak.Stats.Kick.UpBase, 1)

	local m4 = Definition("weapon_m4a1")
	T.eq(m4.Stats.Mode.Type, "silencer")
	T.eq(m4.SpecialSound1 ~= nil, true, "silenced shot sound")

	local glock = Definition("weapon_glock")
	T.eq(glock.Stats.Mode.Type, "burst")
	T.eq(glock.Stats.Mode.Burst.Rounds, 3)

	local awp = Definition("weapon_awp")
	T.eq(awp.Stats.Mode.Type, "scope")
	T.eq(awp.Stats.Mode.FOV[1], 40)
end)

T.test("firearm modes apply their terminal movement speed and sounds", function()
	local base = Base()
	local scopeState = { zoom = 0, rezoom = 0 }
	local scope = setmetatable({
		MaxPlayerSpeed = 210,
		Stats = { Mode = { Type = "scope", Speed = 150 } },
	}, { __index = base })
	function scope:GetZoom() return scopeState.zoom end
	function scope:GetRezoom() return scopeState.rezoom end
	T.eq(scope:GetMaxSpeed(), 210, "unscoped speed")
	scopeState.zoom = 1
	T.eq(scope:GetMaxSpeed(), 150, "scoped speed")
	scopeState.rezoom = 11
	T.eq(scope:GetMaxSpeed(), 210, "speed while scope returns")

	local attached, sounds = false, {}
	local silencer = setmetatable({
		Stats = { Mode = { Type = "silencer" } },
		SpecialSound2 = "silencer.off",
		SpecialSound3 = "silencer.on",
	}, { __index = base })
	function silencer:GetOwner() return { IsPlayer = function() return true end } end
	function silencer:GetSecond() return attached end
	function silencer:SetSecond(value) attached = value end
	function silencer:SendWeaponAnim() end
	function silencer:ViewDuration() return 0.5 end
	function silencer:SetNextPrimaryFire() end
	function silencer:SetNextSecondaryFire() end
	function silencer:EmitSound(sound) sounds[#sounds + 1] = sound end
	silencer:SecondaryAttack()
	silencer:SecondaryAttack()
	T.eq(table.concat(sounds, ","), "silencer.on,silencer.off", "toggle sounds")
end)

T.test("the firearm base calculates damage, movement inaccuracy and spray", function()
	local base = Base()
	local weapon = setmetatable({
		Stats = {
			Ballistics = { Damage = 36, Range = 8192, RangeModifier = 0.98, BulletCount = 3 },
			Accuracy = {
				Stand = 0.00916,
				Crouch = 0.00687,
				Jump = 0.43044,
				Ladder = 0.10761,
				Move = 0.09222,
				Spread = 0.0006,
			},
		},
		MaxPlayerSpeed = 221,
	}, { __index = base })
	function weapon:Mode() return nil end
	function weapon:UsesSecondAccuracy() return false end
	T.near(weapon:DamageAt(0, 1), 144, 1e-9, "head damage")
	T.near(weapon:DamageAt(500, 2), 36 * 0.98, 1e-9, "range falloff")
	T.eq(weapon:DamageAt(9000, 2), 0, "out of range")
	function weapon:UsesSecondAccuracy() return true end
	weapon.Stats.AlternateAccuracy = { Fire = 0.02 }
	T.eq(weapon:AccuracyValue("Fire"), 0.02, "alternate accuracy override")
	T.eq(weapon:AccuracyValue("Stand"), 0.00916, "alternate accuracy fallback")
	function weapon:UsesSecondAccuracy() return false end
	T.near(weapon:Inaccuracy({ penalty = 0, speed = 0, onGround = true }), 0, 1e-9)
	T.near(weapon:Inaccuracy({ penalty = 0, speed = 221, onGround = true }), 0.09222, 1e-9)
	T.near(weapon:Inaccuracy({ penalty = 0, speed = 0, onGround = false }), 0.43044, 1e-9)
	T.eq(#weapon:Spray(0.05), 3)
end)

T.test("knife and grenade stats live on their terminal SWEPs", function()
	local knife = Definition("weapon_knife")
	T.eq(knife.SlashFirstDamage, 20)
	T.eq(knife.SlashFreshWindow, 0.4)
	T.eq(knife.BackstabMultiplier, 3)
	T.eq(knife.BackstabDot, 0.8)
	local flash = Definition("weapon_flashbang")
	T.eq(flash.GrenadeBlind, 4.9)
	T.eq(flash.GrenadeRadius, 1500)
	local he = Definition("weapon_hegrenade")
	T.eq(he.GrenadeDamage, 100)
	T.eq(he.GrenadeFuse, 1.5)
	T.eq(he.GrenadeRadius, 350)
end)

T.finish()
