-- The hostage feature's view: TF2 Classified's VIP HUD
-- (resource/ui/hudobjectivevip.res, its materials in the addon) made the
-- hostages': under the round's timer, its track from home (vip_home) to the
-- getaway car (vip_car), and on it a Civilian's marker (vip_civ_bottom, the
-- Civilian vip_civ above it) for each hostage, as far along as it has come
-- toward the rescue zone and tinted by its state (features.hostage.hud):
-- RED's while held, BLU's while following a rescuer, gold once rescued (at
-- the car), grey where it fell. Under the track, how many are rescued of all.
local Hud = WS.require("features.hostage.hud")

local TINTS = {
	[Hud.HELD] = Color(184, 56, 59),
	[Hud.FOLLOWING] = Color(88, 133, 162),
	[Hud.RESCUED] = Color(255, 200, 40),
	[Hud.KILLED] = Color(110, 110, 110, 160),
}
local TAN_LIGHT = Color(235, 226, 202)
local SHADOW = Color(0, 0, 0, 196)

-- hudobjectivevip.res, in TF2's 480-tall units from the screen's top centre:
-- ObjectiveStatusVIP at c-200, 60, 400 wide; its LevelBar, HomeCPIcon and
-- GoalIcon; the EscortItemPanel's bottom image, 40 square, 14 down.
local PANEL = { x = -200, y = 60 }
local BAR = { x = 73, y = 12, w = 254, h = 4 }
local HOME = { x = 59, y = 0, w = 28, h = 28 }
local GOAL = { x = 313, y = 0, w = 28, h = 28 }
local MARKER = { y = 14, w = 40, h = 40 }
-- The Civilian over his marker, and the tally under the track.
local CIV = { y = -6, w = 28, h = 28 }
local TALLY_Y = 62

local FONT = "Sandcastle.Hud.HostageTally"
local fontFor
local function Font(u)
	if fontFor == u then return end
	surface.CreateFont(FONT, { font = "TF2 Secondary", size = math.Round(14 * u), weight = 500 })
	fontFor = u
end

local MATERIALS = {}
local function Image(name, x, y, w, h)
	MATERIALS[name] = MATERIALS[name] or Material(name)
	surface.SetMaterial(MATERIALS[name])
	surface.DrawTexturedRect(x, y, w, h)
end

local function Published()
	local hostages = {}
	for i = 1, GetGlobal2Int("ws_hostage_count", 0) do
		hostages[i] = {
			state = GetGlobal2String("ws_hostage_" .. i .. "_state", "held"),
			progress = GetGlobal2Float("ws_hostage_" .. i .. "_progress", 0),
		}
	end
	return hostages
end

local function Draw(w, h)
	if not GetGlobal2Bool("ws_hostage", false) then return end
	local hostages = Published()
	if #hostages == 0 then return end
	local u = h / 480
	Font(u)
	local ox, oy = w / 2 + PANEL.x * u, PANEL.y * u
	surface.SetDrawColor(255, 255, 255, 255)
	Image("hud/vip_track", ox + BAR.x * u, oy + BAR.y * u, BAR.w * u, BAR.h * u)
	Image("hud/vip_home", ox + HOME.x * u, oy + HOME.y * u, HOME.w * u, HOME.h * u)
	Image("hud/vip_car", ox + GOAL.x * u, oy + GOAL.y * u, GOAL.w * u, GOAL.h * u)
	for _, marker in ipairs(Hud.Markers(hostages)) do
		local cx = ox + (BAR.x + marker.at * BAR.w) * u
		local tint = TINTS[marker.tint]
		surface.SetDrawColor(tint.r, tint.g, tint.b, tint.a)
		Image("hud/vip_civ_bottom", cx - MARKER.w / 2 * u, oy + MARKER.y * u, MARKER.w * u, MARKER.h * u)
		Image("hud/vip_civ", cx - CIV.w / 2 * u, oy + (MARKER.y + CIV.y) * u, CIV.w * u, CIV.h * u)
	end
	local text = "Rescued " .. Hud.Tally(hostages)
	local tx, ty = w / 2, oy + TALLY_Y * u
	draw.SimpleText(text, FONT, tx + u, ty + u, SHADOW, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	draw.SimpleText(text, FONT, tx, ty, TAN_LIGHT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

local View = { Draw = Draw }

WS.HUD:Add("game.objective.hostages", WS.HUD_ORDER.OBJECTIVES, function(...) View.Draw(...) end, WS.Active)

return View
