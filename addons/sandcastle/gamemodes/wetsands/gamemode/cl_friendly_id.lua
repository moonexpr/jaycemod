-- Friend from foe at a glance, while teams play (includes.friendly_id):
-- teammates wear an outline in their team's colour (cl_friendly_outline), and
-- an enemy under the crosshair shows no name.
local Id = WS.require("includes.friendly_id")

local OUTLINE_BLUR, OUTLINE_PASSES = 2, 1

local outlines = CreateClientConVar("cl_friendly_outline", "1", true, false,
	"Outline your teammates in their team's colour", 0, 1)

-- A true answer keeps the base gamemode's HUDDrawTargetID from drawing.
hook.Add("HUDDrawTargetID", "ws_friendly_id", function()
	local me = LocalPlayer()
	local target = me:GetEyeTrace().Entity
	if IsValid(target) and target:IsPlayer() and Id.Enemy(WS.TeamPlay(), me:Team(), target:Team()) then return true end
end)

hook.Add("PreDrawHalos", "ws_friendly_id", function()
	if not outlines:GetBool() then return end
	local me, teamPlay, friends = LocalPlayer(), WS.TeamPlay(), {}
	for _, ply in ipairs(player.GetAll()) do
		if ply ~= me and ply:Alive() and not ply:IsDormant() and Id.Friendly(teamPlay, me:Team(), ply:Team()) then
			friends[#friends + 1] = ply
		end
	end
	if #friends > 0 then halo.Add(friends, WS.TeamColor[me:Team()], OUTLINE_BLUR, OUTLINE_BLUR, OUTLINE_PASSES) end
end)
