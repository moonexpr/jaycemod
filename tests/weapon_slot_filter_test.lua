local T = dofile("tests/harness.lua")
local Filter = T.require("games.gameplay.combat.weapon_slot_filter")
local Actor = T.require("games.npc.actor")

local function Hit(byPlayer, dmgType)
	return {
		byPlayer = byPlayer,
		dmgType = dmgType,
	}
end

local MELEE, OTHER = Filter.SLOT_MELEE, Filter.SLOT_PRIMARY
local NOT_NEGATED, NEGATED = false, true

T.test("the melee slot passes a player's club and slash damage", function()
	T.eq(Filter.PassesDamage(MELEE, NOT_NEGATED, Hit(true, Actor.DMG_CLUB)), true, "club")
	T.eq(Filter.PassesDamage(MELEE, NOT_NEGATED, Hit(true, Actor.DMG_SLASH)), true, "slash")
	T.eq(Filter.PassesDamage(MELEE, NOT_NEGATED, Hit(true, Actor.DMG_CLUB + Actor.DMG_BURN)), true, "a burning club")
end)

T.test("the melee slot refuses other damage, and anything not from a player", function()
	T.eq(Filter.PassesDamage(MELEE, NOT_NEGATED, Hit(true, Actor.DMG_BLAST)), false, "a rocket")
	T.eq(Filter.PassesDamage(MELEE, NOT_NEGATED, Hit(true, Actor.DMG_GENERIC)), false, "generic")
	T.eq(Filter.PassesDamage(MELEE, NOT_NEGATED, Hit(false, Actor.DMG_SLASH)), false, "a skeleton's swing has no weapon")
end)

T.test("Negated turns the answer round", function()
	T.eq(Filter.PassesDamage(MELEE, NEGATED, Hit(true, Actor.DMG_CLUB)), false, "melee")
	T.eq(Filter.PassesDamage(MELEE, NEGATED, Hit(true, Actor.DMG_BLAST)), true, "blast")
end)

T.test("other slots are not supported and pass no damage", function()
	T.eq(Filter.Supported(MELEE), true, "melee")
	T.eq(Filter.Supported(OTHER), false, "primary")
	T.eq(Filter.PassesDamage(OTHER, NOT_NEGATED, Hit(true, Actor.DMG_CLUB)), false, "primary")
end)

T.test("as an entity filter it passes everyone unless negated (PassesFilterImpl)", function()
	T.eq(Filter.PassesEntity(NOT_NEGATED), true, "plain")
	T.eq(Filter.PassesEntity(NEGATED), false, "negated")
end)

T.finish()
