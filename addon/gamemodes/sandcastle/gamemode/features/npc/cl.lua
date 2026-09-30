-- The npc feature's view: the boss health bar (TF2's monster resource
-- meter), drawn from the wetsand_boss_health Global2 the npc controller
-- networks (0 hides it). The particle files are sh.lua's, in both realms.
local BOSS_HEALTH = "wetsand_boss_health"

-- Under the round timer (cl_hud.lua), centred.
local BAR_TOP = 0.17 -- of the screen height
local BAR_WIDTH = 0.3 -- of the screen width
local BAR_HEIGHT = 16
local BAR_PADDING = 4
local BAR_CORNER = 4
local BAR_BACK = Color(0, 0, 0, 170)
local BAR_FILL = Color(118, 196, 52)

local View = {}

function View:DrawBossHealth(w, h)
	local fraction = GetGlobal2Float(BOSS_HEALTH, 0)
	if fraction <= 0 then return end
	local width = math.floor(w * BAR_WIDTH)
	local x, y = math.floor((w - width) / 2), math.floor(h * BAR_TOP)
	draw.RoundedBox(BAR_CORNER, x - BAR_PADDING, y - BAR_PADDING, width + 2 * BAR_PADDING, BAR_HEIGHT + 2 * BAR_PADDING, BAR_BACK)
	surface.SetDrawColor(BAR_FILL)
	surface.DrawRect(x, y, math.floor(width * fraction), BAR_HEIGHT)
end

hook.Add("HUDPaint", "wetsand_boss_health_bar", function()
	View:DrawBossHealth(ScrW(), ScrH())
end)

-- The bosses' game events, as ClientModeTFNormal::FireGameEvent takes
-- them: the cue's sound on the local player (the Horsemann's and
-- MONOCULUS's music and lines), and its line in the chat.
local BossEvents = WETSAND.require("foundation.npc.boss_events")

function View:PlayBossCue(name, fields)
	local cue = BossEvents.Cue(name, fields)
	local ply = LocalPlayer()
	if IsValid(ply) then ply:EmitSound(cue.sound) end
	local color = cue.color and Color(cue.color.r, cue.color.g, cue.color.b) or color_white
	chat.AddText(color, cue.text)
end

for _, name in ipairs(BossEvents.NAMES) do
	WETSAND.Events.Listen(name, "wetsand_npc_view", function(fields)
		View:PlayBossCue(name, fields)
	end)
end

return View
