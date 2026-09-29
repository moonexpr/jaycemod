-- foundation.spells.tf2: TF2's spell set (g_NormalSpellList, g_RareSpellList,
-- g_generalSpellIndexList) and the strategy parts it names.
local T = dofile("tests/harness.lua")
local Tf2 = T.require("foundation.spells.tf2")

local S = Tf2

local function Want(charges, kind, speedScale)
	return {
		charges = charges,
		kind = kind,
		speedScale = speedScale,
	}
end

local EXPECTED = {
	[S.SPELL_FIREBALL] = Want(2, S.KIND_ROCKET, 1),
	[S.SPELL_BATS] = Want(2, S.KIND_JAR, 1),
	[S.SPELL_OVERHEAL] = Want(1, S.KIND_SELF, 1),
	[S.SPELL_MIRV] = Want(1, S.KIND_JAR, 1),
	[S.SPELL_BLASTJUMP] = Want(2, S.KIND_SELF, 1),
	[S.SPELL_STEALTH] = Want(1, S.KIND_SELF, 1),
	[S.SPELL_TELEPORT] = Want(2, S.KIND_JAR, 1),
	[S.SPELL_LIGHTNING] = Want(1, S.KIND_ROCKET, 0.4),
	[S.SPELL_ATHLETIC] = Want(1, S.KIND_SELF, 1),
	[S.SPELL_METEOR] = Want(1, S.KIND_JAR, 1),
	[S.SPELL_SPAWN_BOSS] = Want(1, S.KIND_JAR, 1),
	[S.SPELL_SKELETON_HORDE] = Want(1, S.KIND_JAR, 1),
}

T.test("twelve spells, indexed as TF2 does", function()
	T.eq(S.COUNT, 12, "COUNT")
	T.eq(S.SPELL_FIREBALL, 0, "fireball first")
	T.eq(S.SPELL_SKELETON_HORDE, S.COUNT - 1, "horde last")
	T.eq(S.TIER_COMMON, 0, "common tier")
	T.eq(S.TIER_RARE, 1, "rare tier")
	T.eq(S.ROLL_TIME, 2, "roll time")
	T.eq(S.CAST_COOLDOWN, 0.5, "cooldown")
end)

T.test("charges, kinds and speeds", function()
	for index = 0, S.COUNT - 1 do
		local def, want = S.Definition(index), EXPECTED[index]
		T.eq(def.charges, want.charges, "charges of " .. def.name)
		T.eq(def.kind, want.kind, "kind of " .. def.name)
		T.eq(def.speedScale, want.speedScale, "speed of " .. def.name)
		T.eq(def.icon:sub(1, #"vgui/spellbook_"), "vgui/spellbook_", "icon of " .. def.name)
		T.eq(def.castSound:sub(1, #"Halloween."), "Halloween.", "cast sound of " .. def.name)
	end
	T.eq(S.Definition(S.SPELL_SPAWN_BOSS).castSound, "Halloween.Merasmus_Spell", "the boss's sound")
	T.eq(S.Definition(S.SPELL_SPAWN_BOSS).icon, "vgui/spellbook_boss", "the boss's icon")
end)

T.test("COMMON_ROLL: indices 0-5 four times each, then lightning, athletic and meteor once", function()
	T.eq(#S.COMMON_ROLL, 27, "27 entries")
	local counts = {}
	for _, index in ipairs(S.COMMON_ROLL) do counts[index] = (counts[index] or 0) + 1 end
	for index = S.SPELL_FIREBALL, S.SPELL_STEALTH do T.eq(counts[index], 4, "four of " .. index) end
	T.eq(counts[S.SPELL_LIGHTNING], 1, "one lightning")
	T.eq(counts[S.SPELL_ATHLETIC], 1, "one athletic")
	T.eq(counts[S.SPELL_METEOR], 1, "one meteor")
	T.eq(counts[S.SPELL_TELEPORT], nil, "teleport is never common")
	T.eq(counts[S.SPELL_SPAWN_BOSS], nil, "boss is never common")
	T.eq(counts[S.SPELL_SKELETON_HORDE], nil, "horde is never common")
end)

T.test("a common roll draws one COMMON_ROLL entry", function()
	local asked
	local index = S.Roll(S.TIER_COMMON, function(lo, hi)
		asked = { lo, hi }
		return 27
	end)
	T.eq(asked[1], 1, "from the first entry")
	T.eq(asked[2], 27, "to the last")
	T.eq(index, S.SPELL_METEOR, "the last entry is meteor")
end)

T.test("a rare roll is uniform over lightning to horde", function()
	local asked
	S.Roll(S.TIER_RARE, function(lo, hi)
		asked = { lo, hi }
		return lo
	end)
	T.eq(asked[1], S.SPELL_LIGHTNING, "lightning is the lowest")
	T.eq(asked[2], S.SPELL_SKELETON_HORDE, "horde the highest")
	for draw = S.SPELL_LIGHTNING, S.SPELL_SKELETON_HORDE do
		local index = S.Roll(S.TIER_RARE, function() return draw end)
		T.eq(index >= S.SPELL_LIGHTNING and index <= S.SPELL_SKELETON_HORDE, true, "rare " .. index)
	end
end)

T.test("each index names a strategy part that registers that index", function()
	for index = 0, S.COUNT - 1 do
		local part = T.require(S.Strategy(index))
		T.eq(part.INDEX, index, S.Strategy(index))
		T.eq(type(part.Cast), "function", S.Strategy(index) .. " casts")
		if S.Definition(index).kind ~= S.KIND_SELF then
			T.eq(type(part.PROJECTILE), "string", S.Strategy(index) .. " throws a class")
			T.eq(type(part.Impact), "function", S.Strategy(index) .. " has an impact")
		end
	end
end)

T.finish()
