-- The running vote on clients (ws/sh_votes.lua): its card on the HUD, and
-- F1 (yes) and F2 (no) while the player may vote, as in TF2; on a vote of
-- choices (the next-map vote), F1 to F4 pick its options in order. Both in
-- WS.UI's look (ws/cl_ui.lua), in TF2's fonts as the nav progress box is,
-- with TF2's vote sounds: a vote starting, the player's own cast landing
-- (Vote.Heard), which the card then marks, and the result, which pops up
-- for RESULT_SECONDS. A refused request is a notice. The Server tab
-- (ws/cl_menu_server.lua) reads WS.VoteState and WS.VoteMaps and hears
-- WSVoteChanged.
local Vote = WS.require("games.gameplay.vote")
local E = WS.Events
local UI = WS.UI
local THEME = UI.THEME

local RESULT_SECONDS = 5
local RESULT_FADE = 0.5
local REFUSED_SECONDS = 4
local REFUSED_SOUND = "buttons/button10.wav"

-- TF2's game_sounds_vo_vote... Vote.Created, Vote.Cast.Yes, .No, Vote.Passed and .Failed.
local STARTED_SOUND = "ui/vote_started.wav"
local YES_SOUND, NO_SOUND = "ui/vote_yes.wav", "ui/vote_no.wav"
local PASSED_SOUND, FAILED_SOUND = "ui/vote_success.wav", "ui/vote_failure.wav"

-- TF2's 480-tall units, as the nav progress box sizes itself.
local CARD_X, CARD_Y_SHARE, CARD_W = 8, 0.3, 190
local LINE_TALL, GAP = 12, 3
local TITLE_TALL, BODY_TALL = 12, 9
local TITLE_FONT, BODY_FONT = "WS.Vote.Title", "WS.Vote.Body"
local RESULT_W, RESULT_TALL, RESULT_Y_SHARE, STRIPE = 220, 46, 0.12, 3
-- TF2's vote panel: its passed (Vote.Passed's check) and failed colours.
local PASSED_COLOR, FAILED_COLOR = Color(118, 178, 60), Color(189, 59, 59)

local fontsFor

local function Fonts(unit)
	if fontsFor == unit then return end
	surface.CreateFont(TITLE_FONT, { font = "TF2 Build", size = math.Round(TITLE_TALL * unit), weight = 500 })
	surface.CreateFont(BODY_FONT, { font = "TF2 Secondary", size = math.Round(BODY_TALL * unit), weight = 500 })
	fontsFor = unit
end

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

-- The result: the box, a stripe in its outcome's colour along its top, TF2's
-- Vote Passed! or Vote Failed and the line under it; it fades as it goes.
UI.Define("VoteResult", "DPanel", {
	Init = function(self)
		self:SetMouseInputEnabled(false)
		self:SetKeyboardInputEnabled(false)
	end,
	Show = function(self, fields, now)
		self.fields = fields
		self.untilTime = now + RESULT_SECONDS
	end,
	Think = function(self)
		local now = CurTime()
		if now >= self.untilTime then return self:Remove() end
		local unit = ScrH() / 480
		self:SetSize(RESULT_W * unit, RESULT_TALL * unit)
		self:SetPos((ScrW() - RESULT_W * unit) / 2, ScrH() * RESULT_Y_SHARE)
		self:SetAlpha(255 * math.Clamp((self.untilTime - now) / RESULT_FADE, 0, 1))
	end,
	Paint = function(self, w, h)
		local unit = h / RESULT_TALL
		Fonts(unit)
		UI.Box(w, h)
		local b, pad = THEME.borderWidth, GAP * 3 * unit
		local passed = self.fields.passed
		surface.SetDrawColor(passed and PASSED_COLOR or FAILED_COLOR)
		surface.DrawRect(b, b, w - b * 2, STRIPE * unit)
		draw.SimpleText(passed and "VOTE PASSED!" or "VOTE FAILED", TITLE_FONT, w / 2, pad + STRIPE * unit,
			passed and PASSED_COLOR or FAILED_COLOR, TEXT_ALIGN_CENTER)
		draw.SimpleText(self.fields.text, BODY_FONT, w / 2, h - pad, THEME.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
	end,
})

local resultBox

E.Listen("game_vote_ended", "ws_votes", function(fields)
	if not IsValid(resultBox) then resultBox = vgui.Create(UI.Name("VoteResult")) end
	resultBox:Show(fields, CurTime())
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
local OPTION_KEYS = { "F1", "F2", "F3", "F4" }

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

-- With C held (the context menu), the card's choices take a click: a
-- panel over the card in the context menu sends the row under the cursor
-- (the rows the card last drew, clickRows: { y, h, yes, choice } in screen
-- space, within cardRect).
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

-- lines: { text, font, color, right (a count, right-aligned), lit (the
-- player's cast: filled with the border's colour, its text dark, as a
-- selected WS.UI button is), cast ({ yes, choice }: what clicking it with C
-- held casts) }.
local function Card(lines, x, y, w, unit)
	local lineH, gap = LINE_TALL * unit, GAP * unit
	local h = #lines * lineH + gap * 2
	UI.Box(w, h, x, y)
	clickRows, cardRect = {}, { x = x, y = y, w = w, h = h }
	local b, pad = THEME.borderWidth, GAP * 2 * unit
	for i, line in ipairs(lines) do
		local ly = y + gap + (i - 1) * lineH
		local color = line.color or THEME.text
		if line.lit then
			surface.SetDrawColor(THEME.border)
			surface.DrawRect(x + b, ly, w - b * 2, lineH)
			color = THEME.background
		end
		if line.cast then clickRows[#clickRows + 1] = { y = ly, h = lineH, yes = line.cast.yes, choice = line.cast.choice } end
		draw.SimpleText(line.text, line.font or BODY_FONT, x + pad, ly + lineH / 2, color, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		if line.right then
			draw.SimpleText(line.right, BODY_FONT, x + w - pad, ly + lineH / 2, line.lit and color or THEME.muted,
				TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		end
	end
end

-- The card's last line: what the player cast, else what they may do.
local function Footer(state)
	local cast = state.cast
	if #state.options > 0 then
		if cast ~= Vote.BALLOT_NONE then return "You voted for " .. state.options[cast] .. "." end
		return state.mine and "Press F1 to F" .. #state.options .. ", or hold C and click." or state.quorum .. " votes are needed."
	end
	if cast == Vote.BALLOT_YES then return "You voted YES." end
	if cast == Vote.BALLOT_NO then return "You voted NO." end
	return state.mine and "Press F1 or F2, or hold C and click." or state.quorum .. " votes are needed."
end

WS.HUD:Add("game.notices.votes", WS.HUD_ORDER.NOTICES, function(_, h)
	local state = WS.VoteState
	if not state.running then return end
	local unit = h / 480
	Fonts(unit)
	local left = math.max(0, math.ceil(state.ends - CurTime()))
	local lines = {
		{
			text = state.caller ~= "" and state.caller .. " wants to call a vote" or "Vote",
			color = THEME.muted,
			right = string.format("%d:%02d", math.floor(left / 60), left % 60),
		},
		{
			text = state.question,
			font = TITLE_FONT,
		},
	}
	if #state.options > 0 then
		for i, option in ipairs(state.options) do
			lines[#lines + 1] = {
				text = OPTION_KEYS[i] .. "   " .. option,
				right = tostring(state.counts[i]),
				lit = state.cast == i,
				cast = { yes = false, choice = i },
			}
		end
	else
		lines[#lines + 1] = { text = "F1   Yes", right = tostring(state.yes), lit = state.cast == Vote.BALLOT_YES,
			cast = { yes = true, choice = 0 } }
		lines[#lines + 1] = { text = "F2   No", right = tostring(state.no), lit = state.cast == Vote.BALLOT_NO,
			cast = { yes = false, choice = 0 } }
	end
	lines[#lines + 1] = { text = Footer(state), color = THEME.muted }
	Card(lines, CARD_X * unit, h * CARD_Y_SHARE, CARD_W * unit, unit)
end, WS.Active)
