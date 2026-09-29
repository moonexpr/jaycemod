-- headless_hatman (CHeadlessHatman): the Horseless Headless Horsemann, a
-- halloween_base_boss bound to foundation.npc.headless_hatman. It
-- implements the Horsemann's port: the control points it guards. The maps
-- spawn it from point_templates and remove it with Kill.
AddCSLuaFile()

ENT.Base = "halloween_base_boss"
ENT.Type = "nextbot"
ENT.Spawnable = false
ENT.Variant = "foundation.npc.headless_hatman"

if CLIENT then return end

-------------------------------------------------------------------------------
-- The Horsemann's port (foundation.npc.headless_hatman.METHODS)

-- The master's points in its order, for CHeadlessHatmanAttack's
-- RecomputeHomePosition. With no master there are none.
function ENT:ControlPoints()
	local master = WETSAND.Master()
	local points = {}
	if not IsValid(master) then return points end
	for i, point in ipairs(WETSAND.ControlPoints()) do
		points[i] = {
			origin = point:GetPos(),
			inRound = master:IsInRound(point),
			owner = WETSAND.CapTeam(point),
			blueMayCapture = WETSAND.TeamCanCapPoint(point, WETSAND.TEAM_BLUE),
		}
	end
	return points
end
