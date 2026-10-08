-- What players see of a condition the server networks: Jarate
-- (wetsand_urine_end_time, CTFPlayerShared::OnAddUrine and OnRemoveUrine)
-- drips from a jarated player and yellows their own screen.
local URINE_DRIPS = "peejar_drips"
local URINE_OVERLAY = "effects/jarate_overlay" -- TF_SCREEN_OVERLAY_MATERIAL_URINE
local PARTICLE_FILE = "particles/item_fx.pcf"

game.AddParticles(PARTICLE_FILE)

local drips = setmetatable({}, { __mode = "k" }) -- player -> its drips

local function Wet(ply)
	return CurTime() < ply:GetNW2Float("wetsand_urine_end_time", 0)
end

hook.Add("Think", "wetsand_condition_effects", function()
	for _, ply in ipairs(player.GetAll()) do
		local wet, effect = Wet(ply) and ply:Alive(), drips[ply]
		if wet and not (effect and effect:IsValid()) then
			drips[ply] = ply:CreateParticleEffect(URINE_DRIPS, {
				{
					entity = ply,
					attachtype = PATTACH_ABSORIGIN_FOLLOW,
				},
			})
		elseif not wet and effect then
			if effect:IsValid() then effect:StopEmission() end
			drips[ply] = nil
		end
	end
end)

hook.Add("RenderScreenspaceEffects", "wetsand_condition_effects", function()
	local ply = LocalPlayer()
	if not (IsValid(ply) and Wet(ply)) then return end
	DrawMaterialOverlay(URINE_OVERLAY, 0)
end)
