-- What the model viewer shows of a model and how it plays, as plain values and
-- no panel: a model's path, its sequences by act, its poses, the cycle a
-- sequence has reached, and where the camera sits. An entity is read only through
-- the methods it is asked here. GMod's require("model_viewer_catalog") loads it.
local ipairs = ipairs
local cos, sin, rad, sqrt, min, max = math.cos, math.sin, math.rad, math.sqrt, math.min, math.max
local gmatch, gsub, find, lower, sub = string.gmatch, string.gsub, string.find, string.lower, string.sub
local sort = table.sort
module("model_viewer_catalog")

local NO_ACT = ""

-- A walker's blend at rest shows a body standing still: forward shows its run.
-- Sequences that do not blend on these ignore them.
local AT_START = { move_x = 1 }

local MIN_RADIUS = 8 -- a model with no size still has the camera some way off
local MAX_PITCH = 89
local ZOOM_STEP = 0.9
local ZOOM_NEAREST, ZOOM_FARTHEST = 0.1, 5 -- of the distance that fits the model

local function Clamp(value, low, high) return max(low, min(high, value)) end

-- text -> the model's path as the engine names it, or nil when it names nothing.
function ModelPath(text)
	local path = lower(gsub(gsub(text, "\\", "/"), "[%s\"]", ""))
	if path == "" then return nil end
	if sub(path, 1, 7) ~= "models/" then path = "models/" .. path end
	if sub(path, -4) ~= ".mdl" then path = path .. ".mdl" end
	return path
end

-- ent -> { sequence, name, act, seconds }s: by act, those with no act last, each
-- act's in the model's own order.
function Sequences(ent)
	local entries = {}
	for sequence = 0, ent:GetSequenceCount() - 1 do
		entries[#entries + 1] = {
			sequence = sequence,
			name = ent:GetSequenceName(sequence),
			act = ent:GetSequenceActivityName(sequence),
			seconds = ent:SequenceDuration(sequence),
		}
	end
	sort(entries, function(a, b)
		if a.act == b.act then return a.sequence < b.sequence end
		if a.act == NO_ACT then return false end
		if b.act == NO_ACT then return true end
		return a.act < b.act
	end)
	return entries
end

-- The entries with every word of the text in their act or name, whatever the case.
function Matching(entries, text)
	local words = {}
	for word in gmatch(lower(text), "%S+") do words[#words + 1] = word end
	local kept = {}
	for _, entry in ipairs(entries) do
		local act, name = lower(entry.act), lower(entry.name)
		local keep = true
		for _, word in ipairs(words) do
			if not find(act, word, 1, true) and not find(name, word, 1, true) then keep = false end
		end
		if keep then kept[#kept + 1] = entry end
	end
	return kept
end

-- The place `by` (1 or -1) from `place` in a list of `count`, wrapping; with
-- nothing chosen, the end it starts from; nil when the list is empty.
function Step(count, place, by)
	if count == 0 then return nil end
	if not place then return by > 0 and 1 or count end
	return (place - 1 + by) % count + 1
end

-- The cycle (0..1) a sequence of `duration` seconds reaches `seconds` later.
function Advance(cycle, seconds, duration, rate, loop)
	if duration <= 0 then return cycle end
	local reached = cycle + seconds * rate / duration
	if loop then return reached % 1 end
	return min(reached, 1)
end

-- ent -> { name, min, max, value }s, each pose's value where it starts.
function Poses(ent)
	local poses = {}
	for i = 0, ent:GetNumPoseParameters() - 1 do
		local name = ent:GetPoseParameterName(i)
		local low, high = ent:GetPoseParameterRange(i)
		poses[#poses + 1] = { name = name, min = low, max = high, value = Clamp(AT_START[name] or 0, low, high) }
	end
	return poses
end

-- A model's bounds -> what the camera looks at, and how far off it fits in a
-- view `fov` degrees wide.
function Framing(mins, maxs, fov)
	local x, y, z = (maxs.x - mins.x) / 2, (maxs.y - mins.y) / 2, (maxs.z - mins.z) / 2
	local radius = max(sqrt(x * x + y * y + z * z), MIN_RADIUS)
	local center = { x = mins.x + x, y = mins.y + y, z = mins.z + z }
	return center, radius / sin(rad(fov / 2))
end

-- Where the camera sits: yaw 0 is in front of the model, which faces +x.
function Orbit(center, distance, yaw, pitch)
	local flat = distance * cos(rad(pitch))
	return center.x + flat * cos(rad(yaw)), center.y + flat * sin(rad(yaw)), center.z + distance * sin(rad(pitch))
end

function Pitch(pitch, by) return Clamp(pitch + by, -MAX_PITCH, MAX_PITCH) end

-- The distance after `wheel` notches, up being nearer, within reach of the fit.
function Zoom(distance, fit, wheel)
	return Clamp(distance * ZOOM_STEP ^ wheel, fit * ZOOM_NEAREST, fit * ZOOM_FARTHEST)
end
