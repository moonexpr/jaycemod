-- The gamemode feature's view: TF2's tournament panel in cooler-hud v2.6's
-- look (features.gamemode.tournament lays it out and words it) while the
-- game is not in Gameplay mode: Sandbox mode, the wait for players
-- (ws_gamemode_waiting_have and _need) and the countdown to Gameplay mode
-- (ws_gamemode_transition_end), with each team's name and players or, while
-- the game waits, whether it is ready (ws_ready_team_<team>), the match's
-- win conditions (the rounds controller's ws_match_timelimit, _winlimit and
-- _maxrounds) and, on TF2's help strip, the key for what the player may do.
-- In MvM, its ready-up instead: a panel per human defender, ready or not
-- (NW2 ws_ready), and TF2's pulsing instructions line. It takes the top of
-- the screen, the team scores' slot, the scores and the round timer giving
-- way to it (features/rounds/cl.lua), and goes while a win panel is up.
local Tournament = WS.require("features.gamemode.tournament")
local Hud = WS.require("ws.tf_hud")
local Text = WS.require("features.rounds.text")
local Permissions = system.permissions
local Font, DrawBorder = WS.TFHud.Font, WS.TFHud.DrawBorder
local TAN_LIGHT = WS.TFHud.TAN_LIGHT
local RED_SOLID = Color(192, 28, 0) -- clientscheme.res's RedSolid, HudReadyPulse's red

local TEAMS = { WS.TEAM_BLUE, WS.TEAM_RED }

local View = {}

-- The key bound to a command, as TF2 names F4 in "F4 = Toggle Ready"; nil unbound.
local function Key(...)
	for _, command in ipairs({ ... }) do
		local key = input.LookupBinding(command)
		if key then return string.upper(key) end
	end
	return nil
end

local function ReadyKey()
	return Key("player_ready_toggle", "gm_showspare2")
end

local function TeamKey()
	return Key("gm_showteam", "changeteam")
end

local function Common()
	return {
		now = CurTime(),
		transitionEnd = GetGlobal2Float("ws_gamemode_transition_end", 0),
		waitingHave = GetGlobal2Int("ws_gamemode_waiting_have", 0),
		waitingNeed = GetGlobal2Int("ws_gamemode_waiting_need", 0),
		halted = WS.GameplayStopped(),
		winPanel = not Text.ShowsTeamBar(WS.State()),
		mayBegin = WS.Can(LocalPlayer(), Permissions.MATCH) == true,
		readyKey = ReadyKey(),
		teamKey = TeamKey(),
	}
end

local function Facts()
	local q = Common()
	q.players, q.humans, q.teamReady = {}, {}, {}
	for _, t in ipairs(TEAMS) do
		q.players[t] = team.NumPlayers(t)
		q.humans[t] = 0
		q.teamReady[t] = GetGlobal2Bool("ws_ready_team_" .. t, false)
	end
	for _, ply in ipairs(player.GetHumans()) do
		local t = WS.TeamOf(ply)
		if q.humans[t] then q.humans[t] = q.humans[t] + 1 end
	end
	q.names = WS.TeamName
	q.limits = {
		timelimit = GetGlobal2Int("ws_match_timelimit", 0),
		winlimit = GetGlobal2Int("ws_match_winlimit", 0),
		maxrounds = GetGlobal2Int("ws_match_maxrounds", 0),
	}
	q.localTeam = WS.TeamOf(LocalPlayer())
	return q
end

-- MvM's defenders: RED (features.mvm's player requirement).
local DEFENDERS = WS.TEAM_RED

local function MvMFacts()
	local q = Common()
	local me = LocalPlayer()
	q.defenders, q.defenderPlayers = {}, {}
	for _, ply in ipairs(player.GetHumans()) do
		if WS.TeamOf(ply) == DEFENDERS then
			q.defenders[#q.defenders + 1] = { name = ply:Nick(), ready = ply:GetNW2Bool("ws_ready", false) }
			q.defenderPlayers[#q.defenderPlayers + 1] = ply
		end
	end
	q.localDefender = WS.TeamOf(me) == DEFENDERS
	q.localReady = me:GetNW2Bool("ws_ready", false)
	return q
end

-- Drawn only while the rounds run (WS.Active), so their view is loaded; a
-- game begun on a map without rounds loads this view before them.
local function Top(h)
	return WS.Feature("rounds"):ScoresTop(h)
end

function View:DrawTournament(panel, w, h)
	local unit = Hud.Unit(h)
	local layout = Tournament.Layout(w / 2, Top(h), unit)
	if panel.instructions then
		DrawBorder(Tournament.BG_IMAGE, layout.help, unit, Tournament.BG_SRC_CORNER, Tournament.BG_DRAW_CORNER)
	end
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
		draw.SimpleText(panel.instructions, Font(Hud.FONT_SECONDARY, Tournament.INSTRUCTIONS_FONT_TALL, unit),
			layout.instructions.x, layout.instructions.y, TAN_LIGHT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
end

-- The avatars, vgui panels painted by hand inside the HUD's paint.
local avatars = {}

local function Avatar(i, ply, box)
	local a = avatars[i]
	if not IsValid(a) then
		a = vgui.Create("AvatarImage")
		a:SetPaintedManually(true)
		avatars[i] = a
	end
	if a.player ~= ply then
		a:SetPlayer(ply, 32)
		a.player = ply
	end
	a:SetPos(box.x, box.y)
	a:SetSize(box.w, box.h)
	a:PaintManual()
end

local CHECK = Material(Tournament.MVM_CHECK_IMAGE)
local READY_COLOR, NOT_READY_COLOR = Color(unpack(Tournament.MVM_COLOR_READY)), Color(unpack(Tournament.MVM_COLOR_NOT_READY))

function View:DrawMvM(panel, players, w, h)
	local unit = Hud.Unit(h)
	local layout = Tournament.MvMLayout(w / 2, Top(h), unit, #panel.players)
	local nameFont = Font(Tournament.MVM_NAME_FONT, Tournament.MVM_NAME_FONT_TALL, unit)
	for i, p in ipairs(panel.players) do
		local at = layout.players[i]
		draw.RoundedBox(0, at.bg.x, at.bg.y, at.bg.w, at.bg.h, p.ready and READY_COLOR or NOT_READY_COLOR)
		surface.SetDrawColor(0, 0, 0, 255)
		surface.DrawRect(at.avatar.x, at.avatar.y, at.avatar.w, at.avatar.h)
		Avatar(i, players[i], at.avatar)
		DrawBorder(Tournament.MVM_READY_BG_IMAGE, at.readyBg, unit, Tournament.MVM_READY_BG_SRC_CORNER, Tournament.MVM_READY_BG_DRAW_CORNER)
		if p.ready then
			surface.SetDrawColor(255, 255, 255, 255)
			surface.SetMaterial(CHECK)
			surface.DrawTexturedRect(at.check.x, at.check.y, at.check.w, at.check.h)
		end
		draw.SimpleText(p.name, nameFont, at.name.x, at.name.y, TAN_LIGHT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	local font = Font(Hud.FONT_BUILD, Tournament.MVM_INSTRUCTIONS_FONT_TALL, unit)
	local color = TAN_LIGHT
	if panel.pulse then
		local red = Tournament.PulseRedness(RealTime())
		color = Color(Lerp(red, TAN_LIGHT.r, RED_SOLID.r), Lerp(red, TAN_LIGHT.g, RED_SOLID.g), Lerp(red, TAN_LIGHT.b, RED_SOLID.b))
	end
	draw.SimpleText(panel.instructions, font, layout.shadow.x, layout.shadow.y, color_black, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	draw.SimpleText(panel.instructions, font, layout.instructions.x, layout.instructions.y, color, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

function View:Draw(w, h)
	if GetGlobal2Bool("ws_mvm", false) then
		local q = MvMFacts()
		local panel = Tournament.MvMPanel(q)
		if panel then self:DrawMvM(panel, q.defenderPlayers, w, h) end
		return
	end
	local panel = Tournament.Panel(Facts())
	if panel then self:DrawTournament(panel, w, h) end
end

WS.HUD:Add("game.match.tournament", WS.HUD_ORDER.ROUND, function(w, h) View:Draw(w, h) end, WS.Active)

return View
