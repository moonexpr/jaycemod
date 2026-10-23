-- The flag feature's view: TF2's flag panel (HudObjectiveFlagPanel.res and
-- FlagStatus.res) in cooler-hud's (v2.6) layout and TF2's materials, at the
-- foot of the screen. In CTF: the
-- two-sided background with each team's captures (BLU's left, RED's right)
-- and the "Playing to" tab under them; a status panel per flag, BLU's left
-- and RED's right, each a compass in the flag's colour pointing to the flag
-- once it leaves home, the briefcase, and the home, dropped or moving icon.
-- In MvM only the bomb's panel shows, the bomb's image for the briefcase.
-- A player carrying a flag sees the carried image and an arrow pointing to
-- the zone that takes it instead. Drawn from what the flag controller
-- networks (NW2 ws_flag_* on each item_teamflag, ws_flag_* and ws_mvm).
WS.Feature("rounds")
local Flag = WS.require("features.flag.model")

local RED, BLUE = WS.TEAM_RED, WS.TEAM_BLUE
local TAN_LIGHT = Color(235, 226, 202)
local SHADOW = Color(0, 0, 0, 196)

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

-- Layouts, in TF2's 480-tall units: x from the screen's centre, y from its
-- foot (the .res's c and r); cooler-hud's HudObjectiveFlagPanel.res -------------------

-- LeftSideBG, RightSideBG and OutlineBG.
local BG = { x = -112, y = 75, w = 224, h = 64 }
-- BlueScore (west-aligned) and RedScore (east-aligned), each over its
-- shadow (BlueScoreShadow, RedScoreShadow) a unit lower and a unit outward.
local SCORE = {
	[BLUE] = {
		x = -97,
		y = 57,
		w = 75,
		h = 35,
		align = TEXT_ALIGN_LEFT,
		shadowX = -1,
	},
	[RED] = {
		x = 25,
		y = 57,
		w = 75,
		h = 35,
		align = TEXT_ALIGN_RIGHT,
		shadowX = 1,
	},
}
local SCORE_SHADOW_Y = 1
local PLAYING_TO_BG = { x = -75, y = 41, w = 150, h = 38 }
local PLAYING_TO = { x = -70, y = 38, w = 140, h = 30 }
-- BlueFlag and RedFlag (CTFFlagStatus), and MvM's bomb in BlueFlag's place (if_mvm).
local PANELS = {
	[Flag.SLOT_BLUE] = { x = -122, y = 106 },
	[Flag.SLOT_RED] = { x = -37, y = 106 },
}
local MVM_PANELS = {
	[Flag.SLOT_BLUE] = { x = -80, y = 111 },
}
-- cooler-hud's FlagStatus.res, from its panel's corner; MvM's arrow and
-- bomb are its if_mvm sizes.
local ARROW = { x = 48, y = 12, w = 64, h = 64 }
local MVM_ARROW = { x = 40, y = 15, w = 80, h = 80 }
local BRIEFCASE = { x = 65, y = 30, w = 30, h = 30 }
local BOMB = { x = 62, y = 36, w = 38, h = 38 }
local STATUS = { x = 75, y = 28, w = 30, h = 30 }
-- What a carrier sees: OutlineImage, CarriedImage and CaptureFlag.
local CARRIED_OUTLINE = { x = -52, y = 127, w = 100, h = 50 }
local CARRIED = { x = -24, y = 115, w = 45, h = 45 }
local CAPTURE_ARROW = { x = -32, y = 95, w = 64, h = 64 }

-- cooler-hud's ClientScheme.res: HudFontMedium (TF2 Build, 24) and
-- HudFontSmall (TF2 Secondary, 14).
local SCORE_FONT, SMALL_FONT = "Sandcastle.Hud.FlagScore", "Sandcastle.Hud.FlagSmall"
local SCORE_TALL, SMALL_TALL = 24, 14
local fontsFor

local function Fonts(u)
	if fontsFor == u then return end
	surface.CreateFont(SCORE_FONT, { font = "TF2 Build", size = math.Round(SCORE_TALL * u), weight = 500 })
	surface.CreateFont(SMALL_FONT, { font = "TF2 Secondary", size = math.Round(SMALL_TALL * u), weight = 500 })
	fontsFor = u
end

-- The flags ---------------------------------------------------------------------------

local function Shown()
	local shown = {}
	for _, ent in ipairs(ents.FindByClass("item_teamflag")) do
		shown[#shown + 1] = {
			ent = ent,
			team = ent:GetNW2Int("ws_flag_team", WS.TEAM_UNASSIGNED),
			state = ent:GetNW2String("ws_flag_state", Flag.HOME),
			enabled = ent:GetNW2Bool("ws_flag_enabled", true),
			carrier = ent:GetNW2Entity("ws_flag_carrier"),
			carrierTeam = ent:GetNW2Int("ws_flag_carrier_team", WS.TEAM_UNASSIGNED),
		}
	end
	return shown
end

-- CTFArrowPanel::GetAngleRotation: the turn from where the player looks to
-- the target, so straight ahead points up.
local function Bearing(target)
	local ply = LocalPlayer()
	local to = target - ply:GetPos()
	return to:Angle().y - ply:EyeAngles().y
end

-- Drawing -------------------------------------------------------------------------------

local function Box(L, ox, oy, u)
	return ox + L.x * u, oy + L.y * u, L.w * u, L.h * u
end

local function DrawScores(cx, h, u)
	surface.SetDrawColor(255, 255, 255, 255)
	local x, y, w, bh = cx + BG.x * u, h - BG.y * u, BG.w * u, BG.h * u
	Image("hud/objectives_flagpanel_bg_left", x, y, w, bh)
	Image("hud/objectives_flagpanel_bg_right", x, y, w, bh)
	Image("hud/objectives_flagpanel_bg_outline", x, y, w, bh)
	for team, L in pairs(SCORE) do
		local text = tostring(GetGlobal2Int("ws_flag_caps_" .. team, 0))
		local edge = L.align == TEXT_ALIGN_LEFT and L.x or L.x + L.w -- the side it is aligned to
		local tx, ty = cx + edge * u, h - (L.y - L.h / 2) * u
		draw.SimpleText(text, SCORE_FONT, tx + L.shadowX * u, ty + SCORE_SHADOW_Y * u, SHADOW, L.align, TEXT_ALIGN_CENTER)
		draw.SimpleText(text, SCORE_FONT, tx, ty, TAN_LIGHT, L.align, TEXT_ALIGN_CENTER)
	end
	surface.SetDrawColor(255, 255, 255, 255)
	Image("hud/objectives_flagpanel_bg_playingto", cx + PLAYING_TO_BG.x * u, h - PLAYING_TO_BG.y * u, PLAYING_TO_BG.w * u, PLAYING_TO_BG.h * u)
	local limit = GetGlobal2Int("ws_flag_caplimit", Flag.CAPLIMIT_DEFAULT)
	draw.SimpleText("Playing to: " .. limit, SMALL_FONT, cx, h - (PLAYING_TO.y - PLAYING_TO.h / 2) * u, TAN_LIGHT,
		TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

-- One CTFFlagStatus: the compass, the briefcase (or bomb) and the status icon.
local function DrawStatus(f, ox, oy, u, mvm)
	surface.SetDrawColor(255, 255, 255, 255)
	local x, y, w, h = Box(mvm and MVM_ARROW or ARROW, ox, oy, u)
	local target = IsValid(f.carrier) and f.carrier:GetPos() or f.ent:GetPos()
	local degrees = f.state == Flag.HOME and 0 or Bearing(target)
	Rotated(Flag.Compass(f.team, f.state), x + w / 2, y + h / 2, w, h, degrees)
	if mvm then
		Image(Flag.BombImage(f.state), Box(BOMB, ox, oy, u))
		return
	end
	Image("hud/objectives_flagpanel_briefcase", Box(BRIEFCASE, ox, oy, u))
	Image(Flag.StatusIcon(f.state), Box(STATUS, ox, oy, u))
end

-- The carrier's view: the carried image and the arrow to its team's zone.
local function DrawCarried(f, cx, h, u)
	surface.SetDrawColor(255, 255, 255, 255)
	Image("hud/objectives_flagpanel_carried_outline", cx + CARRIED_OUTLINE.x * u, h - CARRIED_OUTLINE.y * u, CARRIED_OUTLINE.w * u, CARRIED_OUTLINE.h * u)
	Image(Flag.CarriedImage(f.team, f.carrierTeam), cx + CARRIED.x * u, h - CARRIED.y * u, CARRIED.w * u, CARRIED.h * u)
	local zone = GetGlobal2Vector("ws_flag_zone_" .. f.carrierTeam, vector_origin)
	if zone == vector_origin then return end
	local w, ah = CAPTURE_ARROW.w * u, CAPTURE_ARROW.h * u
	local x, y = cx + CAPTURE_ARROW.x * u, h - CAPTURE_ARROW.y * u
	Rotated(Flag.Compass(f.carrierTeam, Flag.CARRIED), x + w / 2, y + ah / 2, w, ah, Bearing(zone))
end

local function Draw(w, h)
	local shown = Shown()
	if #shown == 0 then return end
	local u = h / 480
	Fonts(u)
	local cx = w / 2
	local mvm = GetGlobal2Bool("ws_mvm", false)
	if not mvm and GetGlobal2Bool("ws_flag_scores", false) then DrawScores(cx, h, u) end
	local me = LocalPlayer()
	for _, f in ipairs(shown) do
		if f.state == Flag.CARRIED and f.carrier == me then
			DrawCarried(f, cx, h, u)
			return
		end
	end
	for slot, f in pairs(Flag.Slots(shown, mvm)) do
		local P = (mvm and MVM_PANELS or PANELS)[slot]
		DrawStatus(f, cx + P.x * u, h - P.y * u, u, mvm)
	end
end

local View = { Draw = Draw }

WS.HUD:Add("game.objective.flags", WS.HUD_ORDER.OBJECTIVES, function(...) View.Draw(...) end, WS.Active)

return View
