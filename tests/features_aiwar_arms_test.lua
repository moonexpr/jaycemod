-- features.aiwar.arms: every soldier carries a primary, a secondary and a
-- melee weapon, and holds the one for its enemy's distance: the melee weapon
-- face to face, the primary within its reach, beyond that whichever of the
-- two guns is more precise (a shotgunner's pistol). It fires at any enemy it
-- sees, from the moment it calls them out, not only within DrGBase's range
-- for the hold type.
local T = dofile("tests/harness.lua")
local Arms = T.require("features.aiwar.arms")

local function Definition(class)
	local path = "addons/sandcastle/gamemodes/sandcastle/entities/weapons/" .. class .. ".lua"
	local definition = { SWEP = {}, AddCSLuaFile = function() end, Model = function(path) return path end }
	setmetatable(definition, { __index = _G })
	local chunk = assert(loadfile(path))
	setfenv(chunk, definition)()
	return definition.SWEP
end

local function Refused(fn, ...)
	local ok = pcall(fn, ...)
	T.eq(ok, false, "refused")
end

local function First() return 1 end

T.test("a loadout is a primary, a secondary and a melee weapon, all three known", function()
	local loadout = Arms.Loadout({ primary = { "weapon_shotgun" }, secondary = "weapon_pistol", melee = "weapon_stunstick" }, First)
	T.eq(loadout.primary, "weapon_shotgun", "primary")
	T.eq(loadout.secondary, "weapon_pistol", "secondary")
	T.eq(loadout.melee, "weapon_stunstick", "melee")
	T.eq(table.concat(Arms.Classes(loadout), " "), "weapon_shotgun weapon_pistol weapon_stunstick", "carried, in slot order")
	Refused(Arms.Loadout, { primary = { "weapon_shotgun" }, melee = "weapon_stunstick" }, First)
	Refused(Arms.Loadout, { primary = { "weapon_shotgun" }, secondary = "weapon_pistol" }, First)
	Refused(Arms.Loadout, { primary = { "not_a_weapon" }, secondary = "weapon_pistol", melee = "weapon_crowbar" }, First)
	Refused(Arms.Loadout, { primary = { "weapon_crowbar" }, secondary = "weapon_pistol", melee = "weapon_stunstick" }, First)
	Refused(Arms.Loadout, { primary = { "weapon_ar2" }, secondary = "weapon_pistol", melee = "weapon_pistol" }, First)
end)

T.test("a kit's primary may be one of several, drawn at random", function()
	local drawn
	local loadout = Arms.Loadout({ primary = { "weapon_ar2", "weapon_smg1" }, secondary = "weapon_pistol", melee = "weapon_stunstick" },
		function(n) drawn = n return 2 end)
	T.eq(drawn, 2, "from both")
	T.eq(loadout.primary, "weapon_smg1", "the one drawn")
end)

T.test("face to face it holds its melee weapon", function()
	local loadout = Arms.Loadout({ primary = { "weapon_ar2" }, secondary = "weapon_pistol", melee = "weapon_stunstick" }, First)
	T.eq(Arms.Choose(loadout, Arms.MELEE_SWITCH), "weapon_stunstick", "at arm's length")
	T.eq(Arms.Choose(loadout, Arms.MELEE_SWITCH + 1), "weapon_ar2", "a step farther: the gun")
end)

T.test("within its primary's reach it holds the primary; beyond, the more precise gun", function()
	local shotgunner = Arms.Loadout({ primary = { "weapon_shotgun" }, secondary = "weapon_pistol", melee = "weapon_stunstick" }, First)
	local reach = Arms.Reach("weapon_shotgun")
	T.eq(Arms.Choose(shotgunner, reach), "weapon_shotgun", "within the shotgun's reach")
	T.eq(Arms.Choose(shotgunner, reach + 1), "weapon_pistol", "beyond it, the pistol")
	local rifleman = Arms.Loadout({ primary = { "weapon_ar2" }, secondary = "weapon_pistol", melee = "weapon_stunstick" }, First)
	T.eq(Arms.Choose(rifleman, 1000), "weapon_ar2", "the rifle in its reach")
	T.eq(Arms.Choose(rifleman, 4000), "weapon_pistol", "the pistol, more precise, far off")
	local marksman = Arms.Loadout({ primary = { "weapon_crossbow" }, secondary = "weapon_pistol", melee = "weapon_crowbar" }, First)
	T.eq(Arms.Choose(marksman, 6000), "weapon_crossbow", "the crossbow is the more precise far off")
end)

T.test("precision runs crossbow, 357, pistol, rifle, smg, shotgun", function()
	local order = { "weapon_crossbow", "weapon_357", "weapon_pistol", "weapon_ar2", "weapon_smg1", "weapon_shotgun" }
	for i = 1, #order - 1 do
		T.eq(Arms.Cone(order[i]) < Arms.Cone(order[i + 1]), true, order[i] .. " before " .. order[i + 1])
	end
end)

T.test("a gun fires at any enemy in sight; a melee weapon only at arm's length", function()
	local gun = Arms.Ranges("weapon_shotgun")
	T.eq(gun.attack, math.huge, "no range limit: it fires once it calls them out")
	T.eq(gun.melee, 0, "no melee with a gun")
	local club = Arms.Ranges("weapon_stunstick")
	T.eq(club.attack, 0, "no shots with a club")
	T.eq(club.melee, Arms.MELEE_REACH, "its reach")
	T.eq(Arms.MELEE_REACH <= Arms.MELEE_SWITCH, true, "drawn before it can strike")
	T.eq(Arms.Ranges("weapon_physcannon"), nil, "a weapon it does not know: DrGBase's own ranges")
end)

-- Half-Life's crowbar (CCrowbar::Swing): a hit swings again 0.25 seconds on.
T.test("a melee weapon strikes for its damage, as fast as Half-Life's crowbar", function()
	T.eq(Arms.Damage("weapon_crowbar") > 0, true, "the crowbar hurts")
	T.eq(Arms.Interval("weapon_crowbar"), 0.25, "the crowbar")
	T.eq(Arms.Interval("weapon_stunstick"), 0.25, "the stunstick too")
end)

T.test("the automatic arms are the SMG, the AR2 and the melee weapons; the rest fire once a press", function()
	for _, class in ipairs({ "weapon_smg1", "weapon_ar2", "weapon_crowbar", "weapon_stunstick" }) do
		T.eq(Arms.Automatic(class), true, class)
	end
	for _, class in ipairs({ "weapon_crossbow", "weapon_357", "weapon_pistol", "weapon_shotgun" }) do
		T.eq(Arms.Automatic(class), false, class)
	end
end)

-- CS:S stats come from terminal SWEP fields; no class registry is involved.
T.test("the soldiers choose among CS:S weapons from their SWEP fields", function()
	local loadout = Arms.Loadout({ primary = { "weapon_ak47" }, secondary = "weapon_glock", melee = "weapon_knife" }, First)
	T.eq(loadout.primary, "weapon_ak47", "a CS:S kit")
	local ak, glock, mac = Definition("weapon_ak47"), Definition("weapon_glock"), Definition("weapon_mac10")
	local knife = Definition("weapon_knife")
	T.eq(Arms.Automatic(ak), true, "the AK fires automatically")
	T.eq(type(Arms.Reach(ak)), "number", "the AK has an AI reach")
	T.eq(Arms.Melee(knife), true, "the knife")
	T.eq(Arms.Damage(knife), 15, "a slash")
	T.eq(Arms.Cone(glock) < Arms.Cone(mac), true, "a pistol's precision over a MAC-10's")
	local steadier = Arms.Cone(glock) < Arms.Cone(ak) and "weapon_glock" or "weapon_ak47"
	T.eq(Arms.Choose(loadout, Arms.Reach(ak) + 1, ak, glock), steadier, "past the rifle's reach, the steadier gun")
end)

T.finish()
