-- The camera on an NPC being watched, on both realms: the client shows it
-- (ws/cl_spectate.lua's CalcView), and the server puts an observer
-- there to roam when the NPC dies (ws/sv_spectate.lua). The geometry is
-- foundation.spectate's: first person just below the top of its bounds,
-- looking where it faces; third person over its right shoulder, turned by
-- the observer's view and pulled in short of walls.
local Spec = WS.require("foundation.spectate")

local WALL_GAP = 4
local CAMERA_HULL = Vector(4, 4, 4)

local function Point(v) return { x = v.x, y = v.y, z = v.z } end
local function ToVector(p) return Vector(p.x, p.y, p.z) end

-- inEye: first person, else third; angles: the observer's view. Returns the
-- camera's origin and angles.
function WS.NpcCamera(npc, inEye, angles)
	local mins, maxs = npc:WorldSpaceAABB()
	if inEye then return ToVector(Spec.NpcEye(Point(mins), Point(maxs))), npc:EyeAngles() end
	local pivot = Spec.ShoulderPivot(Point(mins), Point(maxs))
	local wanted = Spec.ShoulderOrigin(pivot, Point(angles:Forward()), Point(angles:Right()))
	local tr = util.TraceHull({
		start = ToVector(pivot),
		endpos = ToVector(wanted),
		mins = -CAMERA_HULL,
		maxs = CAMERA_HULL,
		mask = MASK_SOLID_BRUSHONLY,
	})
	return tr.HitPos + tr.HitNormal * WALL_GAP, angles
end
