-- Round HUD: timer, every payload cart (speed arrows, pushers, rollback
-- countdown, alarm, both carts in payload race), timed captures,
-- announcements, respawn countdown.

local Payload = WETSAND.require("foundation.payload")

surface.CreateFont("TF2Ents.Timer", { font = "Roboto", size = 34, weight = 800 })
surface.CreateFont("TF2Ents.Label", { font = "Roboto", size = 18, weight = 700 })
surface.CreateFont("TF2Ents.Announce", { font = "Roboto", size = 42, weight = 900 })

-- The top-centre of the screen can sit under a display notch (MacBook), so
-- the timer is pushed down by a fraction of the screen height.
local timer_y = CreateClientConVar("wetsand_hud_timer_y", "0.08", true, false, "Timer box top, as a fraction of screen height (clears display notches).")

local announcement


net.Receive("wetsand_pa_announce_text", function()
	announcement = {
		text = net.ReadString(),
		team = net.ReadUInt(2),
		expires = CurTime() + 4,
	}
end)

local function Clock(seconds)
	seconds = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function DrawTimer(w, h)
	-- free play shows no timer, as TF2's tournament pre-ready state
	if not GetGlobal2Bool("tf2.timer.show", false) or WETSAND.GameplayStopped() then return end
	local top = math.floor(h * timer_y:GetFloat())
	local left
	if GetGlobal2Bool("tf2.timer.paused", true) then
		left = GetGlobal2Float("tf2.timer.left", 0)
	else
		left = GetGlobal2Float("tf2.timer.end", 0) - CurTime()
	end
	local label
	if WETSAND.State() == WETSAND.STATE.PREROUND then
		label = "PREPARE"
	elseif GetGlobal2Bool("tf2.timer.setup", false) then
		label = "SETUP"
	elseif GetGlobal2Bool("tf2.overtime", false) then
		label = "OVERTIME"
	end
	draw.RoundedBox(6, w / 2 - 70, top, 140, label and 64 or 46, Color(0, 0, 0, 170))
	draw.SimpleText(Clock(left), "TF2Ents.Timer", w / 2, top + 4, color_white, TEXT_ALIGN_CENTER)
	if label then
		draw.SimpleText(label, "TF2Ents.Label", w / 2, top + 40, Color(255, 210, 90), TEXT_ALIGN_CENTER)
	end
end

-- Carts ---------------------------------------------------------------------------
-- tf2.cart.<i>.* per enabled team_train_watcher (sv_payload.lua), BLU first.

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
	local key = "tf2.cart." .. i .. "."
	return {
		team = GetGlobal2Int(key .. "team", WETSAND.TEAM_UNASSIGNED),
		progress = GetGlobal2Float(key .. "progress", 0),
		speed = GetGlobal2Int(key .. "speed", 0),
		cappers = GetGlobal2Int(key .. "cappers", 0),
		recedeAt = GetGlobal2Float(key .. "recedeAt", 0),
		canRecede = GetGlobal2Bool(key .. "canRecede", true),
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
		draw.SimpleText(label, "TF2Ents.Label", x - 14, y + barH / 2, WETSAND.TeamColor[cart.team] or color_white, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
	end
	local status = CartStatus(cart)
	if status ~= "" then
		draw.SimpleText(status, "TF2Ents.Label", x + barW / 2, y - 30, cart.alarm and ALARM or color_white, TEXT_ALIGN_CENTER)
	end
end

local function DrawCarts(w, h)
	local count = GetGlobal2Int("tf2.cart.count", 0)
	local race = GetGlobal2Bool("tf2.cart.race", false)
	local leader = GetGlobal2Int("tf2.cart.leader", 0)
	local barW = math.min(600, w * 0.5)
	local x = (w - barW) / 2
	for i = 1, count do
		DrawCartBar(Cart(i), x, h - 90 - (i - 1) * 52, barW, race, leader)
	end
end

-- Timed captures ------------------------------------------------------------------------
-- tf2.cap.<i>.* per control point captured by standing on it, under the timer.

local function Capture(i)
	local key = "tf2.cap." .. i .. "."
	return {
		index = GetGlobal2Int(key .. "index", 0),
		owner = GetGlobal2Int(key .. "owner", WETSAND.TEAM_UNASSIGNED),
		capping = GetGlobal2Int(key .. "capping", WETSAND.TEAM_UNASSIGNED),
		progress = GetGlobal2Float(key .. "progress", 0),
		blocked = GetGlobal2Bool(key .. "blocked", false),
		cappers = GetGlobal2Int(key .. "cappers", 0),
	}
end

local function DrawCapture(cap, x, y, size)
	local owner = WETSAND.TeamColor[cap.owner] or WETSAND.TeamColor[WETSAND.TEAM_UNASSIGNED]
	draw.RoundedBox(6, x, y, size, size, Color(0, 0, 0, 170))
	draw.RoundedBox(4, x + 4, y + 4, size - 8, size - 8, Color(owner.r, owner.g, owner.b, 200))
	draw.SimpleText(tostring(cap.index + 1), "TF2Ents.Timer", x + size / 2, y + size / 2 - 4, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	if cap.capping == WETSAND.TEAM_UNASSIGNED then return end
	local c = WETSAND.TeamColor[cap.capping] or color_white
	surface.SetDrawColor(20, 20, 20, 255)
	surface.DrawRect(x + 4, y + size - 12, size - 8, 8)
	surface.SetDrawColor(c.r, c.g, c.b, 255)
	surface.DrawRect(x + 4, y + size - 12, (size - 8) * cap.progress, 8)
	local label = cap.blocked and "BLOCKED" or ("x" .. cap.cappers)
	draw.SimpleText(label, "TF2Ents.Label", x + size / 2, y + size + 2, cap.blocked and ALARM or color_white, TEXT_ALIGN_CENTER)
end

local function DrawCaptures(w, h)
	local count = GetGlobal2Int("tf2.cap.count", 0)
	if count == 0 then return end
	local size, gap = 56, 8
	local x = (w - (count * size + (count - 1) * gap)) / 2
	local y = math.floor(h * timer_y:GetFloat()) + 72
	for i = 1, count do
		DrawCapture(Capture(i), x + (i - 1) * (size + gap), y, size)
	end
end

local function DrawAnnouncement(w, h)
	if not announcement or CurTime() > announcement.expires then return end
	local c = WETSAND.TeamColor[announcement.team] or color_white
	draw.SimpleTextOutlined(announcement.text, "TF2Ents.Announce", w / 2, h * 0.25, c, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 2, color_black)
end

local function DrawRespawn(w, h)
	local ply = LocalPlayer()
	if not IsValid(ply) or ply:Alive() then return end
	local at = ply:GetNW2Float("tf2.respawnAt", 0)
	if at <= 0 then return end
	local left = math.max(0, math.ceil(at - CurTime()))
	local text = left > 0 and ("Respawn in " .. left .. "s") or "Prepare to respawn"
	draw.SimpleTextOutlined(text, "TF2Ents.Label", w / 2, h * 0.7, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)
end

local function DrawPreround(w, h)
	if WETSAND.State() ~= WETSAND.STATE.PREROUND then return end
	local left = math.max(1, math.ceil(GetGlobal2Float("tf2.preroundEnd", 0) - CurTime()))
	draw.SimpleTextOutlined("Round begins in " .. left, "TF2Ents.Announce", w / 2, h * 0.35, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 2, color_black)
end

function WETSAND.DrawHUD()
	local w, h = ScrW(), ScrH()
	DrawTimer(w, h)
	DrawCarts(w, h)
	DrawCaptures(w, h)
	DrawPreround(w, h)
	DrawAnnouncement(w, h)
	DrawRespawn(w, h)
end
