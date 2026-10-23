-- The gamemode feature's view: TF2's tournament panel in cooler-hud v2.6's
-- look (features.gamemode.tournament lays it out and words it) while the
-- game is not in Gameplay mode: Sandbox mode, the wait for players
-- (ws_gamemode_waiting_have and _need) and the countdown to Gameplay mode
-- (ws_gamemode_transition_end), with each team's name and players, the
-- match's win conditions (the rounds controller's ws_match_timelimit,
-- _winlimit and _maxrounds) and, for a player with the match privilege,
-- where Begin Game is. It hangs under the round timer and its label
-- (ws.tf_hud's TimerPanel), so the wait's count and the countdown's
-- "Prepare" clock stay above it, and goes while a win panel is up.
local Tournament = WS.require("features.gamemode.tournament")
local Hud = WS.require("ws.tf_hud")
local Text = WS.require("features.rounds.text")
local Permissions = system.permissions
local Font, DrawBorder = WS.TFHud.Font, WS.TFHud.DrawBorder
local TAN_LIGHT = WS.TFHud.TAN_LIGHT

-- Between the round timer's panel and this one, 480-tall.
local BELOW_TIMER = 2
local TEAMS = { WS.TEAM_BLUE, WS.TEAM_RED }

local View = {}

local function Facts()
	local players = {}
	for _, t in ipairs(TEAMS) do players[t] = team.NumPlayers(t) end
	return {
		now = CurTime(),
		transitionEnd = GetGlobal2Float("ws_gamemode_transition_end", 0),
		waitingHave = GetGlobal2Int("ws_gamemode_waiting_have", 0),
		waitingNeed = GetGlobal2Int("ws_gamemode_waiting_need", 0),
		halted = WS.GameplayStopped(),
		winPanel = not Text.ShowsTeamBar(WS.State()),
		players = players,
		names = WS.TeamName,
		limits = {
			timelimit = GetGlobal2Int("ws_match_timelimit", 0),
			winlimit = GetGlobal2Int("ws_match_winlimit", 0),
			maxrounds = GetGlobal2Int("ws_match_maxrounds", 0),
		},
		mayBegin = WS.Can(LocalPlayer(), Permissions.MATCH) == true,
	}
end

function View:Draw(w, h)
	local panel = Tournament.Panel(Facts())
	if panel == nil then return end
	local unit = Hud.Unit(h)
	-- drawn only while the rounds run (WS.Active), so their view is loaded;
	-- a game begun on a map without rounds loads this view before them
	local timer = Hud.TimerPanel(w / 2, WS.Feature("rounds"):TimerTop(h), unit)
	local timerBottom = math.max(timer.bg.y + timer.bg.h, timer.label.box.y + timer.label.box.h)
	local layout = Tournament.Layout(w / 2, timerBottom + BELOW_TIMER * unit, unit)
	DrawBorder(Tournament.BG_IMAGE, layout.bg, unit, Tournament.BG_SRC_CORNER, Tournament.BG_DRAW_CORNER)
	draw.SimpleText(panel.state, Font(Hud.FONT_SECONDARY, Tournament.STATE_FONT_TALL, unit), layout.state.x, layout.state.y,
		TAN_LIGHT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	local nameFont = Font(Hud.FONT_SECONDARY, Tournament.NAME_FONT_TALL, unit)
	local stateFont = Font(Hud.FONT_BUILD, Tournament.TEAM_STATE_FONT_TALL, unit)
	for _, t in ipairs(TEAMS) do
		local blue = t == WS.TEAM_BLUE
		DrawBorder(Tournament.STRIP_IMAGES[t], layout.strips[t], unit, Tournament.STRIP_SRC_CORNER, Tournament.STRIP_DRAW_CORNER)
		-- BLU's name at the strip's outer end, its state inward; RED's mirrored
		local name, state = layout.names[t], layout.states[t]
		draw.SimpleText(panel.teams[t].name, nameFont, name.x, name.y, TAN_LIGHT,
			blue and TEXT_ALIGN_LEFT or TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		draw.SimpleText(panel.teams[t].state, stateFont, state.x, state.y, TAN_LIGHT,
			blue and TEXT_ALIGN_RIGHT or TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end
	draw.SimpleText(panel.conditions, Font(Hud.FONT_SECONDARY, Tournament.CONDITION_FONT_TALL, unit), layout.conditions.x,
		layout.conditions.y, TAN_LIGHT, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
	if panel.instructions then
		local font = Font(Hud.FONT_BUILD, Tournament.INSTRUCTIONS_FONT_TALL, unit)
		draw.SimpleText(panel.instructions, font, layout.shadow.x, layout.shadow.y, color_black, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		draw.SimpleText(panel.instructions, font, layout.instructions.x, layout.instructions.y, TAN_LIGHT,
			TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
end

WS.HUD:Add("game.match.tournament", WS.HUD_ORDER.ROUND, function(w, h) View:Draw(w, h) end, WS.Active)

return View
