AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

-- GMod clears the global once the file has run.
local ENT = ENT

local Model = WS.require("features.builder.model")

local ROOM_HEIGHT = 128
local corners = setmetatable({}, { __mode = "k" }) -- player -> the first corner clicked

-- Two corners as a box: its center on the lower corner's floor, its bounds
-- around that, at least height tall and reaching the higher corner.
function ENT.BoxFromCorners(a, b, height)
	local floor, top = math.min(a.z, b.z), math.max(a.z, b.z)
	local halfX, halfY = math.max(a.x, b.x) - (a.x + b.x) / 2, math.max(a.y, b.y) - (a.y + b.y) / 2
	return Vector((a.x + b.x) / 2, (a.y + b.y) / 2, floor),
		Vector(-halfX, -halfY, 0),
		Vector(halfX, halfY, math.max(height, top - floor))
end

-- The first click holds a corner; the second places the room.
function ENT.Prepare(ply, trace)
	local first = corners[ply]
	if not first then
		corners[ply] = trace.HitPos
		ply:ChatPrint("[Gameplay] Corner set: right-click the opposite corner of the spawn room.")
		return nil, nil, nil, true
	end
	corners[ply] = nil
	local center, mins, maxs = ENT.BoxFromCorners(first, trace.HitPos, ROOM_HEIGHT)
	return center, angle_zero, { mins = mins, maxs = maxs }
end

function ENT:Compile(game)
	game:Add({ class = "func_respawnroom", name = self:CompiledName(), pos = self:GetPos(), keys = self:Keys(), mins = self:GetBoxMins(), maxs = self:GetBoxMaxs() })
end
