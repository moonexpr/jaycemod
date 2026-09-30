-- The payload carts (speed arrows, pushers, rollback countdown, alarm, both
-- carts in payload race), until the payload feature's view draws them. The
-- rest of the round HUD is the rounds feature's view (features/rounds/cl.lua).

local Payload = WETSAND.require("foundation.payload")

surface.CreateFont("Sandcastle.Hud.CartLabel", { font = "Roboto", size = 18, weight = 700 })

-- Carts ---------------------------------------------------------------------------
-- wetsand_cart_<i>_* per enabled team_train_watcher (sv_payload.lua), BLU first.

local HILL_UP = Color(150, 110, 60, 255)
local HILL_DOWN = Color(110, 150, 90, 255)
local ALARM = Color(230, 60, 40)

local function Numbers(text)
	local out = {}
	for i, v in ipairs(string.Explode(",", text)) do out[i] = tonumber(v) end
	return out
end

local function Hills(text)
	local hills = {}
	for _, part in ipairs(string.Explode(";", text)) do
		local from, to, down = string.match(part, "([^:]+):([^:]+):(%d)")
		if from then hills[#hills + 1] = { from = tonumber(from), to = tonumber(to), down = down == "1" } end
	end
	return hills
end

local function Cart(i)
	local key = "wetsand_cart_" .. i .. "_"
	return {
		team = GetGlobal2Int(key .. "team", WETSAND.TEAM_UNASSIGNED),
		progress = GetGlobal2Float(key .. "progress", 0),
		speed = GetGlobal2Int(key .. "speed", 0),
		cappers = GetGlobal2Int(key .. "cappers", 0),
		recedeAt = GetGlobal2Float(key .. "recede_time", 0),
		canRecede = GetGlobal2Bool(key .. "can_recede", true),
		alarm = GetGlobal2Bool(key .. "alarm", false),
		cps = Numbers(GetGlobal2String(key .. "cps", "")),
		owners = Numbers(GetGlobal2String(key .. "owners", "")),
		hills = Hills(GetGlobal2String(key .. "hills", "")),
	}
end

-- Speed arrows (the train's speed level), pushers, block, or the rollback countdown.
local function CartStatus(cart)
	if cart.cappers == Payload.CAPPERS_BLOCKED then return "BLOCKED" end
	local parts = {}
	if cart.speed > 0 then parts[#parts + 1] = string.rep(">", cart.speed) end
	if cart.speed < 0 then parts[#parts + 1] = "<" end
	if cart.cappers > 0 then parts[#parts + 1] = "x" .. cart.cappers end
	if cart.recedeAt > 0 and cart.canRecede then
		parts[#parts + 1] = "Rolls back in " .. math.max(0, math.ceil(cart.recedeAt - CurTime()))
	end
	return table.concat(parts, "  ")
end

local function DrawTrack(cart, x, y, barW, barH)
	surface.SetDrawColor(60, 60, 60, 255)
	surface.DrawRect(x, y, barW, barH)
	for _, hill in ipairs(cart.hills) do
		local c = hill.down and HILL_DOWN or HILL_UP
		surface.SetDrawColor(c.r, c.g, c.b, 255)
		surface.DrawRect(x + barW * hill.from, y + barH - 4, barW * math.max(hill.to - hill.from, 0), 4)
	end
	local tc = WETSAND.TeamColor[cart.team] or WETSAND.TeamColor[WETSAND.TEAM_UNASSIGNED]
	surface.SetDrawColor(tc.r, tc.g, tc.b, 255)
	surface.DrawRect(x, y, barW * cart.progress, barH - 4)
	for i, fraction in ipairs(cart.cps) do
		local c = WETSAND.TeamColor[cart.owners[i] or WETSAND.TEAM_UNASSIGNED] or WETSAND.TeamColor[WETSAND.TEAM_UNASSIGNED]
		draw.RoundedBox(4, x + barW * fraction - 7, y - 4, 14, barH + 8, c)
	end
end

-- The cart marker flashes red while the capture alarm sounds near the goal.
local function DrawMarker(cart, x, y, barW)
	local c = color_white
	if cart.alarm and math.sin(CurTime() * 10) > 0 then c = ALARM end
	draw.RoundedBox(3, x + barW * cart.progress - 5, y - 10, 10, 10, c)
end

local function DrawCartBar(cart, x, y, barW, race, leader)
	local barH = 14
	draw.RoundedBox(4, x - 6, y - 6, barW + 12, barH + 12, Color(0, 0, 0, 170))
	DrawTrack(cart, x, y, barW, barH)
	DrawMarker(cart, x, y, barW)
	if race then
		local label = WETSAND.TeamName[cart.team] or ""
		if leader == cart.team then label = label .. " LEADS" end
		draw.SimpleText(label, "Sandcastle.Hud.CartLabel", x - 14, y + barH / 2, WETSAND.TeamColor[cart.team] or color_white, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
	end
	local status = CartStatus(cart)
	if status ~= "" then
		draw.SimpleText(status, "Sandcastle.Hud.CartLabel", x + barW / 2, y - 30, cart.alarm and ALARM or color_white, TEXT_ALIGN_CENTER)
	end
end

local function DrawCarts(w, h)
	local count = GetGlobal2Int("wetsand_cart_count", 0)
	local race = GetGlobal2Bool("wetsand_cart_race", false)
	local leader = GetGlobal2Int("wetsand_cart_race_leader", 0)
	local barW = math.min(600, w * 0.5)
	local x = (w - barW) / 2
	for i = 1, count do
		DrawCartBar(Cart(i), x, h - 90 - (i - 1) * 52, barW, race, leader)
	end
end

hook.Add("SandcastleHUDPaint", "wetsand_carts", function(w, h)
	DrawCarts(w, h)
end)
