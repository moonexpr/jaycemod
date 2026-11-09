-- tf_logic_on_holiday's Fire (CLogicOnHoliday::InputFire,
-- tf_logic_on_holiday.cpp): the outputs to fire for the holidays that are
-- on, asked of a features.holiday.model model. With none on, IsNothing alone.
local ipairs, require = ipairs, require
local Holiday = require("features.holiday.model")
module(...)

IS_APRIL_FOOLS = "IsAprilFools"
IS_FULL_MOON = "IsFullMoon"
IS_HALLOWEEN = "IsHalloween"
IS_SMISSMAS = "IsSmissmas"
IS_TF_BIRTHDAY = "IsTFBirthday"
IS_VALENTINES = "IsValentines"
IS_NOTHING = "IsNothing"

-- InputFire's order.
local CHECKS = {
	{
		holiday = Holiday.APRIL_FOOLS,
		output = IS_APRIL_FOOLS,
	},
	{
		holiday = Holiday.FULLMOON,
		output = IS_FULL_MOON,
	},
	{
		holiday = Holiday.HALLOWEEN,
		output = IS_HALLOWEEN,
	},
	{
		holiday = Holiday.CHRISTMAS,
		output = IS_SMISSMAS,
	},
	{
		holiday = Holiday.BIRTHDAY,
		output = IS_TF_BIRTHDAY,
	},
	{
		holiday = Holiday.VALENTINES,
		output = IS_VALENTINES,
	},
}

-- holiday: a model with :Active(h).
function Outputs(holiday)
	local outputs = {}
	for _, check in ipairs(CHECKS) do
		if holiday:Active(check.holiday) then outputs[#outputs + 1] = check.output end
	end
	if #outputs == 0 then return { IS_NOTHING } end
	return outputs
end
