-- A map's bomb defusal settings, from its cs_defuse_logic's keyvalues (lower
-- case keys), CS:S's defaults when left out: roundtime, the round's length
-- (mp_roundtime's 2:15); c4timer, the planted bomb's timer (mp_c4timer);
-- planttime, how long a site's capture takes to plant (a quick one);
-- armtime, how long arming the bomb then holds the planters (a stun on every
-- RED on the site: CS:S's plant time); defusetime, how long BLU's capture
-- takes (CS:S's kitless defuse); bombradius, the blast's reach,
-- the map's info_map_parameters bombradius when the logic gives none. Seconds
-- and units, each a positive number, else refused naming its key.
local error, tonumber, tostring = error, tonumber, tostring
module(...)

ROUND_TIME = 135
C4_TIMER = 45
PLANT_TIME = 1
ARM_TIME = 3
DEFUSE_TIME = 10
BOMB_RADIUS = 500

local function Positive(keyvalues, key, default)
	local text = keyvalues[key]
	if text == nil or text == "" then return default end
	local value = tonumber(text)
	if not value or value <= 0 then
		error("cs_defuse_logic: " .. key .. " " .. tostring(text) .. " is not a positive number", 3)
	end
	return value
end

-- keyvalues: key -> text; mapRadius: info_map_parameters' bombradius text, or nil.
function Parse(keyvalues, mapRadius)
	return {
		roundTime = Positive(keyvalues, "roundtime", ROUND_TIME),
		c4Timer = Positive(keyvalues, "c4timer", C4_TIMER),
		plantTime = Positive(keyvalues, "planttime", PLANT_TIME),
		armTime = Positive(keyvalues, "armtime", ARM_TIME),
		defuseTime = Positive(keyvalues, "defusetime", DEFUSE_TIME),
		bombRadius = Positive(keyvalues, "bombradius", Positive({ bombradius = mapRadius }, "bombradius", BOMB_RADIUS)),
	}
end
