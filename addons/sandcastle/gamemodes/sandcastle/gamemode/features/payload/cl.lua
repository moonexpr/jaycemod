-- The payload feature's view: TF2's escort HUD (ObjectiveStatusEscort.res,
-- and ObjectiveStatusMultipleEscort.res for a race) in cooler-hud's (v2.6)
-- layout and TF2's materials: the
-- cart's track at the foot of the screen with the home icon at its start,
-- each checkpoint's icon in its owner's colour, the track filled in the
-- pushing team's colour up to the cart, hills marked with the track's
-- arrows, and the cart's icon riding it, with the capture alarm's flash and
-- what Hud.Indicator says on it (blocked, rolling back, its pushers, or the
-- seconds until it rolls back); drawn from what the payload controller
-- networks (ws_cart_*). In a race BLU's cart rides above its track and
-- RED's below its own. It also registers the payload race announcer lines
-- (Announcer.PLR_*), which TF2's soundscripts no longer define, for
-- WS.BroadcastSoundscape to play here; like TF2's other announcer entries they
-- use CHAN_VOICE2 and no attenuation.
WS.Feature("rounds")
WS.Feature("capture")
local Hud = WS.require("features.payload.hud")
local Race = WS.require("features.payload.race")

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

-- Layouts, in TF2's 480-tall units: cooler-hud's .res values -----------------------------

-- EscortItemPanel's controls, in its own units: the cart's icon, the
-- alarm's flash (behind the cart, zpos 0) and what Hud.Indicator says. The
-- panel is ITEM_W wide and CTFHudEscort centres it on the cart's place
-- along the level bar, at the layout's itemY.
local ITEM_W = 52
-- ObjectiveStatusEscort.res.
local SINGLE_ITEM = {
	cart = { x = 13, y = 46, w = 26, h = 26 }, -- EscortItemImage
	alert = { x = 2, y = 42, w = 47, h = 23 }, -- EscortItemImageAlert
	blocked = { x = 23, y = 50, w = 7, h = 7 }, -- Blocked
	backwards = { x = 23, y = 49, w = 7, h = 7 }, -- Speed_Backwards
	capperIcon = { x = 20, y = 48, w = 4, h = 8 }, -- CapPlayerImage
	cappers = { x = 25, y = 49, w = 20, h = 7 }, -- CapNumPlayers, west-aligned
	recede = { x = 21, y = 49, w = 10, h = 7 }, -- RecedeTime, centred
}
-- if_multiple_trains with if_multiple_trains_top: the cart above its track.
-- Both ends move CapPlayerImage off the panel (xpos 9999): a race shows
-- the pushers' count alone.
local RACE_TOP_ITEM = {
	cart = { x = 14, y = 45, w = 23, h = 23 },
	alert = { x = 2, y = 42, w = 47, h = 23 },
	blocked = { x = 22, y = 47, w = 7, h = 7 },
	backwards = { x = 22, y = 48, w = 6, h = 6 },
	cappers = { x = 22, y = 46, w = 30, h = 10 },
	recede = { x = 20, y = 46, w = 11, h = 10 },
}
-- if_multiple_trains with if_multiple_trains_bottom: the cart below its
-- track (EscortItemImageBottom).
local RACE_BOTTOM_ITEM = {
	cart = { x = 14, y = 76, w = 23, h = 23 },
	alert = { x = 2, y = 79, w = 47, h = 23 },
	blocked = { x = 22, y = 84, w = 7, h = 7 },
	backwards = { x = 22, y = 84, w = 6, h = 6 },
	cappers = { x = 22, y = 83, w = 30, h = 10 },
	recede = { x = 20, y = 84, w = 11, h = 10 },
}

-- ObjectiveStatusEscort.res: one cart, the panel at c-200 r160. With hills
-- the track is the opaque one, thicker, and the item panel 4 higher
-- (if_single_with_hills).
local SINGLE = {
	panelW = 400,
	panelBottom = 160,
	-- LevelBar
	trackX = 110,
	trackW = 175,
	trackY = 123,
	trackH = 4,
	hillTrackY = 118,
	hillTrackH = 12,
	-- SimpleControlPointTemplate, centred on each checkpoint's place
	pointSize = 18,
	pointY = 116,
	-- HomeCPIcon, centred on the track's start
	homeX = 101,
	homeY = 116,
	homeSize = 18,
	-- EscortItemPanel
	itemY = 52,
	hillItemY = 48,
	above = SINGLE_ITEM,
}
-- ObjectiveStatusMultipleEscort.res and the escort's if_multiple_trains: a
-- race, each team's track, BLU's cart above it and RED's below. The top
-- team's panel sits at r176 (if_blue_is_top), the other at r160.
local RACE = {
	panelW = 400,
	panelBottom = 176,
	trackX = 110,
	trackW = 175,
	trackY = 114,
	trackH = 12,
	pointSize = 12,
	pointY = 114,
	-- HomeCPIcon, ending at the track's start
	homeX = 96,
	homeY = 113,
	homeSize = 14,
	itemY = 48,
	above = RACE_TOP_ITEM,
	below = RACE_BOTTOM_ITEM,
}
-- The second team's track sits this much below the first's in a race
-- (r176 above r160).
local RACE_TRACK_GAP = 16

local ALARM_FLASH_RATE = 10
local TAN_LIGHT = Color(235, 226, 202)
-- CapNumPlayers' and RecedeTime's ItemFontAttribSmall (cooler-hud's
-- ClientScheme.res: TF2 Secondary, 8), at least MIN_CAPPERS_PIXELS tall.
local CAPPERS_FONT = "Sandcastle.Hud.CartCappers"
local CAPPERS_FACE, CAPPERS_TALL, MIN_CAPPERS_PIXELS = "TF2 Secondary", 8, 8
local cappersFontFor

local function CappersFont(unit)
	if cappersFontFor == unit then return end
	surface.CreateFont(CAPPERS_FONT, {
		font = CAPPERS_FACE,
		size = math.max(MIN_CAPPERS_PIXELS, math.Round(CAPPERS_TALL * unit)),
		weight = 500,
	})
	cappersFontFor = unit
end

local function Image(name, x, y, w, h)
	surface.SetMaterial(Mat(name))
	surface.DrawTexturedRect(x, y, w, h)
end

-- An item panel control's rect R, in pixels, the panel's corner at ix, iy.
local function Place(R, ix, iy, u)
	return ix + R.x * u, iy + R.y * u, R.w * u, R.h * u
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

-- The home icon at the track's start and each checkpoint's in its owner's
-- colour. The home icon is BLU's unless the cart is RED's (if_team_red), a
-- race's the square one (if_multiple_trains_<team>); cooler-hud gives a
-- track with hills no other.
local function DrawPoints(cart, L, ox, oy, u, race, opaque, dy)
	local home = "hud/cart_home_" .. (cart.team == RED and "red" or "blue") .. (race and "_square" or "")
	local homeSize = L.homeSize * u
	Image(home, ox + L.homeX * u, oy + L.homeY * u + dy, homeSize, homeSize)
	local size = L.pointSize * u
	for i, fraction in ipairs(cart.cps) do
		local cx = ox + (L.trackX + L.trackW * fraction) * u
		local name = "hud/cart_point_" .. Suffix(cart.owners[i] or NOBODY) .. ((opaque or race) and "_opaque" or "")
		Image(name, cx - size / 2, oy + L.pointY * u + dy, size, size)
	end
end

-- What Hud.Indicator says, in the item panel I with its corner at ix, iy:
-- blocked, rolling back, the pushers (the capture icon, where the layout
-- has one, and their count), or the rollback countdown.
local function DrawIndicator(cart, I, ix, iy, u)
	local shown = Hud.Indicator(cart, CurTime())
	if shown.blocked then
		Image("hud/cart_blocked", Place(I.blocked, ix, iy, u))
	elseif shown.backwards then
		Image("hud/cart_arrow_left", Place(I.backwards, ix, iy, u))
	elseif shown.cappers then
		if I.capperIcon then Image("vgui/capture_icon_white", Place(I.capperIcon, ix, iy, u)) end
		local x, y, _, h = Place(I.cappers, ix, iy, u)
		draw.SimpleText("x" .. shown.cappers, CAPPERS_FONT, x, y + h / 2, TAN_LIGHT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	elseif shown.recede then
		local x, y, w, h = Place(I.recede, ix, iy, u)
		draw.SimpleText(tostring(shown.recede), CAPPERS_FONT, x + w / 2, y + h / 2, TAN_LIGHT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
end

-- The item panel centred on the cart's place along the track at itemY: the
-- alarm's flash while the capture alarm sounds, behind the cart's icon (BLU's
-- above and RED's below in a race), and the indicator over it.
local function DrawCart(cart, L, ox, oy, u, race, dy, itemY)
	local below = race and cart.team == RED
	local I = below and L.below or L.above
	local ix = ox + (L.trackX + L.trackW * cart.progress - ITEM_W / 2) * u
	local iy = oy + itemY * u + dy
	surface.SetDrawColor(255, 255, 255, 255)
	if cart.alarm and math.sin(CurTime() * ALARM_FLASH_RATE) > 0 then
		Image("hud/cart_alert", Place(I.alert, ix, iy, u))
	end
	Image("hud/cart_" .. Suffix(cart.team) .. (below and "_bottom" or ""), Place(I.cart, ix, iy, u))
	DrawIndicator(cart, I, ix, iy, u)
end

-- offset: how far below its layout this track sits (the second in a race);
-- with hills, a single cart's bar is the thicker opaque one and its item
-- panel sits at hillItemY.
local function DrawEscort(cart, L, ox, oy, u, race, offset)
	local opaque = not race and #cart.hills > 0
	local trackY = (opaque and L.hillTrackY or L.trackY) + offset
	local trackH = opaque and L.hillTrackH or L.trackH
	DrawTrack(cart, L, ox, oy, u, opaque or race, trackY, trackH)
	DrawPoints(cart, L, ox, oy, u, race, opaque, offset * u)
	DrawCart(cart, L, ox, oy, u, race, offset * u, opaque and L.hillItemY or L.itemY)
end

-- The objectives' stack (ws.tf_hud's ObjectiveLifts): the track above
-- frags, under the points and the flag. Its content, in units above the
-- screen's foot: from the checkpoints' foot (a race's: RED's cart under the
-- lower track) to the alarm's top over the cart.
local function Span()
	if GetGlobal2Int("ws_cart_count", 0) == 0 then return nil end
	local top = SINGLE.panelBottom - (math.min(SINGLE.itemY, SINGLE.hillItemY) + SINGLE.above.alert.y)
	if not GetGlobal2Bool("ws_cart_race", false) then
		return { bottom = SINGLE.panelBottom - (SINGLE.pointY + SINGLE.pointSize), top = top }
	end
	local below = RACE.below.alert
	return {
		bottom = RACE.panelBottom - (RACE.itemY + below.y + below.h + RACE_TRACK_GAP),
		top = RACE.panelBottom - (RACE.itemY + RACE.above.alert.y),
	}
end

WS.TFHud.ObjectiveSpan("payload", Span)

local function DrawCarts(w, h)
	local count = GetGlobal2Int("ws_cart_count", 0)
	if count == 0 then return end
	local race = GetGlobal2Bool("ws_cart_race", false)
	local L = race and RACE or SINGLE
	local u = h / 480
	CappersFont(u)
	local lift = WS.TFHud.ObjectiveLift("payload", w, h)
	local ox, oy = w / 2 - L.panelW / 2 * u, h - (L.panelBottom + lift) * u
	for i = 1, count do
		-- the controller orders BLU's cart first (Hud.Order): its track above RED's
		DrawEscort(Cart(i), L, ox, oy, u, race, race and (i - 1) * RACE_TRACK_GAP or 0)
	end
end

local View = { Draw = DrawCarts }

WS.HUD:Add("game.objective.carts", WS.HUD_ORDER.OBJECTIVES, function(...) View.Draw(...) end, WS.Active)

return View
