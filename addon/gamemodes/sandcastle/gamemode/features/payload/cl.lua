-- The payload feature's view: each cart's bar along the bottom of the
-- screen (its track with hills and checkpoints in their owners' colours,
-- the cart marker, flashing while the capture alarm sounds, and the status
-- line of speed arrows, pushers, BLOCKED or the rollback countdown), both
-- carts with the leader named in a payload race; drawn from what the
-- payload controller networks (wetsand_cart_*). It also registers the
-- payload race announcer lines (Announcer.PLR_*), which TF2's soundscripts
-- no longer define, for WETSAND.BroadcastSound to play here; like TF2's
-- other announcer entries they use CHAN_VOICE2 and no attenuation.
WETSAND.Feature("rounds")
WETSAND.Feature("capture")
local Hud = WETSAND.require("foundation.payload.hud")
local Race = WETSAND.require("foundation.payload.race")

local NOBODY = WETSAND.TEAM_UNASSIGNED
local FONT_LABEL = "Sandcastle.Hud.CartLabel"

local BAR_MAX_WIDTH = 600
local BAR_SCREEN_FRACTION = 0.5
local BAR_HEIGHT = 14
local BAR_PADDING = 6
local BAR_ABOVE_BOTTOM = 90
local BAR_SPACING = 52 -- between the carts' bars in a race
local HILL_HEIGHT = 4
local CHECKPOINT_WIDTH = 14
local CHECKPOINT_OVERHANG = 4
local MARKER_SIZE = 10
local LABEL_GAP = 14
local STATUS_ABOVE = 30
local ALARM_FLASH_RATE = 10

local TRACK = Color(60, 60, 60, 255)
local BACKDROP = Color(0, 0, 0, 170)
local HILL_UP = Color(150, 110, 60, 255)
local HILL_DOWN = Color(110, 150, 90, 255)
local ALARM = Color(230, 60, 40)

surface.CreateFont(FONT_LABEL, {
	font = "Roboto",
	size = 18,
	weight = 700,
})

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
	local key = "wetsand_cart_" .. i .. "_"
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

local function TeamColor(t)
	return WETSAND.TeamColor[t] or WETSAND.TeamColor[NOBODY]
end

local function DrawTrack(cart, x, y, barW)
	surface.SetDrawColor(TRACK.r, TRACK.g, TRACK.b, TRACK.a)
	surface.DrawRect(x, y, barW, BAR_HEIGHT)
	for _, hill in ipairs(cart.hills) do
		local c = hill.down and HILL_DOWN or HILL_UP
		surface.SetDrawColor(c.r, c.g, c.b, c.a)
		surface.DrawRect(x + barW * hill.from, y + BAR_HEIGHT - HILL_HEIGHT, barW * math.max(hill.to - hill.from, 0), HILL_HEIGHT)
	end
	local tc = TeamColor(cart.team)
	surface.SetDrawColor(tc.r, tc.g, tc.b, 255)
	surface.DrawRect(x, y, barW * cart.progress, BAR_HEIGHT - HILL_HEIGHT)
	for i, fraction in ipairs(cart.cps) do
		draw.RoundedBox(4, x + barW * fraction - CHECKPOINT_WIDTH / 2, y - CHECKPOINT_OVERHANG,
			CHECKPOINT_WIDTH, BAR_HEIGHT + 2 * CHECKPOINT_OVERHANG, TeamColor(cart.owners[i] or NOBODY))
	end
end

-- The cart marker flashes red while the capture alarm sounds near the goal.
local function DrawMarker(cart, x, y, barW)
	local c = color_white
	if cart.alarm and math.sin(CurTime() * ALARM_FLASH_RATE) > 0 then c = ALARM end
	draw.RoundedBox(3, x + barW * cart.progress - MARKER_SIZE / 2, y - MARKER_SIZE, MARKER_SIZE, MARKER_SIZE, c)
end

local function DrawCartBar(cart, x, y, barW, race, leader)
	draw.RoundedBox(4, x - BAR_PADDING, y - BAR_PADDING, barW + 2 * BAR_PADDING, BAR_HEIGHT + 2 * BAR_PADDING, BACKDROP)
	DrawTrack(cart, x, y, barW)
	DrawMarker(cart, x, y, barW)
	if race then
		local label = WETSAND.TeamName[cart.team] or ""
		if leader == cart.team then label = label .. " LEADS" end
		draw.SimpleText(label, FONT_LABEL, x - LABEL_GAP, y + BAR_HEIGHT / 2, WETSAND.TeamColor[cart.team] or color_white, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
	end
	local status = Hud.Status(cart, CurTime())
	if status ~= "" then
		draw.SimpleText(status, FONT_LABEL, x + barW / 2, y - STATUS_ABOVE, cart.alarm and ALARM or color_white, TEXT_ALIGN_CENTER)
	end
end

local function DrawCarts(w, h)
	local count = GetGlobal2Int("wetsand_cart_count", 0)
	local race = GetGlobal2Bool("wetsand_cart_race", false)
	local leader = GetGlobal2Int("wetsand_cart_race_leader", NOBODY)
	local barW = math.min(BAR_MAX_WIDTH, w * BAR_SCREEN_FRACTION)
	local x = (w - barW) / 2
	for i = 1, count do
		DrawCartBar(Cart(i), x, h - BAR_ABOVE_BOTTOM - (i - 1) * BAR_SPACING, barW, race, leader)
	end
end

local View = { Draw = DrawCarts }

hook.Add("SandcastleHUDPaint", "wetsand_carts", function(...) View.Draw(...) end)

return View
