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
-- RecomputeHomePosition. With no master there are none, and the capture
-- feature is not loaded for the asking.
function ENT:ControlPoints()
	local points = {}
	if not IsValid(ents.FindByClass("team_control_point_master")[1]) then return points end
	local capture = WETSAND.Feature("capture")
	for i, point in ipairs(capture:Points()) do
		points[i] = {
			origin = point:GetPos(),
			inRound = capture:IsInRound(point),
			owner = capture:Owner(point),
			blueMayCapture = capture:TeamMayCapture(point, WETSAND.TEAM_BLUE),
		}
	end
	return points
end
