-- The defuse feature's view: CTF's flag panel (features/flag/cl.lua's
-- layout and TF2's materials, at the foot of the screen) made the bomb
-- defusal's. The two-sided background holds the sites, A on BLU's side and B
-- on RED's, each lettered in its state's colour (blue defended, red being
-- planted, yellow planted); its middle, where CTF's "Playing to" tab sits,
-- is a fillable bar, the site's control point inside the flag's capture
-- zone (features.defuse.hud): red as RED plants, full and flashing yellow
-- once planted with the bomb's seconds left, blue as BLU defuses. Above it,
-- the bomb's status as MvM's: its image and a compass pointing to it once it
-- leaves RED's spawn. The flag panel and the control points' icons, which
-- would show the bomb and the sites again, are hidden.
local Hud = WS.require("features.defuse.hud")
local Flag = WS.require("features.flag.model")

local TAN_LIGHT = Color(235, 226, 202)
local SHADOW = Color(0, 0, 0, 196)
local FILLS = {
	[Hud.RED_FILL] = Color(189, 59, 59),
	[Hud.BLUE_FILL] = Color(91, 122, 140),
	[Hud.YELLOW_FILL] = Color(255, 210, 40),
}
-- The flashing yellow's dim phase.
local DIM = 70

-- Layouts, in TF2's 480-tall units, from the screen's centre and foot (the
-- flag panel's: HudObjectiveFlagPanel.res in cooler-hud's layout).
local BG = { x = -112, y = 75, w = 224, h = 64 }
local SITE_TEXT = { [1] = { x = -100, align = TEXT_ALIGN_LEFT }, [2] = { x = 100, align = TEXT_ALIGN_RIGHT } }
local SITE_Y = 57 - 35 / 2
local BAR_BG = { x = -75, y = 41, w = 150, h = 38 }
-- The bar's fill, inside the tab's frame.
local BAR = { x = -66, y = 34, w = 132, h = 22 }
local BOMB_PANEL = { x = -80, y = 111 }
local ARROW = { x = 40, y = 15, w = 80, h = 80 }
local BOMB = { x = 62, y = 36, w = 38, h = 38 }

local FONT, SMALL_FONT = "Sandcastle.Hud.DefuseSite", "Sandcastle.Hud.DefuseSmall"
local fontsFor
local function Fonts(u)
	if fontsFor == u then return end
	surface.CreateFont(FONT, { font = "TF2 Build", size = math.Round(24 * u), weight = 500 })
	surface.CreateFont(SMALL_FONT, { font = "TF2 Secondary", size = math.Round(14 * u), weight = 500 })
	fontsFor = u
end

local MATERIALS = {}
local function Image(name, x, y, w, h)
	MATERIALS[name] = MATERIALS[name] or Material(name)
	surface.SetMaterial(MATERIALS[name])
	surface.DrawTexturedRect(x, y, w, h)
end

local function Rotated(name, cx, cy, w, h, degrees)
	MATERIALS[name] = MATERIALS[name] or Material(name)
	surface.SetMaterial(MATERIALS[name])
	surface.DrawTexturedRectRotated(cx, cy, w, h, degrees)
end

-- What the controller publishes, as features.defuse.hud's Panel reads it.
local function Published()
	local sites = {}
	for i = 1, GetGlobal2Int("ws_defuse_sites", 0) do
		local prefix = "ws_defuse_site_" .. i .. "_"
		sites[i] = {
			name = GetGlobal2String(prefix .. "name", "?"),
			owner = GetGlobal2Int(prefix .. "owner", WS.TEAM_BLUE),
			capping = GetGlobal2Int(prefix .. "capping", 0),
			progress = GetGlobal2Float(prefix .. "progress", 0),
		}
	end
	return {
		state = GetGlobal2String("ws_defuse_state", "carried"),
		sites = sites,
		planted = GetGlobal2Int("ws_defuse_planted", 0),
		explodeAt = GetGlobal2Float("ws_defuse_explode_at", 0),
		now = CurTime(),
	}
end

local function Bomb()
	for _, ent in ipairs(ents.FindByClass("item_teamflag")) do return ent end
	return nil
end

local function Bearing(target)
	local ply = LocalPlayer()
	return (target - ply:GetPos()):Angle().y - ply:EyeAngles().y
end

local function DrawBomb(ent, ox, oy, u)
	local state = ent:GetNW2String("ws_flag_state", Flag.HOME)
	local carrier = ent:GetNW2Entity("ws_flag_carrier")
	local target = IsValid(carrier) and carrier:GetPos() or ent:GetPos()
	surface.SetDrawColor(255, 255, 255, 255)
	local degrees = state == Flag.HOME and 0 or Bearing(target)
	Rotated(Flag.Compass(WS.TEAM_RED, state), ox + (ARROW.x + ARROW.w / 2) * u, oy + (ARROW.y + ARROW.h / 2) * u, ARROW.w * u, ARROW.h * u, degrees)
	Image(Flag.BombImage(state), ox + BOMB.x * u, oy + BOMB.y * u, BOMB.w * u, BOMB.h * u)
end

local function DrawPanel(panel, cx, foot, u)
	surface.SetDrawColor(255, 255, 255, 255)
	local x, y, w, h = cx + BG.x * u, foot - BG.y * u, BG.w * u, BG.h * u
	Image("hud/objectives_flagpanel_bg_left", x, y, w, h)
	Image("hud/objectives_flagpanel_bg_right", x, y, w, h)
	Image("hud/objectives_flagpanel_bg_outline", x, y, w, h)
	for i, site in ipairs(panel.sites) do
		local L = SITE_TEXT[i]
		if L then
			local colour = FILLS[site.tint] or TAN_LIGHT
			draw.SimpleText(site.name, FONT, cx + L.x * u + u, foot - SITE_Y * u + u, SHADOW, L.align, TEXT_ALIGN_CENTER)
			draw.SimpleText(site.name, FONT, cx + L.x * u, foot - SITE_Y * u, colour, L.align, TEXT_ALIGN_CENTER)
		end
	end
	surface.SetDrawColor(255, 255, 255, 255)
	Image("hud/objectives_flagpanel_bg_playingto", cx + BAR_BG.x * u, foot - BAR_BG.y * u, BAR_BG.w * u, BAR_BG.h * u)
	local bx, by, bw, bh = cx + BAR.x * u, foot - BAR.y * u, BAR.w * u, BAR.h * u
	surface.SetDrawColor(0, 0, 0, 160)
	surface.DrawRect(bx, by, bw, bh)
	local fill = FILLS[panel.tint]
	if fill and panel.fill > 0 then
		local dim = panel.tint == Hud.YELLOW_FILL and not panel.lit
		surface.SetDrawColor(fill.r, fill.g, fill.b, dim and DIM or 255)
		surface.DrawRect(bx, by, bw * panel.fill, bh)
	end
	local label = panel.site and ("Site " .. panel.site) or "Bomb sites"
	if panel.seconds then label = label .. "  " .. string.format("%d", math.max(panel.seconds, 0)) end
	draw.SimpleText(label, SMALL_FONT, cx + u, by + bh / 2 + u, SHADOW, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	draw.SimpleText(label, SMALL_FONT, cx, by + bh / 2, TAN_LIGHT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

-- The objectives' stack: the panel's bar at its foot, the bomb's panel on top.
WS.TFHud.ObjectiveSpan("defuse", function()
	if not GetGlobal2Bool("ws_defuse", false) then return nil end
	return { bottom = BAR_BG.y - BAR_BG.h, top = BOMB_PANEL.y }
end)

local function Draw(w, h)
	if not GetGlobal2Bool("ws_defuse", false) then return end
	local u = h / 480
	Fonts(u)
	local cx = w / 2
	local foot = h - WS.TFHud.ObjectiveLift("defuse", w, h) * u
	local panel = Hud.Panel(Published())
	DrawPanel(panel, cx, foot, u)
	local bomb = Bomb()
	if IsValid(bomb) then DrawBomb(bomb, cx + BOMB_PANEL.x * u, foot - BOMB_PANEL.y * u, u) end
end

-- The bomb's flag panel and the sites' point icons say the same again.
WS.HUD:HideElements("game.objective.flags")
WS.HUD:HideElements("game.objective.points")

local View = { Draw = Draw }

WS.HUD:Add("game.objective.defuse", WS.HUD_ORDER.OBJECTIVES, function(...) View.Draw(...) end, WS.Active)

return View
