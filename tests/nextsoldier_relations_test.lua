-- nextsoldier.relations: whom a soldier fights, answered when asked (TF2's
-- INextBot::IsEnemy and IsFriend), never pushed to every entity as it
-- changes. Dispositions are the caller's values (GMod's D_HT, D_LI...).
local T = dofile("tests/harness.lua")
local Relations = nextsoldier.relations

local HATE, LIKE, NEUTRAL, FEAR = "hate", "like", "neutral", "fear"

local function New(t)
	return Relations.New({ default = t and t.default or NEUTRAL, ally = LIKE })
end

local function None() return {} end

T.test("with nothing set, everyone gets the default", function()
	local r = New()
	T.eq(r:Disposition("someone", None), NEUTRAL)
end)

T.test("a faction's disposition reaches its members", function()
	local r = New()
	r:SetFaction("red", HATE, 1)
	T.eq(r:Disposition("bob", function() return { "red" } end), HATE)
	T.eq(r:Disposition("alice", function() return { "blue" } end), NEUTRAL)
end)

T.test("an entity's own disposition comes before its factions'", function()
	local r = New()
	r:SetFaction("red", HATE, 1)
	r:SetEntity("medic", LIKE, 1)
	T.eq(r:Disposition("medic", function() return { "red" } end), LIKE)
	r:SetEntity("medic", nil)
	T.eq(r:Disposition("medic", function() return { "red" } end), HATE, "cleared: its factions' again")
end)

T.test("of an entity's factions, the highest priority disposition is the one", function()
	local r = New()
	r:SetFaction("red", HATE, 1)
	r:SetFaction("monsters", FEAR, 5)
	local disposition, priority = r:Disposition("hatman", function() return { "red", "monsters" } end)
	T.eq(disposition, FEAR)
	T.eq(priority, 5)
end)

T.test("a tie between factions goes to the faction first by name", function()
	local r = New()
	r:SetFaction("b", HATE, 1)
	r:SetFaction("a", FEAR, 1)
	T.eq(r:Disposition("x", function() return { "b", "a" } end), FEAR)
end)

T.test("sharing a faction with the soldier is an ally, unless the faction says otherwise", function()
	local r = New()
	r:Join("red")
	T.eq(r:Disposition("mate", function() return { "red" } end), LIKE)
	r:SetFaction("red", HATE, 1)
	T.eq(r:Disposition("mate", function() return { "red" } end), HATE, "set outright")
end)

T.test("joining and leaving factions", function()
	local r = New()
	r:Join("red")
	r:Join("combine")
	r:Join("red")
	T.eq(table.concat(r:Factions(), " "), "combine red")
	T.eq(r:InFaction("red"), true)
	r:Leave("red")
	T.eq(table.concat(r:Factions(), " "), "combine")
	T.eq(r:InFaction("red"), false)
end)

T.test("the other's factions are asked only when its own disposition is not set", function()
	local r = New()
	r:SetEntity("known", HATE, 1)
	local asked = false
	r:Disposition("known", function() asked = true return {} end)
	T.eq(asked, false)
end)

T.test("a disposition without a priority has priority 0", function()
	local r = New()
	r:SetEntity("x", HATE)
	local _, priority = r:Disposition("x", None)
	T.eq(priority, 0)
end)

T.test("a relations without its default or ally is refused", function()
	T.eq(pcall(Relations.New, { ally = LIKE }), false)
	T.eq(pcall(Relations.New, { default = NEUTRAL }), false)
end)

T.finish()
