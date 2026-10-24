-- The koth feature's view, drawn from what the koth controller networks
-- (ws_koth_clock_<team>_*):
--   - the two team clocks under the team scores (CTFHudKothTimeStatus), as
--     cooler-hud's time panels (ws.tf_hud): BLU's left and RED's right on
--     their team's outlined backgrounds, each with its progress pie, the
--     active frame (ActiveTimerBG) on the running one, OVERTIME in a box
--     under both while the round is in overtime; they replace the round
--     timer, which the rounds view hides in koth;
--   - each running clock's countdown, "Mission ends in 60 seconds"... "1", as
--     every TF2 client speaks any timer in koth (CTeamRoundTimer::ClientThink
--     and SendTimeWarning's IsInKothMode). The clocks have no setup, so they
--     never play the siren.
-- The point's unlock countdown and its lines are the capture view's; the
-- overtime line is the rounds view's.
WS.Feature("rounds")
local Timer = WS.require("games.gameplay.rounds.timer")
local Hud = WS.require("ws.tf_hud")
local TFHud = WS.TFHud
local Font, DrawImage, DrawPanel, Shadowed = TFHud.Font, TFHud.DrawImage, TFHud.DrawPanel, TFHud.Shadowed

local RED, BLUE = WS.TEAM_RED, WS.TEAM_BLUE
local GAME_TEAMS = { BLUE, RED }

-- The rounds view's convar: where the team scores start, the timer row
-- under them.
local timerY = GetConVar("cl_hud_round_timer_y")

local View = {
	clocks = {
		[RED] = {
			serial = nil,
			armed = {},
		},
		[BLUE] = {
			serial = nil,
			armed = {},
		},
	},
}

local function Key(t, field)
	return "ws_koth_clock_" .. t .. "_" .. field
end

-- A clock as published: shown, paused, seconds left, auto countdown, serial.
local function Clock(t)
	local paused = GetGlobal2Bool(Key(t, "paused"), true)
	local left = paused and GetGlobal2Float(Key(t, "time_left"), 0) or GetGlobal2Float(Key(t, "end_time"), 0) - CurTime()
	return {
		shown = GetGlobal2Bool(Key(t, "shown"), false),
		paused = paused,
		left = math.max(0, left),
		fullLength = GetGlobal2Float(Key(t, "max_length"), 0),
		autoCountdown = GetGlobal2Bool(Key(t, "auto_countdown"), true),
		serial = GetGlobal2Int(Key(t, "serial"), 0),
	}
end

local function Format(seconds)
	seconds = math.ceil(seconds)
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function DrawClock(t, c, panel, unit)
	TFHud.DrawTimerBackground(panel, t)
	TFHud.DrawPie(panel.pie, Hud.TimerElapsed(c.left, c.fullLength))
	Shadowed(Format(c.left), Font(Hud.FONT_BUILD, Hud.TIMER_FONT_TALL, unit), panel.value.x, panel.value.y, TEXT_ALIGN_CENTER)
end

-- Sandbox mode shows no clocks, as it shows no round timer; nor does a win
-- panel, which has the scores and the game over timer.
function View:Paint(w, h)
	-- the pregame panel has the top of the screen before a game (features/rounds/cl.lua)
	if WS.Feature("rounds"):Pregame() then return end
	local unit = Hud.Unit(h)
	local top = Hud.TimerTop(math.floor(h * timerY:GetFloat()), unit)
	local panels = Hud.KothPanels(w / 2, top, unit)
	local shown = {}
	for _, t in ipairs(GAME_TEAMS) do
		local c = Clock(t)
		if c.shown then shown[#shown + 1] = { team = t, clock = c, panel = panels[t] } end
	end
	if #shown == 0 then return end
	for _, s in ipairs(shown) do
		DrawClock(s.team, s.clock, s.panel, unit)
		if not s.clock.paused then DrawImage(Hud.KOTH_ACTIVE_FRAME, Hud.KothActiveFrame(panels, s.team)) end
	end
	-- OvertimeLabel in one box under both clocks
	if not GetGlobal2Bool("ws_round_overtime", false) then return end
	local first, last = shown[1].panel.label, shown[#shown].panel.label
	local box = { x = first.box.x, y = first.box.y, w = last.box.x + last.box.w - first.box.x, h = first.box.h }
	DrawPanel(Hud.TIMER_LABEL_BORDER, box, unit)
	Shadowed("OVERTIME", Font(Hud.FONT_BUILD, Hud.TIMER_LABEL_FONT_TALL, unit), box.x + box.w / 2, first.y, TEXT_ALIGN_CENTER)
end

local function Play(name)
	local ply = LocalPlayer()
	if IsValid(ply) then ply:EmitSound(name) end
end

-- CTeamRoundTimer::ClientThink for one clock: its warnings are re-armed when
-- its length changes (the serial), and spoken while it runs.
function View:CountdownThink(t)
	local c = Clock(t)
	local state = self.clocks[t]
	if not c.shown then return end
	if c.serial ~= state.serial then
		state.serial = c.serial
		state.armed = Timer.ArmClientWarnings(c.left, false) -- koth's clocks run no setup
	end
	if c.paused then return end
	local warning = Timer.NextClientWarning(state.armed, c.left, false)
	if not warning then return end
	state.armed[warning] = false
	local speaks = Timer.Speaks({
		paused = c.paused,
		autoCountdown = c.autoCountdown,
		halted = WS.GameplayStopped(),
		isHud = false,
		koth = true,
	})
	if speaks then Play(Timer.WarningSound(warning, false)) end
end

-- game.match.team_clocks: the win screens hide them (features/rounds/cl.lua).
WS.HUD:Add("game.match.team_clocks", WS.HUD_ORDER.OBJECTIVES, function(w, h)
	View:Paint(w, h)
end, WS.Active)

hook.Add("Think", "ws_koth_announcer", function()
	if not WS.Active() then return end
	for _, t in ipairs(GAME_TEAMS) do View:CountdownThink(t) end
end)

return View
