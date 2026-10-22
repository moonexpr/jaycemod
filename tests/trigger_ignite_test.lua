-- foundation.hazards.ignite: trigger_ignite (CTriggerIgnite, tf_triggers.cpp)
-- on cp_lavapit_final's lava (burn_duration 5, damage_percent_per_second 4),
-- driven on a fake clock against a fake player port.
local T = dofile("tests/harness.lua")
local Ignite = T.require("foundation.hazards.ignite")
local Players = T.require("games.gameplay.players")

local COND = Players.COND
local IGNITE, DAMAGE = Ignite.IGNITE, Ignite.DAMAGE
local STEP = Ignite.BURN_INTERVAL
local LAVA_BURN, LAVA_PERCENT = 5, 4 -- cp_lavapit_final's lava
local SOLDIER_HEALTH, SCOUT_HEALTH = 200, 125

-- The lava's damage over `seconds` to a player of max health `health`.
local function BurnOver(seconds, health)
	return seconds * LAVA_PERCENT / 100 * health
end
local START = 50

-- The player port: conditions and max health by target, as the players'
-- condition system keeps them. An IGNITE with a duration sets them burning.
local function FakePlayers()
	local port = {
		conds = {},
		max = {},
	}
	function port:InCond(target, cond) return self.conds[target][cond] == true end
	function port:MaxHealth(target) return self.max[target] end
	function port:Add(target, maxHealth)
		self.conds[target] = {}
		self.max[target] = maxHealth
	end
	function port:Apply(events)
		for _, e in ipairs(events) do
			if e.kind == IGNITE and e.duration then self.conds[e.target][COND.BURNING] = true end
		end
		return events
	end
	return port
end

local function Lava(port)
	return Ignite.New({
		burnDuration = LAVA_BURN,
		damagePercentPerSecond = LAVA_PERCENT,
	}, port)
end

local function Describe(events)
	local out = {}
	for _, e in ipairs(events) do
		if e.kind == IGNITE then
			out[#out + 1] = string.format("%s:%s:%s", e.kind, e.target, tostring(e.duration))
		else
			out[#out + 1] = string.format("%s:%s:%.3f", e.kind, e.target, e.amount)
		end
	end
	return table.concat(out, ",")
end

local function Ignited(target, duration)
	return string.format("%s:%s:%s", IGNITE, target, tostring(duration))
end

local function Damaged(target, amount)
	return string.format("%s:%s:%.3f", DAMAGE, target, amount)
end

T.test("the defaults are CTriggerIgnite's", function()
	local ignite = Ignite.New({}, FakePlayers())
	T.eq(Ignite.BURN_DURATION_DEFAULT, 1, "burn_duration")
	T.eq(Ignite.DAMAGE_PERCENT_DEFAULT, 10, "damage_percent_per_second")
	T.defined(Ignite.BURN_INTERVAL, "BURN_INTERVAL")
	T.eq(ignite:NextBurn(), nil, "idle until touched")
end)

T.test("a player walking in catches fire, then burns by his max health every interval", function()
	local port = FakePlayers()
	port:Add("scout", SCOUT_HEALTH)
	local lava = Lava(port)
	T.eq(Describe(port:Apply(lava:StartTouch(START, "scout"))), Ignited("scout", LAVA_BURN), "StartTouch ignites")
	T.near(lava:NextBurn(), START + STEP, 1e-9, "BurnThink armed")
	T.eq(Describe(lava:Think(START + STEP / 2)), "", "not due yet")
	-- an interval's worth of LAVA_PERCENT of his max health, and he is already burning
	T.eq(Describe(lava:Think(START + STEP)), Damaged("scout", BurnOver(STEP, SCOUT_HEALTH)), "the first burn")
	T.eq(Describe(lava:Think(START + 2 * STEP)), Damaged("scout", BurnOver(STEP, SCOUT_HEALTH)), "the second")
end)

T.test("the damage is by the time since the last burn, so a late think burns more", function()
	local port = FakePlayers()
	port:Add("soldier", SOLDIER_HEALTH)
	local lava = Lava(port)
	port:Apply(lava:StartTouch(START, "soldier"))
	local late = STEP * 2.5
	T.eq(Describe(lava:Think(START + late)), Damaged("soldier", BurnOver(late, SOLDIER_HEALTH)), "two and a half intervals' worth")
	T.near(lava:NextBurn(), START + late + STEP, 1e-9, "next burn from now")
end)

T.test("a player whose fire went out is ignited again before the burn", function()
	local port = FakePlayers()
	port:Add("scout", SCOUT_HEALTH)
	local lava = Lava(port)
	port:Apply(lava:StartTouch(START, "scout"))
	port.conds.scout[COND.BURNING] = nil
	T.eq(Describe(port:Apply(lava:Think(START + STEP))), Ignited("scout", LAVA_BURN) .. "," .. Damaged("scout", BurnOver(STEP, SCOUT_HEALTH)), "ignite, then damage")
	T.eq(Describe(lava:Think(START + 2 * STEP)), Damaged("scout", BurnOver(STEP, SCOUT_HEALTH)), "burning: damage only")
end)

T.test("an invulnerable player gets the effects, no fire, and still the damage", function()
	for _, cond in ipairs({ COND.INVULNERABLE, COND.INVULNERABLE_USER_BUFF, COND.INVULNERABLE_HIDE_UNLESS_DAMAGED, COND.INVULNERABLE_CARD_EFFECT }) do
		local port = FakePlayers()
		port:Add("medic", SCOUT_HEALTH)
		port.conds.medic[cond] = true
		local lava = Lava(port)
		T.eq(Describe(port:Apply(lava:StartTouch(START, "medic"))), Ignited("medic", nil), "effects only, cond " .. cond)
		T.eq(Describe(lava:Think(START + STEP)), Damaged("medic", BurnOver(STEP, SCOUT_HEALTH)), "TakeDamage regardless, cond " .. cond)
	end
end)

T.test("an already burning player walking in gets the effects without a new fire", function()
	local port = FakePlayers()
	port:Add("pyro", SCOUT_HEALTH)
	port.conds.pyro[COND.BURNING] = true
	local lava = Lava(port)
	T.eq(Describe(lava:StartTouch(START, "pyro")), Ignited("pyro", nil), "no SelfBurn")
end)

T.test("everyone burns in the order they walked in", function()
	local port = FakePlayers()
	port:Add("scout", SCOUT_HEALTH)
	port:Add("soldier", SOLDIER_HEALTH)
	local lava = Lava(port)
	port:Apply(lava:StartTouch(START, "soldier"))
	port:Apply(lava:StartTouch(START + STEP / 2, "scout"))
	T.eq(Describe(lava:Think(START + STEP)), Damaged("soldier", BurnOver(STEP, SOLDIER_HEALTH)) .. "," .. Damaged("scout", BurnOver(STEP, SCOUT_HEALTH)), "both, by entry")
end)

T.test("the last player leaving stops the burn; walking back in starts afresh", function()
	local port = FakePlayers()
	port:Add("scout", SCOUT_HEALTH)
	local lava = Lava(port)
	port:Apply(lava:StartTouch(START, "scout"))
	lava:Think(START + STEP)
	lava:EndTouch("scout")
	T.eq(Describe(lava:Think(START + 2 * STEP)), "", "nobody to burn")
	T.eq(lava:NextBurn(), nil, "BurnThink stopped")
	port.conds.scout[COND.BURNING] = nil
	T.eq(Describe(port:Apply(lava:StartTouch(START + 10, "scout"))), Ignited("scout", LAVA_BURN), "ignited again")
	T.eq(Describe(lava:Think(START + 10 + STEP)), Damaged("scout", BurnOver(STEP, SCOUT_HEALTH)), "no damage for the time away")
end)

T.test("one of two leaving keeps the other burning", function()
	local port = FakePlayers()
	port:Add("scout", SCOUT_HEALTH)
	port:Add("soldier", SOLDIER_HEALTH)
	local lava = Lava(port)
	port:Apply(lava:StartTouch(START, "scout"))
	port:Apply(lava:StartTouch(START, "soldier"))
	lava:EndTouch("scout")
	T.eq(Describe(lava:Think(START + STEP)), Damaged("soldier", BurnOver(STEP, SOLDIER_HEALTH)), "the soldier only")
end)

T.finish()
