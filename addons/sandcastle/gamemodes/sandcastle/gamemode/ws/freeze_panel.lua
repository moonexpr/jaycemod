-- TF2's freeze panel as cooler-hud v2.6 lays it out, in TF2's proportional
-- units of a 480-tall screen: resource/ui/freezepanel_basic.res (which
-- defines FreezePanelBase twice; ApplySettings applies both in order, so
-- the second block's values win) and freezepanelkillerhealth.res for the
-- killer's health. CTFFreezePanel fills it on show_freezepanel
-- (tf_hud_freezepanel.cpp): the panel in the killer's team's colour,
-- "You were killed by" (#FreezePanel_Killer; _Dead once the killer is
-- dead), the killer's health, a player's Steam avatar and the killer's
-- name. Rects are { x, y, w, h } in pixels.
local tostring = tostring
local Hud = require("ws.tf_hud")
module(...)

-- FreezePanelBase: r270, 93, 270x200.
BASE_RIGHT, BASE_Y = 270, 93
-- FreezePanelBG 8,160 268x33: a color_panel image, src_corner_width 23,
-- draw_corner_width 5 (TFHud.DrawPanel's).
BG_X, BG_Y, BG_W, BG_H = 8, 160, 268, 33
-- FreezeLabel 40,164 north-west, HudfontSmallest (TF2 Secondary 11).
LABEL_X, LABEL_Y, LABEL_FONT_TALL = 40, 164, 11
-- FreezePanelHealth 9,161 34x31; inside it PlayerStatusHealthValue2
-- -10,4 52x12, centred, HudFontMediumSmallBold2 (TF2 Build 14) in TanLight,
-- over PlayerStatusHealthValueShadow at -11,5 in black; HealthIcon 10,14
-- 12x12 (the stock health images are hidden, wide 0).
HEALTH_X, HEALTH_Y = 9, 161
VALUE_X, VALUE_Y, VALUE_W, VALUE_H, VALUE_FONT_TALL = -10, 4, 52, 12, 14
SHADOW_X, SHADOW_Y = -11, 5
ICON_X, ICON_Y, ICON_SIZE = 10, 14, 12
-- AvatarImage 41,174 14x14. FreezeLabelKiller 173 down, 18 tall, west,
-- HudFontMediumSmallBold (TF2 Build 18): CTFFreezePanel moves it to
-- XRES(2) after a shown avatar, else to the avatar's place.
AVATAR_X, AVATAR_Y, AVATAR_SIZE = 41, 174, 14
NAME_Y, NAME_TALL, NAME_FONT_TALL, NAME_AFTER_AVATAR = 173, 18, 18, 2

-- cooler-hud's own health cross (replay/thumbnails/hud/health_icon), drawn
-- here as it looks: a dark ring, a tan disc 20/256 of it in, and a red
-- cross 34/256 in from each side, 52/256 thick.
RING_COLOR = { r = 40, g = 40, b = 40, a = 255 }
DISC_COLOR = { r = 203, g = 194, b = 179, a = 255 }
CROSS_COLOR = { r = 172, g = 52, b = 48, a = 255 }
local DISC_INSET, CROSS_INSET, CROSS_THICK = 20 / 256, 34 / 256, 52 / 256

-- #FreezePanel_Killer and #FreezePanel_Killer_Dead's English.
local KILLER_LABEL, KILLER_DEAD_LABEL = "You were killed by", "You were killed by the late"

local function Rect(x, y, w, h)
	return { x = x, y = y, w = w, h = h }
end

-- killer = { name, team, health, alive, avatar (a player's Steam avatar to
-- show) }. Returns { image (FreezePanelBG's), label, health (the value, nil
-- for none: dead or at no health), name, avatar }.
function Panel(killer)
	return {
		image = Hud.PanelImage(killer.team),
		label = killer.alive and KILLER_LABEL or KILLER_DEAD_LABEL,
		health = killer.alive and killer.health > 0 and tostring(killer.health) or nil,
		name = killer.name,
		avatar = killer.avatar,
	}
end

-- Where each part goes on a screen screenW wide (unit: Hud.Unit), avatar
-- whether one shows: { bg, label (its top left), value and shadow (the
-- health's centre and its shadow's), icon, avatar, name (its left and
-- middle) }.
function Layout(screenW, unit, avatar)
	local left, top = screenW - BASE_RIGHT * unit, BASE_Y * unit
	local hx, hy = left + HEALTH_X * unit, top + HEALTH_Y * unit
	local avatarRect = Rect(left + AVATAR_X * unit, top + AVATAR_Y * unit, AVATAR_SIZE * unit, AVATAR_SIZE * unit)
	return {
		bg = Rect(left + BG_X * unit, top + BG_Y * unit, BG_W * unit, BG_H * unit),
		label = { x = left + LABEL_X * unit, y = top + LABEL_Y * unit },
		value = { x = hx + (VALUE_X + VALUE_W / 2) * unit, y = hy + (VALUE_Y + VALUE_H / 2) * unit },
		shadow = { x = hx + (SHADOW_X + VALUE_W / 2) * unit, y = hy + (SHADOW_Y + VALUE_H / 2) * unit },
		icon = Rect(hx + ICON_X * unit, hy + ICON_Y * unit, ICON_SIZE * unit, ICON_SIZE * unit),
		avatar = avatarRect,
		name = {
			x = avatar and avatarRect.x + (AVATAR_SIZE + NAME_AFTER_AVATAR) * unit or avatarRect.x,
			y = top + (NAME_Y + NAME_TALL / 2) * unit,
		},
	}
end

-- The health cross's parts in the icon's rect: { ring, disc (both drawn
-- round), across, down (the cross's bars) }.
function HealthIcon(r)
	local cx, cy = r.x + r.w / 2, r.y + r.h / 2
	local thickW, thickH = r.w * CROSS_THICK, r.h * CROSS_THICK
	return {
		ring = Rect(r.x, r.y, r.w, r.h),
		disc = Rect(r.x + r.w * DISC_INSET, r.y + r.h * DISC_INSET, r.w * (1 - 2 * DISC_INSET), r.h * (1 - 2 * DISC_INSET)),
		across = Rect(r.x + r.w * CROSS_INSET, cy - thickH / 2, r.w * (1 - 2 * CROSS_INSET), thickH),
		down = Rect(cx - thickW / 2, r.y + r.h * CROSS_INSET, thickW, r.h * (1 - 2 * CROSS_INSET)),
	}
end
