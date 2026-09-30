-- foundation.holiday.on_holiday: tf_logic_on_holiday's Fire
-- (CLogicOnHoliday::InputFire, tf_logic_on_holiday.cpp), the outputs it
-- fires for the holidays the holiday model says are on.
local T = dofile("tests/harness.lua")
local Holiday = T.require("foundation.holiday")
local OnHoliday = T.require("foundation.holiday.on_holiday")

local function Model(forced, mapHoliday)
	return Holiday.New({
		mapHoliday = mapHoliday or Holiday.NONE,
		forced = forced or Holiday.NONE,
		spellsForced = false,
		modes = {},
	})
end

local function Fired(holiday)
	return table.concat(OnHoliday.Outputs(holiday), ",")
end

T.test("no holiday on (cp_fortezza, nothing forced) fires IsNothing alone", function()
	T.eq(Fired(Model()), OnHoliday.IS_NOTHING, "IsNothing")
end)

T.test("each holiday forced fires its own output", function()
	T.eq(Fired(Model(Holiday.HALLOWEEN)), OnHoliday.IS_HALLOWEEN, "Halloween")
	T.eq(Fired(Model(Holiday.CHRISTMAS)), OnHoliday.IS_SMISSMAS, "Smissmas")
	T.eq(Fired(Model(Holiday.BIRTHDAY)), OnHoliday.IS_TF_BIRTHDAY, "birthday")
	T.eq(Fired(Model(Holiday.VALENTINES)), OnHoliday.IS_VALENTINES, "Valentines")
	T.eq(Fired(Model(Holiday.FULLMOON)), OnHoliday.IS_FULL_MOON, "full moon")
	T.eq(Fired(Model(Holiday.APRIL_FOOLS)), OnHoliday.IS_APRIL_FOOLS, "April Fools")
end)

T.test("several holidays on fire in InputFire's order, and never IsNothing", function()
	local expected = table.concat({ OnHoliday.IS_FULL_MOON, OnHoliday.IS_HALLOWEEN, OnHoliday.IS_VALENTINES }, ",")
	T.eq(Fired(Model(Holiday.HALLOWEEN_OR_FULLMOON_OR_VALENTINES)), expected, "the combined forced value")
end)

T.test("a map's tf_logic_holiday counts as the holiday", function()
	T.eq(Fired(Model(Holiday.NONE, Holiday.HALLOWEEN)), OnHoliday.IS_HALLOWEEN, "a Halloween map")
end)

T.test("the output names are the entity's", function()
	T.eq(OnHoliday.IS_NOTHING, "IsNothing", "IsNothing")
	T.eq(OnHoliday.IS_APRIL_FOOLS, "IsAprilFools", "IsAprilFools")
	T.eq(OnHoliday.IS_FULL_MOON, "IsFullMoon", "IsFullMoon")
	T.eq(OnHoliday.IS_HALLOWEEN, "IsHalloween", "IsHalloween")
	T.eq(OnHoliday.IS_SMISSMAS, "IsSmissmas", "IsSmissmas")
	T.eq(OnHoliday.IS_TF_BIRTHDAY, "IsTFBirthday", "IsTFBirthday")
	T.eq(OnHoliday.IS_VALENTINES, "IsValentines", "IsValentines")
end)

T.finish()
