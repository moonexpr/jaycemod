-- The capture feature's view: TF2's control point HUD (CHudControlPointIcons)
-- drawn from what the capture controller networks (wetsand_point_*). Each
-- point is an icon in the master's caplayout rows under the round timer:
-- its owner's colour and number, a padlock bar while locked and the unlock
-- countdown, the capture progress in the capping team's colour, the cappers
-- (xN, or N/required when a fixed count is needed) or BLOCKED, which teams
-- may cap it, dimmed when out of the mini-round, and a tf_logic_cp_timer's
-- countdown. The local player standing on a point sees why they may not
-- capture it (CControlPointProgressBar). The unlock countdown speaks 5..1,
-- then the capture-enabled line (CControlPointCountdown::OnTick).
WETSAND.Feature("rounds")
local Capture = WETSAND.require("foundation.capture")
local Text = WETSAND.require("foundation.rounds.text")

local NOBODY, RED, BLUE = WETSAND.TEAM_UNASSIGNED, WETSAND.TEAM_RED, WETSAND.TEAM_BLUE
local NO_POINT_STOOD_ON = 0

local ICON_SIZE = 48
local ICON_GAP = 8
local ROW_GAP = 22 -- room for the cappers line under each row
local BELOW_TIMER = 72 -- the round timer's box height and a margin
local INSET = 4
local BAR_HEIGHT = 7
local TICK_SIZE = 7
local LOCK_BAR_HEIGHT = 6
local DIM_ALPHA = 70
local FILL_ALPHA = 200
local PANEL_ABOVE_CROSSHAIR = 70
local PANEL_WIDTH = 260
local PANEL_HEIGHT = 34
local CORNER = 6

local BACK = Color(0, 0, 0, 170)
local BAR_BACK = Color(20, 20, 20, 255)
local LOCK = Color(120, 120, 120, 255)
local ALERT = Color(230, 60, 40)
local GOLD = Color(255, 210, 90)

local FONT_NUMBER = "Sandcastle.Capture.Number"
local FONT_LABEL = "Sandcastle.Capture.Label"

surface.CreateFont(FONT_NUMBER, {
	font = "Roboto",
	size = 26,
	weight = 800,
})
surface.CreateFont(FONT_LABEL, {
	font = "Roboto",
	size = 16,
	weight = 700,
})

-- The rounds view's convar: where the timer's box starts.
local timerY = GetConVar("wetsand_hud_timer_y")

local UNLOCK_WARNINGS = {
	[5] = "Announcer.RoundBegins5Seconds",
	[4] = "Announcer.RoundBegins4Seconds",
	[3] = "Announcer.RoundBegins3Seconds",
	[2] = "Announcer.RoundBegins2Seconds",
	[1] = "Announcer.RoundBegins1Seconds",
}
local UNLOCK_WARN_FROM = 5
local CAP_ENABLED = "Announcer.AM_CapEnabledRandom"

local View = {
	localized = {},
	english = nil,
	unlockAt = 0,
	unlockArmed = {},
	zeroArmed = false,
}

local function Key(rank, field)
	return "wetsand_point_" .. rank .. "_" .. field
end

-- What the controller published for the point of rank (0-based).
local function Point(rank)
	local r = rank + 1
	return {
		rank = rank,
		owner = GetGlobal2Int(Key(r, "owner"), NOBODY),
		locked = GetGlobal2Bool(Key(r, "locked"), false),
		unlockTime = GetGlobal2Float(Key(r, "unlock_time"), 0),
		capping = GetGlobal2Int(Key(r, "capping"), NOBODY),
		progress = GetGlobal2Float(Key(r, "progress"), 0),
		cappers = GetGlobal2Int(Key(r, "cappers"), 0),
		required = GetGlobal2Int(Key(r, "required"), 0),
		blocked = GetGlobal2Bool(Key(r, "blocked"), false),
		redCanCap = GetGlobal2Bool(Key(r, "red_can_cap"), false),
		blueCanCap = GetGlobal2Bool(Key(r, "blue_can_cap"), false),
		inRound = GetGlobal2Bool(Key(r, "in_round"), true),
		hidden = GetGlobal2Bool(Key(r, "hidden"), false),
		name = GetGlobal2String(Key(r, "name"), ""),
		timerEnd = GetGlobal2Float(Key(r, "timer_end"), 0),
	}
end

function View:Localize(token)
	if self.localized[token] == nil then
		self.english = self.english or file.Read("resource/tf_english.txt", "tf") or ""
		self.localized[token] = Text.Localize(self.english, token) or false
	end
	return self.localized[token] or token
end

local function TeamColor(team)
	return WETSAND.TeamColor[team] or WETSAND.TeamColor[NOBODY]
end

local function Seconds(at)
	return math.max(0, math.ceil(at - CurTime()))
end

local function CappersText(p)
	if p.blocked then return "BLOCKED", ALERT end
	if p.cappers <= 0 then return nil end
	if p.required > 0 then return p.cappers .. "/" .. p.required, color_white end
	return "x" .. p.cappers, color_white
end

local function DrawIcon(p, x, y)
	local owner = TeamColor(p.owner)
	local alpha = p.inRound and FILL_ALPHA or DIM_ALPHA
	local inner = ICON_SIZE - 2 * INSET
	draw.RoundedBox(CORNER, x, y, ICON_SIZE, ICON_SIZE, BACK)
	draw.RoundedBox(INSET, x + INSET, y + INSET, inner, inner, Color(owner.r, owner.g, owner.b, alpha))
	draw.SimpleText(tostring(p.rank + 1), FONT_NUMBER, x + ICON_SIZE / 2, y + ICON_SIZE / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	if p.locked then
		surface.SetDrawColor(LOCK)
		surface.DrawRect(x + INSET, y + INSET, inner, LOCK_BAR_HEIGHT)
		if p.unlockTime > CurTime() then
			draw.SimpleText(tostring(Seconds(p.unlockTime)), FONT_LABEL, x + ICON_SIZE / 2, y - 2, GOLD, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
		end
	end
	if p.capping ~= NOBODY then
		local c = TeamColor(p.capping)
		local barY = y + ICON_SIZE - INSET - BAR_HEIGHT
		surface.SetDrawColor(BAR_BACK)
		surface.DrawRect(x + INSET, barY, inner, BAR_HEIGHT)
		surface.SetDrawColor(c.r, c.g, c.b, 255)
		surface.DrawRect(x + INSET, barY, inner * p.progress, BAR_HEIGHT)
	end
	if p.redCanCap then
		local c = TeamColor(RED)
		surface.SetDrawColor(c.r, c.g, c.b, 255)
		surface.DrawRect(x, y + ICON_SIZE - TICK_SIZE, TICK_SIZE, TICK_SIZE)
	end
	if p.blueCanCap then
		local c = TeamColor(BLUE)
		surface.SetDrawColor(c.r, c.g, c.b, 255)
		surface.DrawRect(x + ICON_SIZE - TICK_SIZE, y + ICON_SIZE - TICK_SIZE, TICK_SIZE, TICK_SIZE)
	end
	local label, labelColor = CappersText(p)
	if p.timerEnd > CurTime() then label, labelColor = string.format("%d:%02d", math.floor(Seconds(p.timerEnd) / 60), Seconds(p.timerEnd) % 60), GOLD end
	if label then draw.SimpleText(label, FONT_LABEL, x + ICON_SIZE / 2, y + ICON_SIZE + 2, labelColor, TEXT_ALIGN_CENTER) end
end

-- The layout's rows of shown points.
local function Rows(count)
	local rows = {}
	for _, row in ipairs(Capture.Layout(GetGlobal2String("wetsand_point_layout", ""), count)) do
		local shown = {}
		for _, rank in ipairs(row) do
			local p = Point(rank)
			if not p.hidden then shown[#shown + 1] = p end
		end
		if #shown > 0 then rows[#rows + 1] = shown end
	end
	return rows
end

local function DrawIcons(w, h)
	local y = math.floor(h * timerY:GetFloat()) + BELOW_TIMER
	for _, row in ipairs(Rows(GetGlobal2Int("wetsand_point_count", 0))) do
		local x = (w - (#row * ICON_SIZE + (#row - 1) * ICON_GAP)) / 2
		for i, p in ipairs(row) do DrawIcon(p, x + (i - 1) * (ICON_SIZE + ICON_GAP), y) end
		y = y + ICON_SIZE + ROW_GAP
	end
end

-- The capture panel: the point's progress while the player's team caps it,
-- else why it may not.
local function DrawPanel(w, h)
	local ply = LocalPlayer()
	local rank = ply:GetNW2Int("wetsand_capture_point", NO_POINT_STOOD_ON)
	if rank == NO_POINT_STOOD_ON or WETSAND.State() == WETSAND.STATE.TEAM_WIN then return end
	local x, y = (w - PANEL_WIDTH) / 2, h / 2 - PANEL_ABOVE_CROSSHAIR - PANEL_HEIGHT
	draw.RoundedBox(CORNER, x, y, PANEL_WIDTH, PANEL_HEIGHT, BACK)
	local reason = ply:GetNW2Int("wetsand_capture_reason", Capture.REASON_NONE)
	if reason == Capture.REASON_NONE then
		local p = Point(rank - 1)
		local c = TeamColor(p.capping)
		surface.SetDrawColor(c.r, c.g, c.b, 255)
		surface.DrawRect(x + INSET, y + INSET, (PANEL_WIDTH - 2 * INSET) * p.progress, PANEL_HEIGHT - 2 * INSET)
		return
	end
	draw.SimpleText(View:Localize(Capture.REASON_TOKEN[reason]), FONT_LABEL, w / 2, y + PANEL_HEIGHT / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

-- Every round mode that loads capture (control points, KOTH, payload)
-- shows its points; payload's cart points come hidden.
hook.Add("SandcastleHUDPaint", "wetsand_capture", function(w, h)
	DrawIcons(w, h)
	DrawPanel(w, h)
end)

-- The first locked point's pending unlock.
local function PendingUnlock()
	for rank = 0, GetGlobal2Int("wetsand_point_count", 0) - 1 do
		local p = Point(rank)
		if p.locked and p.unlockTime > 0 then return p.unlockTime end
	end
	return 0
end

local function Play(name)
	local ply = LocalPlayer()
	if IsValid(ply) then ply:EmitSound(name) end
end

-- CControlPointCountdown::OnTick: armed for each second the unlock is
-- still that far off; 5..1 while the round runs, then the capture line.
hook.Add("Think", "wetsand_capture_unlock", function()
	local pending = PendingUnlock()
	if pending > 0 and pending ~= View.unlockAt then
		View.unlockAt = pending
		View.zeroArmed = true
		for s in pairs(UNLOCK_WARNINGS) do View.unlockArmed[s] = pending - CurTime() >= s end
	end
	if View.unlockAt <= 0 or WETSAND.State() ~= WETSAND.STATE.RND_RUNNING then return end
	local left = math.floor(View.unlockAt - CurTime())
	if left <= 0 then
		if View.zeroArmed then Play(CAP_ENABLED) end
		View.zeroArmed = false
		View.unlockAt = 0
	elseif left <= UNLOCK_WARN_FROM and View.unlockArmed[left] then
		View.unlockArmed[left] = false
		Play(UNLOCK_WARNINGS[left])
	end
end)

return View
