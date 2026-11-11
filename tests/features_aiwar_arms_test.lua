-- features.aiwar.arms: every soldier carries a primary, a secondary and a
-- melee weapon, and holds the one for its enemy's distance: the melee weapon
-- face to face, the primary within its reach, beyond that whichever of the
-- two guns is more precise (a shotgunner's pistol). It fires at any enemy it
-- sees, from the moment it calls them out, not only within DrGBase's range
-- for the hold type.
local T = dofile ("tests/harness.lua")
local Arms = T.require ("features.aiwar.arms")

local function Definition (class)
	local path = "addons/cstrike_weapons/lua/weapons/" .. class .. ".lua"
	local definition = { SWEP = {}, AddCSLuaFile = function () end, Model = function (path) return path end }
	setmetatable (definition, { __index = _G })
	local chunk = assert (loadfile (path))
	setfenv (chunk, definition) ()
	return definition.SWEP
end

local function Refused (fn, ...)
	local ok = pcall (fn, ...)
	T.eq (ok, false, "refused")
end

local function First () return 1 end

T.test ("a loadout is a primary, a secondary and a melee weapon, all three known", function ()
	local loadout = Arms.Loadout ({ primary = { "weapon_shotgun" }, secondary = "weapon_pistol", melee = "weapon_stunstick" }, First)
	T.eq (loadout.primary,                            "weapon_shotgun",                                "primary")
	T.eq (loadout.secondary,                          "weapon_pistol",                                 "secondary")
	T.eq (loadout.melee,                              "weapon_stunstick",                              "melee")
	T.eq (table.concat (Arms.Classes (loadout), " "), "weapon_shotgun weapon_pistol weapon_stunstick", "carried, in slot order")
	Refused (Arms.Loadout, { primary = { "weapon_shotgun" }, melee = "weapon_stunstick" }, First)
	Refused (Arms.Loadout, { primary = { "weapon_shotgun" }, secondary = "weapon_pistol" }, First)
	Refused (Arms.Loadout, { primary = { "not_a_weapon" }, secondary = "weapon_pistol", melee = "weapon_crowbar" }, First)
	Refused (Arms.Loadout, { primary = { "weapon_crowbar" }, secondary = "weapon_pistol", melee = "weapon_stunstick" }, First)
	Refused (Arms.Loadout, { primary = { "weapon_ar2" }, secondary = "weapon_pistol", melee = "weapon_pistol" }, First)
end)

T.test ("a kit's primary may be one of several, drawn at random", function ()
	local drawn
	local loadout = Arms.Loadout ({ primary = { "weapon_ar2", "weapon_smg1" }, secondary = "weapon_pistol", melee = "weapon_stunstick" },
		function (n) drawn = n return 2 end)
	T.eq (drawn,           2,             "from both")
	T.eq (loadout.primary, "weapon_smg1", "the one drawn")
end)

T.test ("face to face it holds its melee weapon", function ()
	local loadout = Arms.Loadout ({ primary = { "weapon_ar2" }, secondary = "weapon_pistol", melee = "weapon_stunstick" }, First)
	T.eq (Arms.Choose (loadout, Arms.MELEE_SWITCH),     "weapon_stunstick", "at arm's length")
	T.eq (Arms.Choose (loadout, Arms.MELEE_SWITCH + 1), "weapon_ar2",       "a step farther: the gun")
end)

T.test ("within its primary's reach it holds the primary; beyond, the more precise gun", function ()
	local shotgunner = Arms.Loadout ({ primary = { "weapon_shotgun" }, secondary = "weapon_pistol", melee = "weapon_stunstick" }, First)
	local reach = Arms.Reach ("weapon_shotgun")
	T.eq (Arms.Choose (shotgunner, reach),     "weapon_shotgun", "within the shotgun's reach")
	T.eq (Arms.Choose (shotgunner, reach + 1), "weapon_pistol",  "beyond it, the pistol")
	local rifleman = Arms.Loadout ({ primary = { "weapon_ar2" }, secondary = "weapon_pistol", melee = "weapon_stunstick" }, First)
	T.eq (Arms.Choose (rifleman, 1000), "weapon_ar2",    "the rifle in its reach")
	T.eq (Arms.Choose (rifleman, 4000), "weapon_pistol", "the pistol, more precise, far off")
	local marksman = Arms.Loadout ({ primary = { "weapon_crossbow" }, secondary = "weapon_pistol", melee = "weapon_crowbar" }, First)
	T.eq (Arms.Choose (marksman, 6000), "weapon_crossbow", "the crossbow is the more precise far off")
end)

T.test ("precision runs crossbow, 357, pistol, rifle, smg, shotgun", function ()
	local order = { "weapon_crossbow", "weapon_357", "weapon_pistol", "weapon_ar2", "weapon_smg1", "weapon_shotgun" }
	for i = 1, #order - 1 do
		T.eq (Arms.Cone (order [i]) < Arms.Cone (order [i + 1]), true, order [i] .. " before " .. order [i + 1])
	end
end)

T.test ("a gun fires at any enemy in sight; a melee weapon only at arm's length", function ()
	local gun = Arms.Ranges ("weapon_shotgun")
	T.eq (gun.attack, math.huge, "no range limit: it fires once it calls them out")
	T.eq (gun.melee,  0,         "no melee with a gun")
	local club = Arms.Ranges ("weapon_stunstick")
	T.eq (club.attack,                           0,                "no shots with a club")
	T.eq (club.melee,                            Arms.MELEE_REACH, "its reach")
	T.eq (Arms.MELEE_REACH <= Arms.MELEE_SWITCH, true,             "drawn before it can strike")
	T.eq (Arms.Ranges ("weapon_physcannon"),     nil,              "a weapon it does not know: DrGBase's own ranges")
end)

-- Half-Life's crowbar (CCrowbar::Swing): a hit swings again 0.25 seconds on.
T.test ("a melee weapon strikes for its damage, as fast as Half-Life's crowbar", function ()
	T.eq (Arms.Damage ("weapon_crowbar") > 0, true, "the crowbar hurts")
	T.eq (Arms.Interval ("weapon_crowbar"),   0.25, "the crowbar")
	T.eq (Arms.Interval ("weapon_stunstick"), 0.25, "the stunstick too")
end)

T.test ("the automatic arms are the SMG, the AR2 and the melee weapons; the rest fire once a press", function ()
	for _, class in ipairs ({ "weapon_smg1", "weapon_ar2", "weapon_crowbar", "weapon_stunstick" }) do
		T.eq (Arms.Automatic (class), true, class)
	end
	for _, class in ipairs ({ "weapon_crossbow", "weapon_357", "weapon_pistol", "weapon_shotgun" }) do
		T.eq (Arms.Automatic (class), false, class)
	end
end)

-- CS:S stats come from terminal SWEP fields; no class registry is involved.
T.test ("the soldiers choose among CS:S weapons from their SWEP fields", function ()
	local loadout = Arms.Loadout ({ primary = { "weapon_ak47" }, secondary = "weapon_glock", melee = "weapon_knife" }, First)
	T.eq (loadout.primary, "weapon_ak47", "a CS:S kit")
	local ak, glock, mac = Definition ("weapon_ak47"), Definition ("weapon_glock"), Definition ("weapon_mac10")
	local knife = Definition ("weapon_knife")
	T.eq (Arms.Automatic (ak),                 true,     "the AK fires automatically")
	T.eq (type (Arms.Reach (ak)),              "number", "the AK has an AI reach")
	T.eq (Arms.Melee (knife),                  true,     "the knife")
	T.eq (Arms.Damage (knife),                 15,       "a slash")
	T.eq (Arms.Cone (glock) < Arms.Cone (mac), true,     "a pistol's precision over a MAC-10's")
	local steadier = Arms.Cone (glock) < Arms.Cone (ak) and "weapon_glock" or "weapon_ak47"
	T.eq (Arms.Choose (loadout, Arms.Reach (ak) + 1, ak, glock), steadier, "past the rifle's reach, the steadier gun")
end)

-- What a bot picks of what its class gave it.
local function Carried (class) return { GetClass = function () return class end, class = class } end
local function Usable () return true end
local MP5, SHOTGUN, CROSSBOW, CROWBAR, RPG = Carried ("weapon_bmesa_mp5"), Carried ("weapon_bmesa_shotgun"),
Carried ("weapon_bmesa_crossbow"), Carried ("weapon_bmesa_crowbar"), Carried ("weapon_bmesa_rpg")
local PHYSGUN, TOOL, SIMPLE = Carried ("weapon_physgun"), Carried ("gmod_tool"), Carried ("simple_hl2_smg1")
local ALL = { PHYSGUN, TOOL, SIMPLE, CROSSBOW, MP5, SHOTGUN, CROWBAR }
-- The distance between two guns' reaches, and past the longest.
local CLOSE = Arms.Reach (SHOTGUN) - 1
local MIDDLING = Arms.Reach (SHOTGUN) + 1
local FAR = Arms.Reach (MP5) + 1
local BEYOND = Arms.Reach (CROSSBOW) + 1

T.test ("every Black Mesa gun can be aimed, measured and approached", function ()
	for _, name in ipairs ({ "glock", "357", "mp5", "shotgun", "crossbow", "rpg", "tau", "gluon", "hivehand" }) do
		local gun = Carried ("weapon_bmesa_" .. name)
		local ranges = Arms.Ranges (gun)
		T.eq (type (Arms.Cone (gun)),                                           "number", name .. "'s cone")
		T.eq (ranges.avoid < ranges.chase and ranges.chase <= Arms.Reach (gun), true,     name .. " backs off nearer than it closes")
	end
	T.eq (Arms.Melee (CROWBAR), true, "its crowbar is melee")
end)

T.test ("a gun that spreads wider reaches less far", function ()
	T.eq (Arms.Cone (SHOTGUN) > Arms.Cone (MP5) and Arms.Reach (SHOTGUN) < Arms.Reach (MP5), true, "the shotgun's pellets")
end)

T.test ("a rocket's blast keeps it from being fired within its own radius", function ()
	T.eq (Arms.Minimum (RPG) > 0,                        true, "it has a nearest")
	T.eq (Arms.Ranges (RPG).avoid >= Arms.Minimum (RPG), true, "and backs off to it")
	T.eq (Arms.Minimum (MP5),                            0,    "a gun has none")
end)

T.test ("it picks the weapon made for the distance: the shortest reach that covers it", function ()
	T.eq (Arms.Pick (ALL, CLOSE, nil, Usable),    SHOTGUN,  "close")
	T.eq (Arms.Pick (ALL, MIDDLING, nil, Usable), MP5,      "middling")
	T.eq (Arms.Pick (ALL, FAR, nil, Usable),      CROSSBOW, "far")
end)

T.test ("beyond every reach, the longest it has", function ()
	T.eq (Arms.Pick ({ MP5, SHOTGUN }, BEYOND, nil, Usable), MP5, "the nearest it can come")
end)

T.test ("within arm's length it takes its melee weapon", function ()
	T.eq (Arms.Pick (ALL, Arms.MELEE_SWITCH - 1, nil, Usable), CROWBAR, "swinging")
end)

T.test ("tools, and weapons not measured, are never picked", function ()
	T.eq (Arms.Pick ({ PHYSGUN, TOOL, SIMPLE }, 500, nil, Usable), nil, "nothing to fight with")
end)

T.test ("an empty gun is passed over, and with none left it takes its melee weapon", function ()
	local function NotShotgun (weapon) return weapon ~= SHOTGUN end
	T.eq (Arms.Pick (ALL, CLOSE, nil, NotShotgun), MP5, "the next that covers it")
	local function NoGuns (weapon) return weapon == CROWBAR end
	T.eq (Arms.Pick (ALL, CLOSE, nil, NoGuns), CROWBAR, "swinging")
end)

T.test ("what it holds it keeps while it still covers the distance, so it does not fidget", function ()
	T.eq (Arms.Pick (ALL, CLOSE, MP5, Usable),  MP5,      "the shotgun would fit better, not enough to swap")
	T.eq (Arms.Pick (ALL, FAR, MP5, Usable),    CROSSBOW, "out of its reach, it swaps")
	T.eq (Arms.Pick (ALL, CLOSE, TOOL, Usable), SHOTGUN,  "a tool is no weapon to keep")
	local function NotMp5 (weapon) return weapon ~= MP5 end
	T.eq (Arms.Pick (ALL, CLOSE, MP5, NotMp5),                 SHOTGUN, "nor is an empty one")
	T.eq (Arms.Pick (ALL, Arms.MELEE_SWITCH - 1, MP5, Usable), CROWBAR, "at arm's length it swings")
end)

T.test ("a long gun in hand is not kept for an enemy well within what fits it", function ()
	T.eq (Arms.Pick (ALL, Arms.MELEE_SWITCH + 1, CROSSBOW, Usable),    SHOTGUN, "a crossbow, face to face")
	T.eq (Arms.Pick ({ RPG, MP5 }, Arms.Reach (MP5) / 2, RPG, Usable), MP5,     "a rocket, at a rifle's distance")
	T.eq (Arms.Pick (ALL, Arms.IDLE_DISTANCE, RPG, Usable),            MP5,     "and with no enemy it readies itself")
end)

T.test ("a rocket is not fired nor kept in hand inside its blast", function ()
	local near = Arms.Minimum (RPG) - 1
	T.eq (Arms.Pick ({ RPG, MP5 }, near, RPG, Usable),       MP5,     "it swaps away from one in hand")
	T.eq (Arms.Pick ({ RPG, MP5 }, near, nil, Usable),       MP5,     "and does not pick one up")
	T.eq (Arms.Pick ({ RPG, CROWBAR }, near, nil, Usable),   CROWBAR, "with nothing else, it swings")
	T.eq (Arms.Pick ({ RPG }, near, nil, Usable),            nil,     "with only that, it holds nothing to fire")
	T.eq (Arms.Pick ({ RPG, SHOTGUN }, BEYOND, nil, Usable), RPG,     "far off, it is the one for the job")
end)

T.finish ()
