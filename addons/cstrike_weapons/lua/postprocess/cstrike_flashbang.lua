local flash_end = 0
local flash_duration = 0

CStrikeFlashbang = CStrikeFlashbang or {}

function CStrikeFlashbang.Apply(duration)
	if duration <= 0 then return end
	flash_duration = math.max(flash_duration, duration)
	flash_end = math.max(flash_end, CurTime() + duration)
end

hook.Add("RenderScreenspaceEffects", "cstrike_flashbang", function()
	local remaining = flash_end - CurTime()
	if remaining <= 0 then
		flash_duration = 0
		return
	end

	local strength = math.Clamp(remaining / flash_duration, 0, 1)
	DrawColorModify({
		["$pp_colour_addr"] = strength * 0.7,
		["$pp_colour_addg"] = strength * 0.7,
		["$pp_colour_addb"] = strength * 0.7,
		["$pp_colour_brightness"] = strength * 0.2,
		["$pp_colour_contrast"] = 1,
		["$pp_colour_colour"] = 1 - strength * 0.8,
		["$pp_colour_mulr"] = 0,
		["$pp_colour_mulg"] = 0,
		["$pp_colour_mulb"] = 0,
	})
end)
