AddCSLuaFile ("shared.lua")
AddCSLuaFile ("cl_init.lua")
include ("shared.lua")

-- GMod clears the global once the file has run.
local ENT = ENT

local Model = WS.require ("features.builder.model")

-- From its origin, how far the locker's back and sides reach.
ENT.BACK, ENT.HALF_WIDTH = 16.25, 32.25
-- How far it looks for a wall, and at what height above the floor.
local WALL_RANGE, WALL_PROBE_HEIGHT = 512, 48
local WALL_DIRECTIONS = 16
local WALL_MAX_NORMAL_Z = 0.7
-- prop_dynamic's solid keyvalue: its own vphysics.
local SOLID_VPHYSICS = "6"
-- Where a player stands to be resupplied: before the locker, which faces +x.
local ZONE_MINS, ZONE_MAXS = Vector (-16, -48, 0), Vector (72, 48, 113)

-- Where it stands on the wall hit at wall (its normal given), and its yaw: it
-- faces center when that lies out from the wall, else straight out, and stands
-- off the wall just enough that the corner it turns toward the wall touches
-- it: flush when it faces straight out.
function ENT.Placement (wall, normal, center)
	local outward = math.atan2 (normal.y, normal.x)
	local yaw = outward
	if center then
		local dx, dy = center.x - wall.x, center.y - wall.y
		if dx * normal.x + dy * normal.y > 0 then yaw = math.atan2 (dy, dx) end
	end
	local turn = yaw - outward
	local standOff = ENT.BACK * math.abs (math.cos (turn)) + ENT.HALF_WIDTH * math.abs (math.sin (turn))
	return Vector (wall.x + normal.x * standOff, wall.y + normal.y * standOff, wall.z), math.deg (yaw)
end

-- The center of the room holding pos, or nil.
function ENT.RoomCenterAt (rooms, pos)
	for _, room in ipairs (rooms) do
		local center, mins, maxs = room:GetPos (), room:GetBoxMins (), room:GetBoxMaxs ()
		local x, y = pos.x - center.x, pos.y - center.y
		if x >= mins.x and x <= maxs.x and y >= mins.y and y <= maxs.y then return Vector (center.x, center.y, center.z) end
	end
	return nil
end

local function BrushTrace (from, to)
	return util.TraceLine ({ start = from, endpos = to, mask = MASK_SOLID_BRUSHONLY })
end

-- The nearest wall around pos, at a player's height above the floor below it:
-- its trace, and the floor's height; nil if no wall is in reach.
local function NearestWall (pos)
	local floorZ = BrushTrace (pos, pos - Vector (0, 0, WALL_RANGE)).HitPos.z
	local from = Vector (pos.x, pos.y, floorZ + WALL_PROBE_HEIGHT)
	local nearest, fraction = nil, 1
	for i = 1, WALL_DIRECTIONS do
		local yaw = math.rad (360 * i / WALL_DIRECTIONS)
		local hit = BrushTrace (from, from + Vector (math.cos (yaw), math.sin (yaw), 0) * WALL_RANGE)
		if hit.Hit and hit.Fraction < fraction and math.abs (hit.HitNormal.z) < WALL_MAX_NORMAL_Z then
			nearest, fraction = hit, hit.Fraction
		end
	end
	return nearest, floorZ
end

-- Flush on the nearest wall, turned to its room's center.
function ENT.Prepare (ply, trace)
	local wall, floorZ = NearestWall (trace.HitPos + trace.HitNormal)
	if not wall then
		ply:ChatPrint ("[Gameplay] No wall near there for a resupply closet.")
		return nil, nil, nil, false
	end
	local rooms = ents.FindByClass (Model.CLASSES [Model.ROOM])
	local pos, yaw = ENT.Placement (wall.HitPos, wall.HitNormal, ENT.RoomCenterAt (rooms, trace.HitPos))
	return Vector (pos.x, pos.y, floorZ), Angle (0, yaw, 0)
end

-- The Spawn tool's reload: a closet; on another helper, removes it.
function ENT.Reload (ply, trace, team)
	local builder = WS.Feature ("builder")
	local hit = builder:PieceOf (trace)
	if hit and hit.Kind ~= Model.LOCKER then return builder:RemoveAt (ply, trace) end
	return builder:Place (ply, trace, Model.LOCKER, { TeamNum = Model.PlayingTeam (team) })
end

function ENT:Compile (game)
	local prop = Model.PartName (self:Id (), "prop")
	local pos, ang = self:GetPos (), self:GetAngles ()
	game:Add ({ class = "prop_dynamic", name = prop, pos = pos, ang = ang, model = self.MarkerModel, keys = { solid = SOLID_VPHYSICS } })
	local keys = self:Keys ()
	keys.associatedmodel = prop
	game:Add ({ class = "func_regenerate", name = self:CompiledName (), pos = pos, ang = ang, mins = ZONE_MINS, maxs = ZONE_MAXS, keys = keys })
end
