-- What a living player's +use reaches, traced USE_REACH from its eyes along
-- its aim (a USE_HULL box, so a near miss on an entity still counts):
-- an entity, WSPlayerUseEntity(ply, ent) (the AI war recruits its soldiers,
-- features/aiwar/sv_recruit.lua); nothing at all, aimed into the air with
-- no surface or entity in reach, WSPlayerUseNothing(ply) (a call for a
-- medic, ws/sv_medic_call.lua). A use on the world does neither.
local USE_REACH = 96
local USE_HULL = Vector(4, 4, 4)

hook.Add("KeyPress", "ws_use", function(ply, key)
	if key ~= IN_USE or not ply:Alive() or ply:InVehicle() or ply:GetObserverMode() ~= OBS_MODE_NONE then return end
	local from = ply:EyePos()
	local tr = util.TraceHull({
		start = from,
		endpos = from + ply:GetAimVector() * USE_REACH,
		mins = -USE_HULL,
		maxs = USE_HULL,
		filter = ply,
	})
	if not tr.Hit then
		hook.Run("WSPlayerUseNothing", ply)
	elseif IsValid(tr.Entity) then
		hook.Run("WSPlayerUseEntity", ply, tr.Entity)
	end
end)
