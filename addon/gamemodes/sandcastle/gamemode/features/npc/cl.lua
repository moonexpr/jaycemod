-- The npc feature's view: the boss health bar (TF2's monster resource
-- meter), drawn from the wetsand_boss_health Global2 the npc controller
-- networks (0 hides it), and the particle files the NPCs' effects use.
local BOSS_HEALTH = "wetsand_boss_health"

local PARTICLE_FILES = {
	"particles/halloween.pcf",
	"particles/scary_ghost.pcf",
	"particles/eyeboss.pcf",
	"particles/cinefx.pcf",
	"particles/rockettrail.pcf",
	"particles/explosion.pcf",
}

-- Under the round timer (cl_hud.lua), centred.
local BAR_TOP = 0.17 -- of the screen height
local BAR_WIDTH = 0.3 -- of the screen width
local BAR_HEIGHT = 16
local BAR_PADDING = 4
local BAR_CORNER = 4
local BAR_BACK = Color(0, 0, 0, 170)
local BAR_FILL = Color(118, 196, 52)

for _, pcf in ipairs(PARTICLE_FILES) do game.AddParticles(pcf) end

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

return View
