-- ws.freeze_panel: TF2's freeze panel as cooler-hud v2.6 lays it out
-- (freezepanel_basic.res, its second FreezePanelBase block, and
-- freezepanelkillerhealth.res) and CTFFreezePanel fills it
-- (tf_hud_freezepanel.cpp): the killer's team's panel, "You were killed
-- by" (or "by the late" once the killer is dead), the killer's health over
-- a health cross, a player's Steam avatar and the killer's name.
local T = dofile("tests/harness.lua")
local Freeze = T.require("ws.freeze_panel")
local Teams = gameplay.teams

local function Killer(over)
	local killer = {
		name = "alice",
		team = Teams.BLUE,
		health = 125,
		alive = true,
		avatar = true,
	}
	for k, v in pairs(over or {}) do killer[k] = v end
	return killer
end

T.test("a live killer: killed by, their health and name", function()
	local panel = Freeze.Panel(Killer())
	T.eq(panel.label, "You were killed by", "#FreezePanel_Killer")
	T.eq(panel.health, "125", "their health")
	T.eq(panel.name, "alice", "their name")
end)

T.test("a dead killer: killed by the late, no health", function()
	local panel = Freeze.Panel(Killer({ alive = false, health = 0 }))
	T.eq(panel.label, "You were killed by the late", "#FreezePanel_Killer_Dead")
	T.eq(panel.health, nil, "no health")
end)

T.test("no health shows at zero or below, as CTFHudPlayerHealth's empty value", function()
	T.eq(Freeze.Panel(Killer({ health = 0 })).health, nil, "zero")
	T.eq(Freeze.Panel(Killer({ health = -20 })).health, nil, "below")
end)

T.test("the panel is the killer's team's colour, brown for any other team", function()
	T.eq(Freeze.Panel(Killer({ team = Teams.BLUE })).image, "hud/color_panel_blu", "BLU")
	T.eq(Freeze.Panel(Killer({ team = Teams.RED })).image, "hud/color_panel_red", "RED")
	T.eq(Freeze.Panel(Killer({ team = Teams.UNASSIGNED })).image, "hud/color_panel_brown", "no team")
	T.eq(Freeze.Panel(Killer({ team = Teams.HALLOWEEN })).image, "hud/color_panel_brown", "the Halloween team")
end)

T.test("only a killer with an avatar shows one", function()
	T.eq(Freeze.Panel(Killer()).avatar, true, "a player")
	T.eq(Freeze.Panel(Killer({ avatar = false })).avatar, false, "an NPC or a bot")
end)

local SCREEN_W, UNIT = 1920, 2.25

T.test("the panel hangs from the screen's right edge, FreezePanelBase r270, 93", function()
	local layout = Freeze.Layout(SCREEN_W, UNIT, true)
	T.near(layout.bg.x, SCREEN_W - (Freeze.BASE_RIGHT - Freeze.BG_X) * UNIT, 1e-6, "FreezePanelBG's left")
	T.near(layout.bg.y, (Freeze.BASE_Y + Freeze.BG_Y) * UNIT, 1e-6, "its top")
	T.near(layout.bg.w, Freeze.BG_W * UNIT, 1e-6, "its width")
	T.near(layout.label.x, SCREEN_W - (Freeze.BASE_RIGHT - Freeze.LABEL_X) * UNIT, 1e-6, "FreezeLabel's left")
end)

T.test("the name follows the avatar when there is one, else takes its place", function()
	local with, without = Freeze.Layout(SCREEN_W, UNIT, true), Freeze.Layout(SCREEN_W, UNIT, false)
	T.near(with.name.x - with.avatar.x, (Freeze.AVATAR_SIZE + Freeze.NAME_AFTER_AVATAR) * UNIT, 1e-6, "after the avatar")
	T.near(without.name.x, with.avatar.x, 1e-6, "at the avatar's place")
	T.eq(with.name.y, without.name.y, "on one line either way")
end)

T.test("the health value's shadow is a unit left and a unit down", function()
	local layout = Freeze.Layout(SCREEN_W, UNIT, true)
	T.near(layout.shadow.x - layout.value.x, -UNIT, 1e-6, "left")
	T.near(layout.shadow.y - layout.value.y, UNIT, 1e-6, "down")
end)

T.test("the health cross: a disc inside a ring, the cross centred on both", function()
	local icon = Freeze.HealthIcon({ x = 10, y = 20, w = 30, h = 30 })
	T.eq(icon.ring.x, 10, "the ring fills the icon")
	T.eq(icon.ring.w, 30, "edge to edge")
	T.eq(icon.disc.x > icon.ring.x and icon.disc.x + icon.disc.w < icon.ring.x + icon.ring.w, true, "the disc inside")
	T.near(icon.across.x + icon.across.w / 2, 25, 1e-6, "the bar across centred")
	T.near(icon.down.y + icon.down.h / 2, 35, 1e-6, "the bar down centred")
	T.near(icon.across.w, icon.down.h, 1e-6, "arms as long")
	T.near(icon.across.h, icon.down.w, 1e-6, "and as thick")
end)

T.finish()
