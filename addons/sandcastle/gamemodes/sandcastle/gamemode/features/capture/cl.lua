-- The capture feature's view: TF2's control point HUD (CHudControlPointIcons)
-- drawn from what the capture controller networks (ws_point_*). Each
-- point is an icon in the master's caplayout rows, centred at the bottom of
-- the screen and scaled with its height as TF2 lays them out
-- (foundation.capture.hud), except in payload rounds, whose cart HUD takes
-- the bottom centre, drawn in TF2's materials (ControlPointIcon.res): the
-- map's icon for its owner (team_icon_N), its _locked version while locked
-- with the unlock countdown over it (CControlPointCountdown), the capping
-- team's icon_obj_cap fill rising with the capture, the capture icon and
-- cappers (xN, or N/required when a fixed count is needed) or blocked,
-- dimmed when out of the mini-round, and a tf_logic_cp_timer's clock on
-- icon_obj_timer. The local player standing on a point sees why they may not
-- capture it (CControlPointProgressBar). The unlock countdown speaks 5..1,
-- then the capture-enabled line (CControlPointCountdown::OnTick).
WS.Feature("rounds")
local Capture = WS.require("foundation.capture")
local Hud = WS.require("foundation.capture.hud")
local Rounds = WS.require("foundation.rounds")

local NOBODY, RED, BLUE = WS.TEAM_UNASSIGNED, WS.TEAM_RED, WS.TEAM_BLUE
local NO_POINT_STOOD_ON = 0

-- The icons' fonts, in TF2's HUD units (foundation.capture.hud): the
-- unlock countdown's (ControlPointTimer) and the cappers' (CapPlayerFont).
local NUMBER_FONT_SIZE = 18
local INSET = 4 -- the capture panel's, in pixels
local DIM_ALPHA = 70
local PANEL_ABOVE_CROSSHAIR = 70
local PANEL_WIDTH = 260
local PANEL_HEIGHT = 34
local CORNER = 6

-- The capture panel, TF2's target ID: a white rounded border round a dark fill.
local PANEL_BORDER, PANEL_FILL, PANEL_EDGE = 2, Color(30, 28, 26, 235), color_white
local ANCHOR_LIFT = 24 -- how far above the object's top the panel sits
local ALERT = Color(230, 60, 40)

local FONT_NUMBER = "Sandcastle.Capture.Number"
local FONT_LABEL = "Sandcastle.Capture.Label"
local FONT_REASON = "Sandcastle.Capture.Reason"

-- HUD units to pixels on a screen h pixels tall, at least one.
local function Pixels(units, h)
	return math.max(1, math.floor(units * h / Hud.UNITS_TALL))
end

-- The icons' fonts, sized with the screen's height.
local function CreateFonts()
	surface.CreateFont(FONT_NUMBER, {
		font = "TF2 Build",
		size = Pixels(NUMBER_FONT_SIZE, ScrH()),
		weight = 500,
	})
	surface.CreateFont(FONT_LABEL, {
		font = "TF2 Build",
		size = Pixels(Hud.LABEL, ScrH()),
		weight = 500,
	})
	surface.CreateFont(FONT_REASON, {
		font = Hud.REASON_FONT,
		size = Pixels(Hud.REASON_TALL, ScrH()),
		weight = Hud.REASON_WEIGHT,
		outline = true,
	})
end
CreateFonts()
hook.Add("OnScreenSizeChanged", "ws_capture_fonts", CreateFonts)

local UNLOCK_WARNINGS = {
	[60] = "Announcer.CompGame1Begins60Seconds",
	[30] = "Announcer.CompGame1Begins30Seconds",
	[10] = "Announcer.CompGame1Begins10Seconds",
	[5] = "Announcer.CompGameBegins05Seconds",
	[4] = "Announcer.CompGameBegins04Seconds",
	[3] = "Announcer.CompGameBegins03Seconds",
	[2] = "Announcer.CompGameBegins02Seconds",
	[1] = "Announcer.CompGameBegins01Seconds",
	[0] = "Announcer.CompGameBeginsFight"
}
local UNLOCK_WARN_FROM = 5
local CAP_ENABLED = "Announcer.AM_CapEnabledRandom"

local View = {
	unlockAt = 0,
	unlockArmed = {},
	zeroArmed = false,
}

local function Key(rank, field)
	return "ws_point_" .. rank .. "_" .. field
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
		icon = GetGlobal2String(Key(r, "icon"), Capture.ICON_DEFAULT[NOBODY]),
	}
end

-- A TF2 token worded in the player's language (WS.Localize), or the
-- token itself when no language has it.
function View:Localize(token)
	return WS.Localize(token) or token
end

local function TeamColor(team)
	return WS.TeamColor[team] or WS.TeamColor[NOBODY]
end

local function Seconds(at)
	return math.max(0, math.ceil(at - CurTime()))
end

-- TF2's ControlPointIcon.res, in its 33-unit icon: the capture icon and
-- the cappers' count (#ControlPointIconCappers), centred on it as its
-- layout code places them, the unlock countdown (CControlPointCountdown)
-- over all of it, and a
-- tf_logic_cp_timer's clock on icon_obj_timer, twice as wide, behind it.
local ICON_UNITS = 33
local CAPPER_W, CAPPER_H = 10, 20
local TIMER_BG_W = 66
local TAN_LIGHT = Color(235, 226, 202)
local CAP_FILL = { [RED] = "sprites/obj_icons/icon_obj_cap_red", [BLUE] = "sprites/obj_icons/icon_obj_cap_blu" }

local MATERIALS = {}
local function Mat(name)
	MATERIALS[name] = MATERIALS[name] or Material(name)
	return MATERIALS[name]
end

-- A locked point's icon: the map icon's _locked version where one ships
-- (the numbered icon_obj_N_*), else the icon itself, dimmed.
local function LockedIcon(icon)
	local locked = Mat(icon .. "_locked")
	if not locked:IsError() then return locked, false end
	return Mat(icon), true
end

local function Image(material, x, y, w, h)
	surface.SetMaterial(material)
	surface.DrawTexturedRect(x, y, w, h)
end

-- The cappers' count: N, or N/required when a fixed count is needed.
local function CappersText(p)
	if p.required > 0 then return p.cappers .. "/" .. p.required end
	return "x" .. p.cappers
end

-- The capture sweep: icon_obj_cap_<team>, twice as wide as the icon, a fill
-- ending in a chevron at its middle, slid across the icon so the chevron's
-- tip stands at the capture's share, and masked to the icon's rounded square
-- by its detail texture (capture_highlight, $separatedetailuvs), so each
-- layer takes its own texture coordinates: a mesh quad, which surface's
-- draws (one set) cannot give.
local function DrawSweep(material, x, y, size, progress, alpha)
	local w = size * progress
	local u0 = 1 - progress / 2 -- the base's u at the icon's left edge
	cam.Start2D()
	render.SetMaterial(material)
	mesh.Begin(MATERIAL_QUADS, 1)
	local function Corner(px, py, u, v, mu, mv)
		mesh.Position(Vector(px, py, 0))
		mesh.TexCoord(0, u, v)
		mesh.TexCoord(1, mu, mv)
		mesh.Color(255, 255, 255, alpha)
		mesh.AdvanceVertex()
	end
	Corner(x, y, u0, 0, 0, 0)
	Corner(x + w, y, 1, 0, progress, 0)
	Corner(x + w, y + size, 1, 1, progress, 1)
	Corner(x, y + size, u0, 1, 0, 1)
	mesh.End()
	cam.End2D()
end

-- The cappers, centred on the icon as CControlPointIcon lays them out: the
-- capture icon, then their count.
local function DrawCappers(p, x, y, size, s)
	local text = CappersText(p)
	surface.SetFont(FONT_LABEL)
	local textW = surface.GetTextSize(text)
	local imageW, imageH = CAPPER_W * s, CAPPER_H * s
	local left = x + (size - (imageW + textW)) / 2
	surface.SetDrawColor(255, 255, 255, 255)
	Image(Mat("vgui/capture_icon"), left, y + (size - imageH) / 2, imageW, imageH)
	draw.SimpleTextOutlined(text, FONT_LABEL, left + imageW, y + size / 2, TAN_LIGHT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 1, color_black)
end

-- A point's icon, size pixels square at x, y on a screen h pixels tall:
-- its owner's icon from the map (team_icon_N), dimmed out of the mini-round,
-- the capping team's sweep with the capture, blocked or, while it is being
-- captured, its cappers, and the unlock countdown or the point's timer.
local function DrawIcon(p, x, y, size, h)
	local s = size / ICON_UNITS
	local alpha = p.inRound and 255 or DIM_ALPHA
	local icon, dim = Mat(p.icon), false
	if p.locked then icon, dim = LockedIcon(p.icon) end
	if p.timerEnd > CurTime() then
		surface.SetDrawColor(255, 255, 255, alpha)
		Image(Mat("sprites/obj_icons/icon_obj_timer"), x, y, TIMER_BG_W * s, size)
		local left = Seconds(p.timerEnd)
		draw.SimpleText(string.format("%d:%02d", math.floor(left / 60), left % 60), FONT_LABEL,
			x + (ICON_UNITS + (TIMER_BG_W - ICON_UNITS) / 2) * s, y + size / 2, TAN_LIGHT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	surface.SetDrawColor(255, 255, 255, dim and DIM_ALPHA or alpha)
	Image(icon, x, y, size, size)
	if CAP_FILL[p.capping] and p.progress > 0 then DrawSweep(Mat(CAP_FILL[p.capping]), x, y, size, p.progress, alpha) end
	surface.SetDrawColor(255, 255, 255, alpha)
	if p.blocked then
		Image(Mat("hud/cart_blocked"), x + size / 4, y + size / 4, size / 2, size / 2)
	elseif p.capping ~= NOBODY and p.cappers > 0 then
		-- only a point in contest shows who is on it
		DrawCappers(p, x, y, size, s)
	end
	if p.locked and p.unlockTime > CurTime() then
		draw.SimpleTextOutlined(tostring(Seconds(p.unlockTime)), FONT_NUMBER, x + size / 2, y + size / 2, TAN_LIGHT,
			TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)
	end
end

-- The layout's rows of shown points.
local function Rows(count)
	local rows = {}
	for _, row in ipairs(Capture.Layout(GetGlobal2String("ws_point_layout", ""), count)) do
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
	if not Hud.Shown(GetGlobal2Int("ws_round_hud_type", Rounds.HUD_NONE)) then return end
	local rows = Rows(GetGlobal2Int("ws_point_count", 0))
	local sizes = {}
	for i, row in ipairs(rows) do sizes[i] = #row end
	local layout = Hud.Layout(sizes, w, h)
	for line, row in ipairs(rows) do
		for i, p in ipairs(row) do
			local at = layout.rows[line][i]
			DrawIcon(p, at.x, at.y, layout.size, h)
		end
	end
end

-- Why the player may not cap, in TF2's target ID font, outlined, one line
-- per line of TF2's string (its "\n"), fading white -> red -> white; the
-- box grows to hold it.
-- A capture panel's box: TF2's white rounded border round a dark fill.
local function PanelBox(x, y, boxW, boxH)
	draw.RoundedBox(CORNER, x - PANEL_BORDER, y - PANEL_BORDER, boxW + 2 * PANEL_BORDER, boxH + 2 * PANEL_BORDER, PANEL_EDGE)
	draw.RoundedBox(CORNER, x, y, boxW, boxH, PANEL_FILL)
end

-- The object the player caps at, the panel's anchor in the world: the
-- point, or the cart its area rides; NULL when the server names none or
-- this client was not sent it (a hidden point).
local function PanelAnchor(ply)
	return ply:GetNW2Entity("ws_capture_anchor")
end

local function DrawReason(text, centre, bottom)
	local lines = string.Explode("\n", text)
	surface.SetFont(FONT_REASON)
	local lineW, lineH = 0, select(2, surface.GetTextSize("M"))
	for _, line in ipairs(lines) do lineW = math.max(lineW, (surface.GetTextSize(line))) end
	local boxW = math.max(PANEL_WIDTH, lineW + 4 * INSET)
	local boxH = math.max(PANEL_HEIGHT, lineH * #lines + 2 * INSET)
	local y = bottom - boxH
	PanelBox(centre - boxW / 2, y, boxW, boxH)
	local red = Hud.ReasonRedness(CurTime())
	local color = Color(Lerp(red, 255, ALERT.r), Lerp(red, 255, ALERT.g), Lerp(red, 255, ALERT.b))
	local top = y + (boxH - lineH * #lines) / 2
	for i, line in ipairs(lines) do
		draw.SimpleText(line, FONT_REASON, centre, top + (i - 1) * lineH, color, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
	end
end

-- The capture panel: the point's progress while the player's team caps it,
-- else why it may not; nil when the player stands on no point.
local function PanelRank(ply)
	local rank = ply:GetNW2Int("ws_capture_point", NO_POINT_STOOD_ON)
	if rank == NO_POINT_STOOD_ON or WS.State() == WS.STATE.TEAM_WIN then return nil end
	return rank
end

-- The panel, centred on centre with its bottom at bottom, in the 2D space
-- being drawn (the screen, or the panel's plane in the world).
local function DrawPanelAt(ply, rank, centre, bottom)
	local reason = ply:GetNW2Int("ws_capture_reason", Capture.REASON_NONE)
	if reason ~= Capture.REASON_NONE then return DrawReason(View:Localize(Capture.REASON_TOKEN[reason]), centre, bottom) end
	local x, y = centre - PANEL_WIDTH / 2, bottom - PANEL_HEIGHT
	PanelBox(x, y, PANEL_WIDTH, PANEL_HEIGHT)
	local p = Point(rank - 1)
	local c = TeamColor(p.capping)
	surface.SetDrawColor(c.r, c.g, c.b, 255)
	surface.DrawRect(x + INSET, y + INSET, (PANEL_WIDTH - 2 * INSET) * p.progress, PANEL_HEIGHT - 2 * INSET)
end

-- Every round mode that loads capture (control points, KOTH, payload)
-- shows its points; payload's cart points come hidden. The panel is drawn
-- here only without an anchor in the world: above the crosshair.
WS.HUD:Add("game.objective.points", WS.HUD_ORDER.OBJECTIVES, function(w, h)
	DrawIcons(w, h)
	local ply = LocalPlayer()
	local rank = PanelRank(ply)
	if rank and not IsValid(PanelAnchor(ply)) then DrawPanelAt(ply, rank, w / 2, h / 2 - PANEL_ABOVE_CROSSHAIR) end
end, WS.Active)

-- With an anchor, the panel stands in the world above it, as TF2's target
-- ID does: fixed there, turned to face the camera, PANEL_SCALE world units
-- a pixel, so it grows as the player comes near and walls hide it.
local PANEL_SCALE = 0.2

hook.Add("PostDrawTranslucentRenderables", "ws_capture_panel", function(_, skybox)
	if skybox then return end
	local ply = LocalPlayer()
	local rank = PanelRank(ply)
	local anchor = PanelAnchor(ply)
	if not rank or not IsValid(anchor) then return end
	local at = anchor:LocalToWorld(Vector(0, 0, anchor:OBBMaxs().z + ANCHOR_LIFT))
	local facing = EyeAngles()
	facing:RotateAroundAxis(facing:Forward(), 90)
	facing:RotateAroundAxis(facing:Right(), 90)
	cam.Start3D2D(at, facing, PANEL_SCALE)
	DrawPanelAt(ply, rank, 0, 0)
	cam.End3D2D()
end)

-- The first locked point's pending unlock.
local function PendingUnlock()
	for rank = 0, GetGlobal2Int("ws_point_count", 0) - 1 do
		local p = Point(rank)
		if p.locked and p.unlockTime > 0 then return p.unlockTime end
	end
	return 0
end

local function Play(name)
	local ply = LocalPlayer()
	if not IsValid(ply) then return end

	-- CHAN_VOICE2 is important here so announcer doens't talk over herself.
	ply:EmitSound(name, SNDLVL_100dB, 100, CHAN_VOICE2)
end

-- CControlPointCountdown::OnTick: armed for each second the unlock is
-- still that far off; 5..1 while the round runs, then the capture line.
hook.Add("Think", "ws_capture_unlock", function()
	local pending = PendingUnlock()
	if pending > 0 and pending ~= View.unlockAt then
		View.unlockAt = pending
		View.zeroArmed = true
		for s in pairs(UNLOCK_WARNINGS) do View.unlockArmed[s] = pending - CurTime() >= s end
	end
	if View.unlockAt <= 0 or WS.State() ~= WS.STATE.RND_RUNNING then return end
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

-- The capture's game events (sh.lua), worded for the rounds HUD: a capture
-- is the announcement line, a defence a notice (for a point with a name).
-- A point's name is the map's token ("#Badwater_cap_1"), worded here.
WS.Events.Listen("game_teamplay_point_captured", "ws_capture_view", function(fields)
	local point = fields.cpname ~= "" and View:Localize(fields.cpname) or ("point " .. fields.cp)
	WS.Feature("rounds"):Announce(WS.TeamName[fields.team] .. " captured " .. point, fields.team)
end)

WS.Events.Listen("game_teamplay_capture_blocked", "ws_capture_view", function(fields)
	if fields.cpname == "" then return end
	WS.Feature("rounds"):Notice(WS.TeamName[fields.team] .. " defended " .. View:Localize(fields.cpname), fields.team)
end)

return View
