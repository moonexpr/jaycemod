-- The map as a walker meets it, what GMod's nav mesh does not tell: its parts
-- doors, portal and nav_gaps; here, which clips it stands on and where a
-- solid brush stands in the mesh.
local abs, ipairs = math.abs, ipairs
module ("nextsoldier.world")

-- Which clip brushes the AI war's soldiers stand on. Maps made for players
-- (TF2's, CS:S's) close gaps and drops with player clips (CONTENTS_PLAYERCLIP)
-- that NPC movement (MASK_NPCSOLID) passes through: arena_well's gap round
-- its point, pl_goldrush's second stage. The soldiers stand in for players
-- there, so they take the player's clips (CLIP_PLAYER: MASK_PLAYERSOLID); on
-- any other map, made for NPCs, the NPC's (CLIP_NPC: MASK_NPCSOLID). A map is
-- a players' map by its entities.
CLIP_PLAYER, CLIP_NPC = "player", "npc"

local PLAYER_MAP_CLASSES =
{
	tf_gamerules = true,
	info_player_teamspawn = true, -- TF2's team spawns
	info_player_terrorist = true, -- CS:S's
	info_player_counterterrorist = true
}

-- The clips for a map with entities of these classes (a list of names).
function ClipFor (classes)
	for _, class in ipairs (classes) do
		if PLAYER_MAP_CLASSES [class] then return CLIP_PLAYER end
	end
	return CLIP_NPC
end

local STEP_HEIGHT = 18 -- StepHeight
local CROUCH_HEIGHT = 30 -- the sweep's top, as in TF2
local LEVEL_TOLERANCE = 1 -- corners this close in height are level

-- Which nav areas a solid func_brush stands in: TF2's
-- TestAndBlockOverlappingAreas (tf_nav_mesh.cpp), which GMod's nav mesh
-- lacks, so routes led into brushes that are solid in places the mesh was
-- generated through (a wall toggled on by map logic, a barrier). For each area
-- overlapping the brush, a thin hull is swept across the area from StepHeight
-- to crouch height, along the area's slope; if it hits the brush, the area is
-- blocked to everyone.
--
-- Corners are { x, y, z }; nw is the area's lowest x and y (its extent's lo),
-- ne has the highest x, sw the highest y, se both. Returns the sweep: from, to
-- (corner points) and the hull's mins, maxs (offsets from the swept point).
function BrushSweep (nw, ne, se, sw, sizeX, sizeY)
	local from, to, maxs
	if abs (nw.z - ne.z) < LEVEL_TOLERANCE then
		-- level along x, perhaps sloping along y: a hull as wide as the area, swept south
		from, to, maxs = nw, sw, { x = sizeX, y = 0, z = CROUCH_HEIGHT }
	elseif abs (nw.z - sw.z) < LEVEL_TOLERANCE then
		-- level along y, perhaps sloping along x: swept east
		from, to, maxs = nw, ne, { x = 0, y = sizeY, z = CROUCH_HEIGHT }
	else
		-- sloping both ways: a thin hull along the diagonal
		from, to, maxs = nw, se, { x = 1, y = 1, z = CROUCH_HEIGHT }
	end
	-- from high to low, so the hull does not start inside the floor
	if from.z < to.z then from, to = to, from end
	return from, to, { x = 0, y = 0, z = STEP_HEIGHT }, maxs
end
