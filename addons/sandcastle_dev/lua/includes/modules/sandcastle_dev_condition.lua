-- The dev workbench's reading of a condition given or taken by hand (PLAYER:AddCondition,
-- sv_entity.lua):
--   Parse(conds, value) -> the condition's number in conds (the game's COND, name -> number),
--     given its number or its name in any case, with or without TF2's TF_COND_; nil for none
local pairs, type, upper = pairs, type, string.upper
module (...)

local PREFIX = "^TF_COND_"

function Parse (conds, value)
	if type (value) == "number" then
		for _, number in pairs (conds) do
			if number == value then return value end
		end
		return nil
	end
	if type (value) ~= "string" then return nil end
	return conds [(upper (value):gsub (PREFIX, ""))]
end
