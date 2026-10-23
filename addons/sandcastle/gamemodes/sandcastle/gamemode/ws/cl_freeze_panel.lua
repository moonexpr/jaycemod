-- TF2's freeze panel in cooler-hud v2.6's look (ws.freeze_panel lays it
-- out): while the freeze cam holds on the killer (ws/sv_spectate.lua,
-- OBS_MODE_FREEZECAM, the observer target the killer), a strip at the
-- right in the killer's team's colour with "You were killed by", the
-- killer's health over a health cross, a player's Steam avatar and the
-- killer's name; gone while a win panel is up, as TF2 hides it on
-- teamplay_win_panel. The killer may be a player or an NPC, named as the
-- kill feed and the scoreboard name them, in the team ws_team gives an NPC.
-- Their health is what the server kept on the victim as they killed
-- (ws_killer_health).
local Freeze = WS.require("ws.freeze_panel")
local Hud = WS.require("ws.tf_hud")
local Text = WS.require("features.rounds.text")
local Font, DrawPanel = WS.TFHud.Font, WS.TFHud.DrawPanel
local TAN_LIGHT = WS.TFHud.TAN_LIGHT

local KILLER_HEALTH = "ws_killer_health"
local AVATAR_PIXELS = 32 -- the Steam avatar size AvatarImage loads
local CIRCLE_SEGMENTS = 24

local function Rgba(c) return Color(c.r, c.g, c.b, c.a) end
local RING, DISC, CROSS = Rgba(Freeze.RING_COLOR), Rgba(Freeze.DISC_COLOR), Rgba(Freeze.CROSS_COLOR)

-- The killer, as ws.freeze_panel takes them.
local function Killer(ent, victim)
	local player = ent:IsPlayer()
	return {
		name = player and ent:Nick() or ent.PrintName or language.GetPhrase(ent:GetClass()),
		team = player and ent:Team() or ent:GetNW2Int("ws_team", WS.TEAM_UNASSIGNED),
		health = victim:GetNW2Int(KILLER_HEALTH, 0),
		-- an NPC that dies is removed, and the freeze cam loses it
		alive = not player or ent:Alive(),
		avatar = player and not ent:IsBot(),
	}
end

-- A disc filling the rect, its points clockwise on screen as DrawPoly needs.
local function Circle(r, color)
	local cx, cy, rx, ry = r.x + r.w / 2, r.y + r.h / 2, r.w / 2, r.h / 2
	local points = {}
	for i = 1, CIRCLE_SEGMENTS do
		local a = (i - 1) / CIRCLE_SEGMENTS * 2 * math.pi
		points[i] = { x = cx + math.cos(a) * rx, y = cy + math.sin(a) * ry }
	end
	surface.SetDrawColor(color)
	surface.DrawPoly(points)
end

local function DrawHealthIcon(r)
	local icon = Freeze.HealthIcon(r)
	draw.NoTexture()
	Circle(icon.ring, RING)
	Circle(icon.disc, DISC)
	surface.SetDrawColor(CROSS)
	surface.DrawRect(icon.across.x, icon.across.y, icon.across.w, icon.across.h)
	surface.DrawRect(icon.down.x, icon.down.y, icon.down.w, icon.down.h)
end

-- The killer's Steam avatar: a GMod AvatarImage, painted with the HUD.
local avatar

local function DrawAvatar(ply, r)
	if not IsValid(avatar) then
		avatar = vgui.Create("AvatarImage")
		avatar:SetPaintedManually(true)
		avatar.player = nil
	end
	if avatar.player ~= ply then
		avatar:SetPlayer(ply, AVATAR_PIXELS)
		avatar.player = ply
	end
	avatar:SetPos(r.x, r.y)
	avatar:SetSize(r.w, r.h)
	avatar:PaintManual()
end

local function Draw(w, h)
	local ply = LocalPlayer()
	if ply:GetObserverMode() ~= OBS_MODE_FREEZECAM or not Text.ShowsTeamBar(WS.State()) then return end
	local target = ply:GetObserverTarget()
	if not IsValid(target) or target == ply then return end
	local panel = Freeze.Panel(Killer(target, ply))
	local unit = Hud.Unit(h)
	local layout = Freeze.Layout(w, unit, panel.avatar)
	DrawPanel(panel.image, layout.bg, unit)
	draw.SimpleText(panel.label, Font(Hud.FONT_SECONDARY, Freeze.LABEL_FONT_TALL, unit), layout.label.x, layout.label.y,
		TAN_LIGHT, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
	DrawHealthIcon(layout.icon)
	if panel.health then
		local font = Font(Hud.FONT_BUILD, Freeze.VALUE_FONT_TALL, unit)
		draw.SimpleText(panel.health, font, layout.shadow.x, layout.shadow.y, color_black, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		draw.SimpleText(panel.health, font, layout.value.x, layout.value.y, TAN_LIGHT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	if panel.avatar then DrawAvatar(target, layout.avatar) end
	draw.SimpleText(panel.name, Font(Hud.FONT_BUILD, Freeze.NAME_FONT_TALL, unit), layout.name.x, layout.name.y, TAN_LIGHT,
		TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
end

WS.HUD:Add("player.freeze_panel", WS.HUD_ORDER.NOTICES, Draw, WS.Active)
