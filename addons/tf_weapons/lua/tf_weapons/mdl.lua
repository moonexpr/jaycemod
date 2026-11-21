-- A studio model's skeleton read from the .mdl's bytes (studiohdr_t v48/v49, public/studio.h): the
-- bones' names, parents and rest pose, and the quaternion-interpolation helpers' triggers, which no
-- GMod API gives. In plain Lua over a string, so the tests run it apart from GMod.
local Mdl = {}

Mdl.BONE_SIZE       = 216
Mdl.TRIGGER_SIZE    = 48
Mdl.PROC_QUATINTERP = 2
Mdl.VERSIONS        = { [48] = true, [49] = true }

local BONE_SIZE, TRIGGER_SIZE, PROC_QUATINTERP = Mdl.BONE_SIZE, Mdl.TRIGGER_SIZE, Mdl.PROC_QUATINTERP

-- studiohdr_t and mstudiobone_t offsets
local HEADER_VERSION, HEADER_BONE_COUNT, HEADER_BONE_INDEX = 4, 156, 160
local BONE_PARENT, BONE_POS, BONE_QUAT, BONE_PROCTYPE, BONE_PROCINDEX = 4, 32, 44, 164, 168

local floor, byte = math.floor, string.byte

-- Offsets are from 0, as the format's; Lua's strings count from 1
local function Int32 (data, at)
	local b1, b2, b3, b4 = byte (data, at + 1, at + 4)
	if not b4 then error ("the model ends early", 0) end
	local value = b1 + b2 * 0x100 + b3 * 0x10000 + b4 * 0x1000000
	if value >= 0x80000000 then value = value - 0x100000000 end
	return value
end

-- IEEE 754 single, little-endian
local function Float (data, at)
	local b1, b2, b3, b4 = byte (data, at + 1, at + 4)
	if not b4 then error ("the model ends early", 0) end
	local sign = b4 >= 0x80 and -1 or 1
	local exponent = (b4 % 0x80) * 2 + floor (b3 / 0x80)
	local mantissa = ((b3 % 0x80) * 0x100 + b2) * 0x100 + b1
	if exponent == 0 then
		return sign * mantissa * 2 ^ -149
	elseif exponent == 0xFF then
		return mantissa == 0 and sign * math.huge or 0 / 0
	end
	return sign * (1 + mantissa / 0x800000) * 2 ^ (exponent - 127)
end

local function CString (data, at)
	local stop = string.find (data, "\0", at + 1, true)
	if not stop then error ("a name runs off the model", 0) end
	return string.sub (data, at + 1, stop - 1)
end

Mdl.Int32 = Int32
Mdl.Float = Float

local function Triggers (data, bone)
	local at = bone + Int32 (data, bone + BONE_PROCINDEX)
	local control, count, first = Int32 (data, at), Int32 (data, at + 4), at + Int32 (data, at + 8)
	local triggers = {}
	for t = 1, count do
		local o = first + (t - 1) * TRIGGER_SIZE
		local trigger = {}
		for k = 1, 12 do trigger [k] = Float (data, o + (k - 1) * 4) end
		triggers [t] = trigger
	end
	return { control = control + 1, triggers = triggers }
end

-- The skeleton of a model's bytes (see tf_weapons/rig.lua), or nil and why. A trigger is
-- { inverse tolerance, trigger quaternion (4), local position (3), local quaternion (4) }.
function Mdl.Read (data)
	if type (data) ~= "string" or string.sub (data, 1, 4) ~= "IDST" then return nil, "not a studio model" end
	local ok, result = pcall (function ()
		local version = Int32 (data, HEADER_VERSION)
		if not Mdl.VERSIONS [version] then error ("studio version " .. version .. " is not read", 0) end
		local count, base = Int32 (data, HEADER_BONE_COUNT), Int32 (data, HEADER_BONE_INDEX)
		local s =
		{
			count = count, version = version, name = {}, parent = {}, procedural = {},
			px = {}, py = {}, pz = {}, qx = {}, qy = {}, qz = {}, qw = {}
		}
		for i = 1, count do
			local o = base + (i - 1) * BONE_SIZE
			s.name [i] = CString (data, o + Int32 (data, o))
			s.parent [i] = Int32 (data, o + BONE_PARENT) + 1
			s.px [i], s.py [i] = Float (data, o + BONE_POS), Float (data, o + BONE_POS + 4)
			s.pz [i] = Float (data, o + BONE_POS + 8)
			s.qx [i], s.qy [i] = Float (data, o + BONE_QUAT), Float (data, o + BONE_QUAT + 4)
			s.qz [i], s.qw [i] = Float (data, o + BONE_QUAT + 8), Float (data, o + BONE_QUAT + 12)
			if Int32 (data, o + BONE_PROCTYPE) == PROC_QUATINTERP then
				s.procedural [i] = Triggers (data, o)
			end
		end
		return s
	end)
	if not ok then return nil, result end

	return result
end

return Mdl
