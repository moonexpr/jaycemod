local T = dofile("tests/harness.lua")
local Fake = dofile("tests/fake_actor.lua")
local Holiday = T.require("foundation.holiday")
local Halloween = T.require("foundation.holiday.halloween")

local V = Fake.Vector
local MINUTE = 60

local function New(overrides)
	local config = {
		mapHoliday = Holiday.NONE,
		forced = Holiday.NONE,
		spellsForced = false,
		modes = { Halloween },
	}
	for k, v in pairs(overrides or {}) do config[k] = v end
	return Holiday.New(config)
end

T.test("the holidays keep EHoliday's numbers", function()
	T.eq(Holiday.NONE, 0, "none")
	T.eq(Holiday.BIRTHDAY, 1, "birthday")
	T.eq(Holiday.HALLOWEEN, 2, "halloween")
	T.eq(Holiday.CHRISTMAS, 3, "christmas")
	T.eq(Holiday.VALENTINES, 6, "valentines")
	T.eq(Holiday.FULLMOON, 8, "full moon")
	T.eq(Holiday.HALLOWEEN_OR_FULLMOON, 9, "halloween or full moon")
	T.eq(Holiday.HALLOWEEN_OR_FULLMOON_OR_VALENTINES, 10, "halloween or full moon or valentines")
end)

-- TF_IsHolidayActive, with no calendar

T.test("a Halloween map is Halloween, and runs the Halloween mode", function()
	local h = New({ mapHoliday = Holiday.HALLOWEEN })
	T.eq(h:Active(Holiday.HALLOWEEN), true, "halloween")
	T.eq(h:Active(Holiday.HALLOWEEN_OR_FULLMOON), true, "halloween or full moon")
	T.eq(h:Active(Holiday.FULLMOON), false, "not a full moon")
	T.eq(h:Active(Holiday.CHRISTMAS), false, "not christmas")
	T.eq(h:Mode(), Halloween, "mode")
end)

T.test("tf_forced_holiday makes any map Halloween", function()
	local h = New({ forced = Holiday.HALLOWEEN })
	T.eq(h:Active(Holiday.HALLOWEEN), true, "forced halloween")
	T.eq(h:Mode(), Halloween, "mode")
	local either = New({ forced = Holiday.HALLOWEEN_OR_FULLMOON })
	T.eq(either:Active(Holiday.HALLOWEEN), true, "halloween-or-full-moon forces halloween")
	T.eq(either:Active(Holiday.FULLMOON), true, "and the full moon")
	T.eq(either:Active(Holiday.CHRISTMAS), false, "not christmas")
end)

T.test("a Christmas map is Christmas and has no mode", function()
	local h = New({ mapHoliday = Holiday.CHRISTMAS })
	T.eq(h:Active(Holiday.CHRISTMAS), true, "christmas")
	T.eq(h:Active(Holiday.HALLOWEEN), false, "not halloween")
	T.eq(h:Active(Holiday.HALLOWEEN_OR_FULLMOON), false, "not halloween or full moon")
	T.eq(h:Mode(), nil, "no mode")
	T.eq(New({ forced = Holiday.CHRISTMAS }):Active(Holiday.CHRISTMAS), true, "forced christmas")
end)

T.test("a full-moon map counts for halloween-or-full-moon only", function()
	local h = New({ mapHoliday = Holiday.FULLMOON })
	T.eq(h:Active(Holiday.HALLOWEEN_OR_FULLMOON), true, "either")
	T.eq(h:Active(Holiday.HALLOWEEN), false, "not halloween")
	T.eq(h:Mode(), nil, "no mode")
end)

T.test("a map with no holiday has none until its holiday entity binds", function()
	local h = New()
	T.eq(h:Active(Holiday.HALLOWEEN), false, "not yet")
	T.eq(h:Mode(), nil, "no mode yet")
	h:SetMapHoliday(Holiday.HALLOWEEN)
	T.eq(h:Active(Holiday.HALLOWEEN), true, "bound")
	T.eq(h:Mode(), Halloween, "mode")
end)

-- CTFGameRules::IsUsingSpells

T.test("spells turn on and off, and report whether they changed", function()
	local h = New()
	T.eq(h:UsingSpells(), false, "off at first")
	T.eq(h:SetUsingSpells(true), true, "turned on")
	T.eq(h:UsingSpells(), true, "on")
	T.eq(h:SetUsingSpells(true), false, "already on")
	T.eq(h:SetUsingSpells(false), true, "turned off")
	T.eq(h:UsingSpells(), false, "off")
end)

T.test("tf_spells_enabled keeps spells on", function()
	local h = New({ spellsForced = true })
	T.eq(h:UsingSpells(), true, "forced on")
	T.eq(h:SetUsingSpells(true), false, "no change turning on")
	T.eq(h:SetUsingSpells(false), false, "no change turning off")
	T.eq(h:UsingSpells(), true, "still on")
end)

-- IsUsingSpells's map-name check (HALLOWEEN_SCENARIO_HIGHTOWER), made
-- entity-driven: a map that places tf_spell_pickup uses spells.

T.test("a map that places a spell pickup uses spells", function()
	local h = New()
	T.eq(h:SpellPickupPlaced(), true, "the first placed pickup turns spells on")
	T.eq(h:UsingSpells(), true, "on")
	T.eq(h:SpellPickupPlaced(), false, "a second one changes nothing")
	T.eq(h:SetUsingSpells(false), false, "HalloweenSetUsingSpells 0 leaves a pickup map's spells on")
	T.eq(h:UsingSpells(), true, "still on")
end)

T.test("a placed pickup changes nothing once spells are on", function()
	T.eq(New({ spellsForced = true }):SpellPickupPlaced(), false, "tf_spells_enabled")
	local h = New()
	h:SetUsingSpells(true)
	T.eq(h:SpellPickupPlaced(), false, "HalloweenSetUsingSpells 1")
	T.eq(h:SetUsingSpells(false), false, "the placed pickup keeps them on")
end)

-- CTFGameRules::DropSpellPickup

local function Floats(fractions)
	local r = Fake.Random(fractions)
	return function(lo, hi) return r:Float(lo, hi) end
end

T.test("a spell drop needs spells on", function()
	T.eq(New():SpellDrop(V(0, 0, 0), Floats({ 0.5 }), V), nil, "spells off")
end)

T.test("a spell drop starts 50 up and flies at 500 up and a little sideways", function()
	local h = New()
	h:SetUsingSpells(true)
	local drop = h:SpellDrop(V(100, 200, 0), Floats({ 1, 0 }), V)
	T.eq(drop.position, V(100, 200, Holiday.SPELL_DROP_HEIGHT), "position")
	local expected = V(0.5, -0.5, 1):GetNormalized() * Holiday.SPELL_DROP_SPEED
	T.near(drop.velocity.x, expected.x, 1e-9, "x")
	T.near(drop.velocity.y, expected.y, 1e-9, "y")
	T.near(drop.velocity.z, expected.z, 1e-9, "z")
	T.eq(Holiday.SPELL_DROP_HEIGHT, 50, "height")
	T.eq(Holiday.SPELL_DROP_SPEED, 500, "speed")
	local straight = h:SpellDrop(V(0, 0, 0), Floats({ 0.5 }), V)
	T.eq(straight.velocity, V(0, 0, Holiday.SPELL_DROP_SPEED), "no sideways draw")
end)

-- The Halloween mode (CTFGameRules::PeriodicHalloweenUpdate)

T.test("the Halloween mode announces IT and gifts last 240 s", function()
	T.eq(Halloween.HOLIDAY, Holiday.HALLOWEEN, "holiday")
	T.eq(Halloween.ANNOUNCES_IT, true, "announces IT")
	T.eq(Halloween.LIFETIME, 240, "tf_halloween_gift_lifetime")
end)

local function Ints(fractions)
	local r = Fake.Random(fractions)
	return function(lo, hi) return r:Int(lo, hi) end
end

T.test("gifts wait for a location before the clock starts", function()
	local schedule = Halloween.GiftSchedule(Ints({ 0 }))
	local players = { "scout" }
	T.eq(#schedule:Tick(0, players, {}), 0, "no locations")
	T.eq(#schedule:Tick(20 * MINUTE, players, {}), 0, "still none")
	local locations = { V(1, 0, 0) }
	T.eq(#schedule:Tick(20 * MINUTE, players, locations), 0, "the clock starts")
	T.eq(#schedule:Tick(27 * MINUTE - 1, players, locations), 0, "7 minutes not up")
	T.eq(#schedule:Tick(27 * MINUTE, players, locations), 1, "7 minutes after the first location")
end)

T.test("a gift for every player at a random location every 7 to 12 minutes", function()
	-- Draws, in order: first delay (7), then per round the next delay, then
	-- one location per player.
	local draws = {
		0, -- first delay: 7 minutes
		1, -- next delay: 12 minutes
		0, -- scout's location: the first
		1, -- heavy's location: the last
		0.5, -- next delay: 10 minutes
		0.5, -- scout's location: the middle
		0.5, -- heavy's location: the middle
	}
	local schedule = Halloween.GiftSchedule(Ints(draws))
	local locations = { V(1, 0, 0), V(2, 0, 0), V(3, 0, 0) }
	local players = { "scout", "heavy" }
	local start = 100
	T.eq(#schedule:Tick(start, players, locations), 0, "starts the clock")
	T.eq(#schedule:Tick(start + 7 * MINUTE - 1, players, locations), 0, "before 7 minutes")
	local gifts = schedule:Tick(start + 7 * MINUTE, players, locations)
	T.eq(#gifts, 2, "one per player")
	T.eq(gifts[1].player, "scout", "first player")
	T.eq(gifts[1].location, locations[1], "first location")
	T.eq(gifts[2].player, "heavy", "second player")
	T.eq(gifts[2].location, locations[3], "last location")
	T.eq(#schedule:Tick(start + 7 * MINUTE, players, locations), 0, "once")
	T.eq(#schedule:Tick(start + 19 * MINUTE - 1, players, locations), 0, "before 12 more minutes")
	gifts = schedule:Tick(start + 19 * MINUTE, players, locations)
	T.eq(#gifts, 2, "second round")
	T.eq(gifts[1].location, locations[2], "middle location")
	T.eq(#schedule:Tick(start + 29 * MINUTE - 1, players, locations), 0, "before 10 more minutes")
	T.eq(#schedule:Tick(start + 29 * MINUTE, players, locations), 2, "third round")
end)

T.test("a round with no players spends its turn", function()
	local schedule = Halloween.GiftSchedule(Ints({ 0 }))
	local locations = { V(1, 0, 0) }
	schedule:Tick(0, {}, locations)
	T.eq(#schedule:Tick(7 * MINUTE, {}, locations), 0, "nobody to give to")
	T.eq(#schedule:Tick(7 * MINUTE + 1, { "pyro" }, locations), 0, "the next round is 7 minutes on")
	T.eq(#schedule:Tick(14 * MINUTE, { "pyro" }, locations), 1, "next round")
end)

T.finish()
