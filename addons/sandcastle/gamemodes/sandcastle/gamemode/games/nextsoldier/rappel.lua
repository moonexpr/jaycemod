-- Rappelling: a soldier going down a drop deeper than a safe fall (one it
-- would land from faster than games.nextsoldier.noise's MAX_SAFE_FALL_SPEED,
-- HL2's) comes down it no faster than RAPPEL_SPEED, landing softly. Its
-- paths may take drops as deep as games.nextsoldier.path.hl2's
-- SOLDIER_DROP_HEIGHT: mvm_decoy's ledge below BLU's spawn, cp_steel's.
-- Speeds are downward, in units a second; gravity is sv_gravity's.
local Noise = require("games.nextsoldier.noise")
local sqrt = math.sqrt
module(...)

RAPPEL_SPEED = 160

-- The deepest drop fallen without rappelling, under gravity.
local function SafeDrop(gravity)
	return Noise.MAX_SAFE_FALL_SPEED ^ 2 / (2 * gravity)
end

-- Whether a drop this deep is rappelled.
function Rappels(depth, gravity)
	return depth > SafeDrop(gravity)
end

-- How fast to come down now, falling at downSpeed with height to the floor,
-- and whether it rappels: as it falls, unless it would land faster than a
-- safe fall or rappels already; then no faster than RAPPEL_SPEED, to the
-- floor. Returns the speed, rappelling.
function Descent(downSpeed, height, gravity, rappelling)
	local landing = sqrt(downSpeed * downSpeed + 2 * gravity * height)
	if not rappelling and landing <= Noise.MAX_SAFE_FALL_SPEED then return downSpeed, false end
	return downSpeed < RAPPEL_SPEED and downSpeed or RAPPEL_SPEED, true
end
