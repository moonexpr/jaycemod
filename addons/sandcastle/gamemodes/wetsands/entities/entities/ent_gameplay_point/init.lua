AddCSLuaFile ("shared.lua")
AddCSLuaFile ("cl_init.lua")
include ("shared.lua")

local Model = WS.require ("features.builder.model")

local AREA_MINS, AREA_MAXS = Vector (-80, -80, 0), Vector (80, 80, 128)

function ENT:ShownTeam ()
	return self:GetDefaultOwner ()
end

-- What the game calls it until it is given a name.
function ENT:UndoLabel ()
	return "Point " .. #ents.FindByClass (Model.CLASSES [Model.POINT])
end

-- The Control Point tool's right click.
function ENT.CycleOwner (ply, trace)
	local point = WS.Feature ("builder"):PieceOf (trace, Model.POINT)
	if not point then return false end
	point:Update ({ DefaultOwner = Model.NextOwner (point:GetDefaultOwner ()) })
	return true
end

-- Its keyvalues, called by its place if it has no name.
function ENT:PointKeys (fallbackName)
	local keys = self:Keys ()
	if keys.point_printname == "" then keys.point_printname = fallbackName end
	return keys
end

-- Points with an index first, by it; those without as they were placed.
local function InOrder (a, b)
	local placeA, placeB = a:GetPointIndex (), b:GetPointIndex ()
	placeA, placeB = placeA >= 0 and placeA or math.huge, placeB >= 0 and placeB or math.huge
	if placeA ~= placeB then return placeA < placeB end
	return a:Id () < b:Id ()
end

-- Those on a node are the track's checkpoints (ent_gameplay_node); the rest fall
-- in their order, after the track's, either team able to take them.
function ENT.CompileAll (all, game)
	local points = {}
	for _, point in ipairs (all) do
		if point:GetNodeId () == 0 then points [#points + 1] = point end
	end
	table.sort (points, InOrder)
	for i, point in ipairs (points) do
		local name, pos = point:CompiledName (), point:GetPos ()
		local place = game.pointIndex + 1
		local before = points [i - 1] and points [i - 1]:CompiledName ()
		Model.ControlPoint (game, name, pos, game.pointIndex, point:PointKeys ("Point " .. place), before, { WS.TEAM_RED, WS.TEAM_BLUE })
		game.pointIndex = place
		local area = point:Keys (point.AREA)
		area.area_cap_point = name
		game:Add ({ class = "trigger_capture_area", name = Model.AreaName (point:Id ()), pos = pos, mins = AREA_MINS, maxs = AREA_MAXS, keys = area })
		Model.PointPlate (game, point:Id (), pos)
	end
end

function ENT:WireStatus (point)
	local capture = WS.Feature ("capture")
	local area = WS.Feature ("builder").compiled [Model.AreaName (self:Id ())]
	return
	{
		Owner = capture:Owner (point),
		Capturing = IsValid (area) and capture:AreaCapturing (area) and 1 or 0
	}
end
