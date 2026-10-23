-- The running vote on clients (ws/sh_votes.lua): its panel on the HUD, and
-- F1 (yes) and F2 (no) while the player may vote, as in TF2; on a vote of
-- choices (the next-map vote), F1 to F4 pick its options in order. Both in
-- cooler-hud v2.6's look (votehud.res, laid out by ws.vote_hud): the
-- VoteActive panel at the left, then VotePassed or VoteFailed in its place,
-- with TF2's vote sounds: a vote starting, the player's own cast landing
-- (Vote.Heard), which the panel then lights, and the result, which shows for
-- VoteHud.RESULT_SECONDS. A refused request is a notice. The Server tab
-- (ws/cl_menu_server.lua) reads WS.VoteState and WS.VoteMaps and hears
-- WSVoteChanged.
local Vote = WS.require("games.gameplay.vote")
local VoteHud = WS.require("ws.vote_hud")
local Hud = WS.require("ws.tf_hud")
local E = WS.Events
local UI = WS.UI
local Font, DrawImage, DrawPanel = WS.TFHud.Font, WS.TFHud.DrawImage, WS.TFHud.DrawPanel

local REFUSED_SECONDS = 4
local REFUSED_SOUND = "buttons/button10.wav"

-- TF2's game_sounds_vo_vote... Vote.Created, Vote.Cast.Yes, .No, Vote.Passed and .Failed.
local STARTED_SOUND = "ui/vote_started.wav"
local YES_SOUND, NO_SOUND = "ui/vote_yes.wav", "ui/vote_no.wav"
local PASSED_SOUND, FAILED_SOUND = "ui/vote_success.wav", "ui/vote_failure.wav"

local function Rgba(c) return Color(c.r, c.g, c.b, c.a) end
local GREY, SELECTED, BOX_EDGE, FAILED = Rgba(VoteHud.GREY), Rgba(VoteHud.SELECTED), Rgba(VoteHud.BOX_EDGE), Rgba(VoteHud.FAILED)
-- Between the header's text and the clock at its right.
local CLOCK_GAP = 4

WS.VoteState = WS.VoteState or { running = false, cast = Vote.BALLOT_NONE }
WS.VoteMaps = WS.VoteMaps or {}

E.Listen("game_vote_state", "ws_votes", function(fields)
	local heard = Vote.Heard(WS.VoteState, fields)
	WS.VoteState = fields
	if heard == Vote.HEARD_STARTED then
		surface.PlaySound(STARTED_SOUND)
	elseif heard == Vote.HEARD_CAST then
		surface.PlaySound(fields.cast == Vote.BALLOT_NO and #fields.options == 0 and NO_SOUND or YES_SOUND)
	end
	hook.Run("WSVoteChanged")
end)

E.Listen("game_vote_maps", "ws_votes", function(fields)
	WS.VoteMaps = fields.maps
	hook.Run("WSVoteChanged")
end)

-- The last result: { panel (VoteHud.Result), untilTime }.
local result

E.Listen("game_vote_ended", "ws_votes", function(fields)
	result = { panel = VoteHud.Result(fields), untilTime = CurTime() + VoteHud.RESULT_SECONDS }
	surface.PlaySound(fields.passed and PASSED_SOUND or FAILED_SOUND)
end)

E.Listen("game_vote_refused", "ws_votes", function(fields)
	notification.AddLegacy(fields.text, NOTIFY_ERROR, REFUSED_SECONDS)
	surface.PlaySound(REFUSED_SOUND)
end)

-- GMod's F1 and F2 binds, taken only while the player may vote.
local CASTS = {
	gm_showhelp = true,
	gm_showteam = false,
}
-- GMod's F1 to F4 binds, an option each on a vote of choices.
local OPTION_BINDS = {
	gm_showhelp = 1,
	gm_showteam = 2,
	gm_showspare1 = 3,
	gm_showspare2 = 4,
}

-- A ballot: yes or no, or the option chosen (1..) on a vote of choices.
local function Cast(yes, choice)
	E.Request("game_vote_cast", { yes = yes, choice = choice })
end

hook.Add("PlayerBindPress", "ws_votes", function(_, bind, pressed)
	if not pressed then return end
	local state = WS.VoteState
	if not (state.running and state.mine) then return end
	if #state.options > 0 then
		local choice = OPTION_BINDS[bind]
		if choice == nil or choice > #state.options then return end
		Cast(false, choice)
		return true
	end
	local yes = CASTS[bind]
	if yes == nil then return end
	Cast(yes, 0)
	return true
end)

-- With C held (the context menu), the panel's rows take a click: a panel
-- over it in the context menu sends the row under the cursor (the rows the
-- panel last drew, clickRows: { y, h, yes, choice } in screen space, within
-- cardRect).
local clickRows, cardRect = {}, nil

UI.Define("VoteClicks", "DPanel", {
	Init = function(self)
		self:SetCursor("hand")
	end,
	Think = function(self)
		local state = WS.VoteState
		local open = state.running and state.mine and cardRect ~= nil
		self:SetVisible(open)
		if open then self:SetPos(cardRect.x, cardRect.y) self:SetSize(cardRect.w, cardRect.h) end
	end,
	Paint = function() end,
	OnMousePressed = function(self, code)
		if code ~= MOUSE_LEFT then return end
		local _, my = gui.MousePos()
		for _, row in ipairs(clickRows) do
			if my >= row.y and my < row.y + row.h then
				Cast(row.yes, row.choice)
				return
			end
		end
	end,
})

local clicks

hook.Add("OnContextMenuOpen", "ws_votes", function()
	if IsValid(clicks) or not IsValid(g_ContextMenu) then return end
	clicks = vgui.Create(UI.Name("VoteClicks"), g_ContextMenu)
end)

-- A label's text wrapped to its width as vgui's wrapping labels do (GMod's
-- markup), parsed again only when what it shows changes; slot names the
-- label.
local wrapped = {}

local function Wrapped(slot, text, font, width, color)
	local key = table.concat({ text, font, math.floor(width), color.r, color.g, color.b, color.a }, "\0")
	local held = wrapped[slot]
	if held and held.key == key then return held.markup end
	local parsed = markup.Parse(string.format("<font=%s><color=%d,%d,%d,%d>%s</color></font>", font,
		color.r, color.g, color.b, color.a, markup.Escape(text)), width)
	wrapped[slot] = { key = key, markup = parsed }
	return parsed
end

local function Rect(x, y, w, h) return { x = x, y = y, w = w, h = h } end

-- VoteBarPanel::Paint's box: a grey edge, black inside, the icon inset
-- twice the edge.
local function DrawBox(icon, x, y, unit)
	local size, inset = VoteHud.BOX_SIZE * unit, VoteHud.BOX_INSET * unit
	surface.SetDrawColor(BOX_EDGE)
	surface.DrawRect(x, y, size, size)
	surface.SetDrawColor(0, 0, 0, 255)
	surface.DrawRect(x + inset, y + inset, size - inset * 2, size - inset * 2)
	DrawImage(icon, Rect(x + inset * 2, y + inset * 2, size - inset * 4, size - inset * 4))
end

local function DrawActive(state, h)
	local unit = Hud.Unit(h)
	local card = VoteHud.Active(state, CurTime())
	local left, top = VoteHud.PANEL_X * unit, VoteHud.PANEL_Y * unit
	local function X(x) return left + x * unit end
	local function Y(y) return top + y * unit end
	local panel = Rect(left, top, VoteHud.PANEL_W * unit, card.tall * unit)
	DrawPanel(VoteHud.PANEL_IMAGE, panel, unit)
	local tiny = Font(Hud.FONT_SECONDARY, VoteHud.VERY_SMALL_FONT_TALL, unit)
	local small = Font(Hud.FONT_SECONDARY, VoteHud.SMALL_FONT_TALL, unit)

	-- the header, and the time left at its right
	surface.SetFont(tiny)
	local clockW = surface.GetTextSize(card.clock)
	local headerRight = X(VoteHud.HEADER_X + VoteHud.HEADER_W)
	draw.SimpleText(card.clock, tiny, headerRight, Y(VoteHud.HEADER_Y), GREY, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
	Wrapped("header", card.header, tiny, VoteHud.HEADER_W * unit - clockW - CLOCK_GAP * unit, GREY)
		:Draw(X(VoteHud.HEADER_X), Y(VoteHud.HEADER_Y), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
	Wrapped("issue", card.issue, small, VoteHud.ISSUE_W * unit, color_white)
		:Draw(X(VoteHud.ISSUE_X), Y(VoteHud.ISSUE_Y), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
	surface.SetDrawColor(GREY)
	surface.DrawRect(X(VoteHud.DIVIDER_X), Y(VoteHud.DIVIDER_Y), VoteHud.DIVIDER_W * unit, math.max(1, unit))

	-- the rows, the player's cast lit behind its own
	clickRows, cardRect = {}, panel
	local rowW, rowH = VoteHud.OPTION_W * unit, VoteHud.OPTION_TALL * unit
	for i, row in ipairs(card.rows) do
		local y = Y(VoteHud.RowY(i))
		if row.lit then
			surface.SetDrawColor(SELECTED)
			surface.DrawRect(X(VoteHud.OPTION_X), y, rowW, rowH)
		end
		draw.SimpleText(row.text, tiny, X(VoteHud.OPTION_X), y + rowH / 2, color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		if row.count then
			draw.SimpleText(row.count, tiny, X(VoteHud.OPTION_X + VoteHud.OPTION_W - VoteHud.OPTION_COUNT_INSET), y + rowH / 2,
				color_white, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		end
		if row.cast then clickRows[#clickRows + 1] = { y = y, h = rowH, yes = row.cast.yes, choice = row.cast.choice } end
	end
	if not card.yesNo then return end

	-- the count line, and the vote bar with each side's count
	surface.SetDrawColor(GREY)
	surface.DrawRect(X(VoteHud.DIVIDER_X), Y(VoteHud.DIVIDER2_Y), VoteHud.DIVIDER_W * unit, math.max(1, unit))
	draw.SimpleText(VoteHud.COUNT_LABEL, tiny, X(VoteHud.COUNT_LABEL_X), Y(VoteHud.COUNT_LABEL_Y), GREY, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
	DrawBox(VoteHud.YES_ICON, X(VoteHud.BAR_X), Y(VoteHud.BAR_Y), unit)
	DrawBox(VoteHud.NO_ICON, X(VoteHud.BAR_X + VoteHud.NO_BOX_X), Y(VoteHud.BAR_Y), unit)
	local countY = Y(VoteHud.COUNT_Y + VoteHud.BOX_SIZE / 2)
	draw.SimpleText(card.yes, small, X(VoteHud.YES_COUNT_X + VoteHud.COUNT_W / 2), countY, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	draw.SimpleText(card.no, small, X(VoteHud.NO_COUNT_X + VoteHud.COUNT_W / 2), countY, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

WS.HUD:Add("game.notices.votes", WS.HUD_ORDER.NOTICES, function(_, h)
	local state = WS.VoteState
	if not state.running then
		cardRect = nil
		return
	end
	DrawActive(state, h)
end, WS.Active)

-- VotePassed or VoteFailed, where the running vote's panel was, fading as
-- it goes; a new vote takes the place.
local function DrawResult(r, h)
	local unit = Hud.Unit(h)
	local panel = r.panel
	local left, top = VoteHud.PANEL_X * unit, VoteHud.PANEL_Y * unit
	local function X(x) return left + x * unit end
	local function Y(y) return top + y * unit end
	surface.SetAlphaMultiplier(VoteHud.ResultAlpha(CurTime(), r.untilTime))
	DrawPanel(VoteHud.PANEL_IMAGE, Rect(left, top, VoteHud.PANEL_W * unit, VoteHud.RESULT_TALL * unit), unit)
	local icon = VoteHud.RESULT_ICON_SIZE * unit
	DrawImage(panel.icon, Rect(X(VoteHud.RESULT_ICON_X), Y(VoteHud.RESULT_ICON_Y), icon, icon))
	draw.SimpleText(panel.title, Font(Hud.FONT_SECONDARY, VoteHud.SMALL_FONT_TALL, unit), X(VoteHud.RESULT_TITLE_X),
		Y(VoteHud.RESULT_TITLE_Y + VoteHud.RESULT_TITLE_TALL / 2), panel.passed and color_white or FAILED, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	Wrapped("result", panel.text, Font(Hud.FONT_SECONDARY, VoteHud.VERY_SMALL_FONT_TALL, unit), VoteHud.RESULT_TEXT_W * unit, color_white)
		:Draw(X(VoteHud.RESULT_TEXT_X), Y(VoteHud.RESULT_TEXT_Y), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
	surface.SetAlphaMultiplier(1)
end

WS.HUD:Add("game.notices.vote_result", WS.HUD_ORDER.NOTICES, function(_, h)
	if result == nil or CurTime() >= result.untilTime or WS.VoteState.running then return end
	DrawResult(result, h)
end)
