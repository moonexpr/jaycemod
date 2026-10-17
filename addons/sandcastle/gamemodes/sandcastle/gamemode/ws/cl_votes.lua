-- The running vote on clients (ws/sh_votes.lua): its card on the HUD, and
-- F1 (yes) and F2 (no) while the player may vote, as in TF2; on a vote of
-- choices (the next-map vote), F1 to F4 pick its options in order. A vote's
-- result stays on the card for RESULT_SECONDS; a refused request is a
-- notice. The Server tab (ws/cl_menu_server.lua) reads WS.VoteState and
-- WS.VoteMaps and hears WSVoteChanged.
local E = WS.Events
local THEME = WS.UI.THEME

local RESULT_SECONDS = 5
local REFUSED_SECONDS = 4
local REFUSED_SOUND = "buttons/button10.wav"

local CARD_X, CARD_Y_SHARE, CARD_W = 16, 0.3, 360
local LINE_H, GAP = 22, 6

WS.VoteState = WS.VoteState or { running = false }
WS.VoteMaps = WS.VoteMaps or {}
local result -- { passed, text, untilTime }

E.Listen("vote_state", "ws_votes", function(fields)
	WS.VoteState = fields
	hook.Run("WSVoteChanged")
end)

E.Listen("vote_maps", "ws_votes", function(fields)
	WS.VoteMaps = fields.maps
	hook.Run("WSVoteChanged")
end)

E.Listen("vote_ended", "ws_votes", function(fields)
	result = {
		passed = fields.passed,
		text = fields.text,
		untilTime = CurTime() + RESULT_SECONDS,
	}
end)

E.Listen("vote_refused", "ws_votes", function(fields)
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

hook.Add("PlayerBindPress", "ws_votes", function(_, bind, pressed)
	if not pressed then return end
	local state = WS.VoteState
	if not (state.running and state.mine) then return end
	if #state.options > 0 then
		local choice = OPTION_BINDS[bind]
		if choice == nil or choice > #state.options then return end
		E.Request("vote_cast", { yes = false, choice = choice })
		return true
	end
	local yes = CASTS[bind]
	if yes == nil then return end
	E.Request("vote_cast", { yes = yes, choice = 0 })
	return true
end)

local function Card(lines, y)
	local h = #lines * LINE_H + GAP * 2
	surface.SetDrawColor(THEME.border)
	surface.DrawRect(CARD_X, y, CARD_W, h)
	local b = THEME.borderWidth
	surface.SetDrawColor(THEME.background)
	surface.DrawRect(CARD_X + b, y + b, CARD_W - b * 2, h - b * 2)
	for i, line in ipairs(lines) do
		local ly = y + GAP + (i - 1) * LINE_H
		draw.SimpleText(line.text, line.font or THEME.bodyFont, CARD_X + THEME.padding, ly, line.color or THEME.text)
		if line.right then
			draw.SimpleText(line.right, THEME.bodyFont, CARD_X + CARD_W - THEME.padding, ly, THEME.muted, TEXT_ALIGN_RIGHT)
		end
	end
end

hook.Add("SandcastleHUDPaint", "ws_votes", function(_, h)
	local y = h * CARD_Y_SHARE
	local state = WS.VoteState
	if state.running then
		local left = math.max(0, math.ceil(state.ends - CurTime()))
		local lines = {
			{
				text = state.caller ~= "" and state.caller .. " wants to call a vote" or "Vote",
				color = THEME.muted,
				right = string.format("%d:%02d", math.floor(left / 60), left % 60),
			},
			{
				text = state.question,
				font = THEME.titleFont,
			},
		}
		if #state.options > 0 then
			for i, option in ipairs(state.options) do
				lines[#lines + 1] = {
					text = OPTION_KEYS[i] .. "   " .. option,
					right = tostring(state.counts[i]),
				}
			end
			lines[#lines + 1] = {
				text = state.mine and "Press F1 to F" .. #state.options .. " to choose." or state.quorum .. " votes are needed.",
				color = THEME.muted,
			}
		else
			lines[#lines + 1] = { text = "Yes: F1   " .. state.yes .. "        No: F2   " .. state.no }
			lines[#lines + 1] = {
				text = state.mine and "Press F1 to vote YES." or state.quorum .. " votes are needed.",
				color = THEME.muted,
			}
		end
		Card(lines, y)
		return
	end
	if result and CurTime() < result.untilTime then
		Card({
			{
				text = result.passed and "Vote Passed" or "Vote Failed",
				color = THEME.muted,
			},
			{
				text = result.text,
				font = THEME.titleFont,
			},
		}, y)
	end
end)
