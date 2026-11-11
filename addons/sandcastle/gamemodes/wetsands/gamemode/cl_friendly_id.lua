-- Friend from foe at a glance, while teams play (includes.friendly_id):
-- teammates wear an outline in their team's colour (cl_friendly_outline), and
-- an enemy under the crosshair shows no name.
local Id = WS.require ("includes.friendly_id")

local OUTLINE_BLUR, OUTLINE_PASSES = 2, 1

local outlines = CreateClientConVar ("cl_friendly_outline", "1", true, false,
	"Outline your teammates in their team's colour", 0, 1)

-- Where the base gamemode draws a target id: under the crosshair.
local TARGET_ID_DROP, LINE_HEIGHT = 30, 20

-- A teammate's building (base_obj): its name, then its health or how far up it is.
local function DrawBuilding (building)
	local lines = Id.BuildingLines (WS.Localize (building.PrintName) or building.PrintName, building:GetObjHealth (), building:GetObjMaxHealth (), building:Constructed ())
	local x, y = ScrW () / 2, ScrH () / 2 + TARGET_ID_DROP
	local color = WS.TeamColor [building:GetObjTeam ()] or color_white
	for i, line in ipairs (lines) do
		draw.SimpleText (line, i == 1 and "TargetID" or "TargetIDSmall", x, y, color, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
		y = y + LINE_HEIGHT
	end
end

-- A true answer keeps the base gamemode's HUDDrawTargetID from drawing.
hook.Add ("HUDDrawTargetID", "ws_friendly_id", function ()
	local me = LocalPlayer ()
	local target = me:GetEyeTrace ().Entity
	if not IsValid (target) then return end
	if target:IsPlayer () then
		if Id.Enemy (WS.TeamPlay (), me:Team (), target:Team ()) then return true end
		return
	end
	if target.GetObjHealth and Id.SeesBuilding (WS.TeamPlay (), me:Team (), target:GetObjTeam (), target:GetBuilder () == me) then
		DrawBuilding (target)
		return true
	end
end)

hook.Add ("PreDrawHalos", "ws_friendly_id", function ()
	if not outlines:GetBool () then return end
	local me, teamPlay, friends = LocalPlayer (), WS.TeamPlay (), {}
	for _, ply in ipairs (player.GetAll ()) do
		if ply ~= me and ply:Alive () and not ply:IsDormant () and Id.Friendly (teamPlay, me:Team (), ply:Team ()) then
			friends [#friends + 1] = ply
		end
	end
	if #friends > 0 then halo.Add (friends, WS.TeamColor [me:Team ()], OUTLINE_BLUR, OUTLINE_BLUR, OUTLINE_PASSES) end
end)
