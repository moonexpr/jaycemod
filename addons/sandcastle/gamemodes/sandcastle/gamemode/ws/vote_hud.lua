-- The vote panels as cooler-hud v2.6 lays them out (resource/ui/votehud.res,
-- CHudVote full-screen at 0,0 640x480), in TF2's proportional units of a
-- 480-tall screen, filled as CHudVote fills them (hud_vote.cpp): VoteActive
-- with the header (#GameUI_vote_header: who called it), the issue, a row an
-- option (LabelOption1..5; the yes/no instructions, or "F1. <option>" on a
-- vote of choices), the player's cast lit behind its row
-- (Option<N>Background_Selected), and on a yes/no vote the count line and
-- the vote bar with each side's count; VotePassed and VoteFailed for the
-- result. The game's vote state is ws/sh_votes.lua's game_vote_state.
local ceil, floor, format, ipairs, max, min, tostring = math.ceil, math.floor, string.format, ipairs, math.max, math.min, tostring
local Vote = require("games.gameplay.vote")
module(...)

-- VoteActive: 8,150 150x144, border TFFatLineBorderOpaque.
PANEL_X, PANEL_Y, PANEL_W, ACTIVE_TALL = 8, 150, 150, 144
PANEL_IMAGE = "hud/color_panel_brown_opaque"
-- Header 10,5 130x20 and Issue 10,22 120x40, both north-west.
HEADER_X, HEADER_Y, HEADER_W = 10, 5, 130
ISSUE_X, ISSUE_Y, ISSUE_W = 10, 22, 120
-- Divider 10,50 and Divider2 10,100, 130x1. CHudVote hides "Divider1" and
-- Divider2 on a vote of choices; no control is named Divider1, so Divider
-- always shows and Divider2 only on a yes/no vote.
DIVIDER_X, DIVIDER_Y, DIVIDER2_Y, DIVIDER_W = 10, 50, 100, 130
-- LabelOption1 10,57 130x16, each next 16 down (LabelOption5 at 121); the
-- panel's foot is BOTTOM_PAD under the fifth.
OPTION_X, OPTION_Y, OPTION_W, OPTION_TALL = 10, 57, 130, 16
local OPTION_ROWS = 5
local BOTTOM_PAD = ACTIVE_TALL - (OPTION_Y + OPTION_ROWS * OPTION_TALL)
-- A vote of choices' count, right-aligned in its row this far from its end
-- (TF2 shows none; the card showed them before).
OPTION_COUNT_INSET = 3
-- VoteCountLabel 10,100 140x20, north-west.
COUNT_LABEL_X, COUNT_LABEL_Y = 10, 100
COUNT_LABEL = "Vote Count:" -- #GameUI_vote_current_vote_count
-- VoteBar 11,113: box_size 16, box_inset 1, its yes_texture and no_texture.
-- VoteBarPanel::Paint puts the no box 64 pixels after the yes box's end,
-- unscaled; NO_BOX_X is where that lands on a 1080-tall screen, the one
-- cooler-hud's Option2CountLabel (74) lines up with.
BAR_X, BAR_Y, BOX_SIZE, BOX_INSET = 11, 113, 16, 1
NO_BOX_X = 44
YES_ICON, NO_ICON = "vgui/hud/vote_yes", "vgui/hud/vote_no"
-- Option1CountLabel 28,113 and Option2CountLabel 74,113, 16x16, centred.
YES_COUNT_X, NO_COUNT_X, COUNT_Y, COUNT_W = 28, 74, 113, 16
-- Fonts, 480-tall: ScoreboardVerySmall (TF2 Secondary 8) for the header,
-- rows and count line, ScoreboardSmall (TF2 Secondary 10) for the issue,
-- counts and result titles.
SMALL_FONT_TALL, VERY_SMALL_FONT_TALL = 10, 8
-- fgcolor_override: the header and count line grey, the rest white; the
-- dividers' fillcolor; Option<N>Background_Selected's fillcolor.
GREY = { r = 128, g = 128, b = 128, a = 255 }
SELECTED = { r = 88, g = 119, b = 140, a = 180 }
-- VoteBarPanel::Paint's boxes: a grey edge round a black middle.
BOX_EDGE = { r = 128, g = 128, b = 128, a = 128 }

-- VotePassed, VoteFailed: 8,150 150x67; the icon 10,10 17x17, the title
-- 32,10 98x17 west, the result 10,29 130x40 north-west.
RESULT_TALL = 67
RESULT_ICON_X, RESULT_ICON_Y, RESULT_ICON_SIZE = 10, 10, 17
RESULT_TITLE_X, RESULT_TITLE_Y, RESULT_TITLE_TALL = 32, 10, 17
RESULT_TEXT_X, RESULT_TEXT_Y, RESULT_TEXT_W = 10, 29, 130
-- FailedTitle's fgcolor_override.
FAILED = { r = 200, g = 30, b = 30, a = 255 }
-- How long the result shows, the last RESULT_FADE seconds fading.
RESULT_SECONDS, RESULT_FADE = 5, 0.5

-- #GameUI_vote_header's words, and CHudVote's caller for a vote nobody called.
local HEADER = "%s wants to call a vote:"
local SERVER_CALLER = "Server"
-- #GameUI_vote_yes_pc_instruction and _no_; the ballots shown to a player
-- who may not vote.
local YES_INSTRUCTION, NO_INSTRUCTION = "Press F1 to vote YES", "Press F2 to vote NO"
local YES_BALLOT, NO_BALLOT = "Yes", "No"
-- GMod's F1 to F4 binds pick a vote of choices' options in order
-- (ws/cl_votes.lua); CHudVote labels them "F1. ".
local OPTION_KEYS = { "F1", "F2", "F3", "F4" }
local SECONDS_PER_MINUTE = 60

-- votehud.res's LabelOption<i>, from the panel's top.
function RowY(i)
	return OPTION_Y + (i - 1) * OPTION_TALL
end

local function Clock(seconds)
	local s = max(0, ceil(seconds))
	return format("%d:%02d", floor(s / SECONDS_PER_MINUTE), s % SECONDS_PER_MINUTE)
end

local function YesNoRows(state)
	local mine = state.mine
	return {
		{
			text = mine and YES_INSTRUCTION or YES_BALLOT,
			lit = state.cast == Vote.BALLOT_YES,
			cast = mine and { yes = true, choice = 0 } or nil,
		},
		{
			text = mine and NO_INSTRUCTION or NO_BALLOT,
			lit = state.cast == Vote.BALLOT_NO,
			cast = mine and { yes = false, choice = 0 } or nil,
		},
	}
end

local function ChoiceRows(state)
	local rows = {}
	for i, option in ipairs(state.options) do
		local key = state.mine and OPTION_KEYS[i]
		rows[i] = {
			text = key and key .. ". " .. option or option,
			lit = state.cast == i,
			count = tostring(state.counts[i]),
			cast = state.mine and { yes = false, choice = i } or nil,
		}
	end
	return rows
end

-- The running vote's panel: state is game_vote_state's fields, now the
-- time. Returns { header, clock (the time left), issue, rows (each { text,
-- lit (the player's cast), count (a vote of choices'), cast ({ yes, choice
-- }: what clicking it casts; nil for a player who may not vote) }), yesNo
-- (the count line and vote bar show), yes, no (their counts), tall (the
-- panel's height, grown past five rows) }.
function Active(state, now)
	local yesNo = #state.options == 0
	local rows = yesNo and YesNoRows(state) or ChoiceRows(state)
	return {
		header = format(HEADER, state.caller ~= "" and state.caller or SERVER_CALLER),
		clock = Clock(state.ends - now),
		issue = state.question,
		rows = rows,
		yesNo = yesNo,
		yes = tostring(state.yes),
		no = tostring(state.no),
		tall = max(ACTIVE_TALL, OPTION_Y + #rows * OPTION_TALL + BOTTOM_PAD),
	}
end

-- #GameUI_vote_passed and #GameUI_vote_failed's words.
local PASSED_TITLE, FAILED_TITLE = "Vote Passed", "Vote Failed"

-- The result's panel, from game_vote_ended's fields: { icon, title, passed,
-- text (PassedResult or FailedReason) }.
function Result(fields)
	return {
		icon = fields.passed and YES_ICON or NO_ICON,
		title = fields.passed and PASSED_TITLE or FAILED_TITLE,
		passed = fields.passed,
		text = fields.text,
	}
end

-- How opaque the result is at now when it goes at untilTime, 0 to 1.
function ResultAlpha(now, untilTime)
	return max(0, min(1, (untilTime - now) / RESULT_FADE))
end
