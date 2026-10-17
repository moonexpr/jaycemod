-- The holiday system: which holiday is on (TF_IsHolidayActive, with no
-- calendar), whether spells are (CTFGameRules::IsUsingSpells), and the mode
-- that runs for the active holiday.
--
-- New{ mapHoliday, forced, spellsForced, modes }: mapHoliday is the map's
-- tf_logic_holiday holiday_type (NONE until one binds), forced the
-- tf_forced_holiday convar, spellsForced the tf_spells_enabled convar, and
-- modes the holiday modes the controller registers.
--
-- A holiday mode is a part (foundation.holiday.<name>) providing HOLIDAY,
-- ANNOUNCES_IT (whether the IT warnings play) and
-- GiftSchedule(random) -> schedule | nil.
local ipairs, setmetatable = ipairs, setmetatable
module(...)

-- EHoliday (econ_item_constants.h)
NONE = 0
BIRTHDAY = 1
HALLOWEEN = 2
CHRISTMAS = 3
VALENTINES = 6
FULLMOON = 8
HALLOWEEN_OR_FULLMOON = 9
HALLOWEEN_OR_FULLMOON_OR_VALENTINES = 10
APRIL_FOOLS = 11

-- CTFGameRules::DropSpellPickup
SPELL_DROP_HEIGHT = 50
SPELL_DROP_SPEED = 500
SPELL_DROP_SPREAD = 0.5

-- BIsCvarIndicatingHolidayIsActive: the forced values that count for each
-- holiday. Holidays are not a bitfield.
local FORCED_COUNTS = {
	[BIRTHDAY] = { BIRTHDAY },
	[HALLOWEEN] = { HALLOWEEN, HALLOWEEN_OR_FULLMOON, HALLOWEEN_OR_FULLMOON_OR_VALENTINES },
	[CHRISTMAS] = { CHRISTMAS },
	[VALENTINES] = { VALENTINES, HALLOWEEN_OR_FULLMOON_OR_VALENTINES },
	[FULLMOON] = { FULLMOON, HALLOWEEN_OR_FULLMOON, HALLOWEEN_OR_FULLMOON_OR_VALENTINES },
	[HALLOWEEN_OR_FULLMOON] = {
		HALLOWEEN,
		FULLMOON,
		HALLOWEEN_OR_FULLMOON,
		HALLOWEEN_OR_FULLMOON_OR_VALENTINES,
	},
	[HALLOWEEN_OR_FULLMOON_OR_VALENTINES] = {
		HALLOWEEN,
		FULLMOON,
		VALENTINES,
		HALLOWEEN_OR_FULLMOON,
		HALLOWEEN_OR_FULLMOON_OR_VALENTINES,
	},
	[APRIL_FOOLS] = { APRIL_FOOLS },
}

-- TF_IsHolidayActive's map check: HALLOWEEN_OR_FULLMOON also accepts a map
-- of either.
local MAP_COUNTS = {
	[HALLOWEEN_OR_FULLMOON] = { HALLOWEEN, FULLMOON, HALLOWEEN_OR_FULLMOON },
}

local function Contains(list, value)
	for _, v in ipairs(list or {}) do
		if v == value then return true end
	end
	return false
end

local Holiday = {}
Holiday.__index = Holiday

function New(config)
	return setmetatable({
		mapHoliday = config.mapHoliday,
		forced = config.forced,
		spellsForced = config.spellsForced,
		modes = config.modes,
		usingSpells = nil, -- the last HalloweenSetUsingSpells, nil until one comes
		spellPickupPlaced = false,
	}, Holiday)
end

-- tf_logic_holiday's holiday_type (CTFHolidayEntity sets the game rules').
function Holiday:SetMapHoliday(h)
	self.mapHoliday = h
end

function Holiday:Active(h)
	if self.forced ~= NONE and Contains(FORCED_COUNTS[h], self.forced) then return true end
	if MAP_COUNTS[h] then return Contains(MAP_COUNTS[h], self.mapHoliday) end
	return self.mapHoliday == h
end

-- The first registered mode whose holiday is on.
function Holiday:Mode()
	for _, mode in ipairs(self.modes) do
		if self:Active(mode.HOLIDAY) then return mode end
	end
	return nil
end

-- CTFGameRules::IsUsingSpells, with its map-name check (Helltower, which
-- never sends HalloweenSetUsingSpells) replaced by the map's entities: a map
-- that places a spell pickup uses spells until its first
-- HalloweenSetUsingSpells, and the last input decides from then on (so
-- ctf_helltrain_event's minigame turns them off). tf_spells_enabled forces
-- them on.
function Holiday:UsingSpells()
	if self.spellsForced then return true end
	if self.usingSpells ~= nil then return self.usingSpells end
	return self.spellPickupPlaced
end

-- Sets one of UsingSpells()'s inputs; returns whether UsingSpells() changed.
local function SetSpellsInput(self, field, on)
	local before = self:UsingSpells()
	self[field] = on
	return self:UsingSpells() ~= before
end

-- HalloweenSetUsingSpells: returns whether UsingSpells() changed.
function Holiday:SetUsingSpells(on)
	return SetSpellsInput(self, "usingSpells", on)
end

-- A tf_spell_pickup the map placed (not one thrown by a skeleton king):
-- returns whether UsingSpells() changed.
function Holiday:SpellPickupPlaced()
	return SetSpellsInput(self, "spellPickupPlaced", true)
end

-- CTFGameRules::DropSpellPickup: nothing while spells are off; otherwise a
-- pickup 50 above `position`, thrown at 500 along a random direction that is
-- mostly up. random(lo, hi) draws a float; vector(x, y, z) builds the
-- engine's vectors.
function Holiday:SpellDrop(position, random, vector)
	if not self:UsingSpells() then return nil end
	local spread = SPELL_DROP_SPREAD
	local impulse = vector(random(-spread, spread), random(-spread, spread), 1):GetNormalized()
	return {
		position = position + vector(0, 0, SPELL_DROP_HEIGHT),
		velocity = impulse * SPELL_DROP_SPEED,
	}
end
