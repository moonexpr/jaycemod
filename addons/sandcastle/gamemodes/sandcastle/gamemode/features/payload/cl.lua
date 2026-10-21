-- The payload feature's view: TF2's escort HUD (ObjectiveStatusEscort.res,
-- and ObjectiveStatusMultipleEscort.res for a race), in its materials: the
-- cart's track at the foot of the screen with the home icon at its start,
-- each checkpoint's icon in its owner's colour, the track filled in the
-- pushing team's colour up to the cart, hills marked with the track's
-- arrows, and the cart's icon riding it, with the capture alarm's flash and
-- what Hud.Indicator says on it (blocked, rolling back, its pushers, or the
-- seconds until it rolls back); drawn from what the payload controller
-- networks (ws_cart_*). In a race BLU's cart rides above its track and
-- RED's below its own. It also registers the payload race announcer lines
-- (Announcer.PLR_*), which TF2's soundscripts no longer define, for
-- WS.BroadcastSound to play here; like TF2's other announcer entries they
-- use CHAN_VOICE2 and no attenuation.
WS.Feature("rounds")
WS.Feature("capture")
local Hud = WS.require("foundation.payload.hud")
local Race = WS.require("foundation.payload.race")

local NOBODY = WS.TEAM_UNASSIGNED
local RED, BLUE = WS.TEAM_RED, WS.TEAM_BLUE

for name, wave in pairs(Race.Sounds()) do
	if not sound.GetProperties(name) then
		sound.Add({
			name = name,
			channel = CHAN_VOICE2,
			volume = 1.0,
			level = 0,
			pitch = 100,
			sound = wave,
		})
	end
end

local function Cart(i)
	local key = "ws_cart_" .. i .. "_"
	return {
		team = GetGlobal2Int(key .. "team", NOBODY),
		progress = GetGlobal2Float(key .. "progress", 0),
		speed = GetGlobal2Int(key .. "speed", 0),
		cappers = GetGlobal2Int(key .. "cappers", 0),
		recedeAt = GetGlobal2Float(key .. "recede_time", 0),
		canRecede = GetGlobal2Bool(key .. "can_recede", true),
		alarm = GetGlobal2Bool(key .. "alarm", false),
		cps = Hud.DecodeNumbers(GetGlobal2String(key .. "cps", "")),
		owners = Hud.DecodeNumbers(GetGlobal2String(key .. "owners", "")),
		hills = Hud.DecodeHills(GetGlobal2String(key .. "hills", "")),
	}
end

-- Materials ----------------------------------------------------------------------------

local MATERIALS = {}
local function Mat(name)
	MATERIALS[name] = MATERIALS[name] or Material(name)
	return MATERIALS[name]
end

local TEAM_SUFFIX = { [RED] = "red", [BLUE] = "blue" }
local function Suffix(team) return TEAM_SUFFIX[team] or "neutral" end

-- Layouts, in TF2's 480-tall units ------------------------------------------------------

-- ObjectiveStatusEscort.res: one cart; with hills the track is the opaque
-- one, thicker (if_single_with_hills).
local SINGLE = {
	panelW = 400, panelBottom = 150,
	trackX = 73, trackW = 254, trackY = 123, trackH = 4,
	hillTrackY = 116, hillTrackH = 18,
	pointSize = 28, pointY = 111, homeX = 59,
	cartSize = 40, cartY = 85, cartBelowY = nil,
	alertX = -24, alertY = 46, alertW = 60, alertH = 30,
	-- Blocked's and CapNumPlayers' middle: 10 below EscortItemImage's top
	indicatorY = 95, indicatorSize = 10,
}
-- ObjectiveStatusMultipleEscort.res and the escort's if_multiple_trains: a
-- race, each team's track, BLU's cart above it and RED's below.
local RACE = {
	panelW = 400, panelBottom = 200,
	trackX = 79, trackW = 270, trackY = 114, trackH = 12,
	pointSize = 12, pointY = 114, homeX = 59, homeSize = 14, homeY = 113,
	cartSize = 30, cartY = 91, cartBelowY = 119,
	alertX = -21, alertY = 79, alertW = 60, alertH = 30,
	-- if_multiple_trains: 7 below EscortItemImage's top
	indicatorY = 98, indicatorBelowY = 131, indicatorSize = 8,
}
-- The second team's track sits this much below the first's in a race.
local RACE_TRACK_GAP = 16

local ALARM_FLASH_RATE = 10
local TAN_LIGHT = Color(235, 226, 202)
local CAPPERS_FONT = "Sandcastle.Hud.CartCappers"
local CAPPERS_TALL = 9
local cappersFontFor

local function CappersFont(unit)
	if cappersFontFor == unit then return end
	surface.CreateFont(CAPPERS_FONT, { font = "TF2 Build", size = math.max(8, math.Round(CAPPERS_TALL * unit)), weight = 500 })
	cappersFontFor = unit
end

local function Image(name, x, y, w, h)
	surface.SetMaterial(Mat(name))
	surface.DrawTexturedRect(x, y, w, h)
end

-- Drawing -------------------------------------------------------------------------------

-- The track: the level bar, then the pushing team's fill up to the cart,
-- then each hill's arrows (pointing back up a hill, on down one).
local function DrawTrack(cart, L, ox, oy, u, opaque, trackY, trackH)
	local x, y, w, h = ox + L.trackX * u, oy + trackY * u, L.trackW * u, trackH * u
	surface.SetDrawColor(255, 255, 255, 255)
	Image(opaque and "hud/cart_track_neutral_opaque" or "hud/cart_track", x, y, w, h)
	local fill = cart.progress
	if fill > 0 and TEAM_SUFFIX[cart.team] then
		surface.SetMaterial(Mat("hud/cart_track_" .. Suffix(cart.team) .. (opaque and "_opaque" or "")))
		surface.DrawTexturedRectUV(x, y, w * fill, h, 0, 0, fill, 1)
	end
	for _, hill in ipairs(cart.hills) do
		local hx, hw = x + w * hill.from, w * math.max(hill.to - hill.from, 0)
		local tiles = math.max(hw / h, 1)
		surface.SetMaterial(Mat("hud/cart_track_arrow"))
		if hill.down then
			surface.DrawTexturedRectUV(hx, y, hw, h, 0, 0, tiles, 1)
		else
			surface.DrawTexturedRectUV(hx, y, hw, h, tiles, 0, 0, 1)
		end
	end
end

-- The home icon at the track's start and each checkpoint's in its owner's colour.
local function DrawPoints(cart, L, ox, oy, u, race, opaque, dy)
	-- the home icon is BLU's unless the cart is RED's (the .res's if_team_red)
	local homeTeam = cart.team == RED and "red" or "blue"
	local home
	if race then
		home = "hud/cart_home_" .. homeTeam .. "_square"
	else
		home = "hud/cart_home_" .. homeTeam .. (opaque and "_opaque" or "")
	end
	local homeSize = (L.homeSize or L.pointSize) * u
	Image(home, ox + L.homeX * u, oy + (L.homeY or L.pointY) * u + dy, homeSize, homeSize)
	local size = L.pointSize * u
	for i, fraction in ipairs(cart.cps) do
		local cx = ox + (L.trackX + L.trackW * fraction) * u
		local name = "hud/cart_point_" .. Suffix(cart.owners[i] or NOBODY) .. ((opaque or race) and "_opaque" or "")
		Image(name, cx - size / 2, oy + L.pointY * u + dy, size, size)
	end
end

-- The pushers' icon and count, in indicator sizes from the cart's middle, as
-- CapPlayerImage (7 left, 6 by 12, 1 above the middle) and CapNumPlayers
-- (west-aligned from 1 left) sit in ObjectiveStatusEscort.res.
local CAPPERS_ICON_X, CAPPERS_ICON_Y, CAPPERS_ICON_W, CAPPERS_ICON_H = -0.7, -0.7, 0.6, 1.2
local CAPPERS_TEXT_X = -0.1

-- What Hud.Indicator says, centred at cx, cy: blocked, rolling back, the
-- pushers (the capture icon and their count), or the rollback countdown.
local function DrawIndicator(cart, cx, cy, size, u)
	local shown = Hud.Indicator(cart, CurTime())
	if shown.blocked then
		Image("hud/cart_blocked", cx - size / 2, cy - size / 2, size, size)
	elseif shown.backwards then
		Image("hud/cart_arrow_left", cx - size / 2, cy - size / 2, size, size)
	elseif shown.cappers then
		Image("vgui/capture_icon_white", cx + size * CAPPERS_ICON_X, cy + size * CAPPERS_ICON_Y,
			size * CAPPERS_ICON_W, size * CAPPERS_ICON_H)
		draw.SimpleText("x" .. shown.cappers, CAPPERS_FONT, cx + size * CAPPERS_TEXT_X, cy, TAN_LIGHT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	elseif shown.recede then
		draw.SimpleText(tostring(shown.recede), CAPPERS_FONT, cx, cy, TAN_LIGHT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
end

-- The cart's icon on the track at its progress, BLU's above and RED's below
-- in a race, the alarm's flash over it while the capture alarm sounds.
local function DrawCart(cart, L, ox, oy, u, race, dy)
	local cx = ox + (L.trackX + L.trackW * cart.progress) * u
	local below = race and cart.team == RED
	local size = L.cartSize * u
	local top = oy + (below and L.cartBelowY or L.cartY) * u + dy
	surface.SetDrawColor(255, 255, 255, 255)
	Image("hud/cart_" .. Suffix(cart.team) .. (below and "_bottom" or ""), cx - size / 2, top, size, size)
	if cart.alarm and math.sin(CurTime() * ALARM_FLASH_RATE) > 0 then
		Image("hud/cart_alert", cx + L.alertX * u, oy + L.alertY * u + dy, L.alertW * u, L.alertH * u)
	end
	local cy = oy + (below and L.indicatorBelowY or L.indicatorY) * u + dy
	DrawIndicator(cart, cx, cy, L.indicatorSize * u, u)
end

-- offset: how far below its layout this track sits (the second in a race);
-- with hills, a single cart's bar is the thicker opaque one, its icons where
-- they were.
local function DrawEscort(cart, L, ox, oy, u, race, offset)
	local opaque = not race and #cart.hills > 0
	local trackY = (opaque and L.hillTrackY or L.trackY) + offset
	local trackH = opaque and L.hillTrackH or L.trackH
	DrawTrack(cart, L, ox, oy, u, opaque or race, trackY, trackH)
	DrawPoints(cart, L, ox, oy, u, race, opaque, offset * u)
	DrawCart(cart, L, ox, oy, u, race, offset * u)
end

local function DrawCarts(w, h)
	local count = GetGlobal2Int("ws_cart_count", 0)
	if count == 0 then return end
	local race = GetGlobal2Bool("ws_cart_race", false)
	local L = race and RACE or SINGLE
	local u = h / 480
	CappersFont(u)
	local ox, oy = w / 2 - L.panelW / 2 * u, h - L.panelBottom * u
	for i = 1, count do
		-- the controller orders BLU's cart first (Hud.Order): its track above RED's
		DrawEscort(Cart(i), L, ox, oy, u, race, race and (i - 1) * RACE_TRACK_GAP or 0)
	end
end

local View = { Draw = DrawCarts }

WS.HUD:Add("game.objective.carts", WS.HUD_ORDER.OBJECTIVES, function(...) View.Draw(...) end, WS.Active)

return View
