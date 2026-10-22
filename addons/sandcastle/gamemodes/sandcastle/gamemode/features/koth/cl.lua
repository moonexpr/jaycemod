-- The koth feature's view, drawn from what the koth controller networks
-- (ws_koth_clock_<team>_*):
--   - the two team clocks under the team scores (CTFHudKothTimeStatus), as
--     TF2's time panels (ws.tf_hud): BLU's left and RED's right on their
--     team's backgrounds, the running one bright and the paused one dimmed,
--     OVERTIME on the strip under them while the round is in overtime; they
--     replace the round timer, which the rounds view hides in koth;
--   - each running clock's countdown, "Mission ends in 60 seconds"... "1", as
--     every TF2 client speaks any timer in koth (CTeamRoundTimer::ClientThink
--     and SendTimeWarning's IsInKothMode). The clocks have no setup, so they
--     never play the siren.
-- The point's unlock countdown and its lines are the capture view's; the
-- overtime line is the rounds view's.
WS.Feature("rounds")
local Timer = WS.require("games.gameplay.rounds.timer")
local Hud = WS.require("ws.tf_hud")
local Font, DrawImage, Shadowed = WS.TFHud.Font, WS.TFHud.DrawImage, WS.TFHud.Shadowed

local RED, BLUE = WS.TEAM_RED, WS.TEAM_BLUE
local GAME_TEAMS = { RED, BLUE }

-- Between the two clocks, in a 480-tall screen's units.
local CLOCK_GAP = 4
local DIM_ALPHA = 110
-- BLU's clock sits left of the centre, RED's right.
local SIDE = {
	[BLUE] = -1,
	[RED] = 1,
}

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
		autoCountdown = GetGlobal2Bool(Key(t, "auto_countdown"), true),
		serial = GetGlobal2Int(Key(t, "serial"), 0),
	}
end

local function Format(seconds)
	seconds = math.ceil(seconds)
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function ClockPanel(t, w, top, unit)
	return Hud.TimerPanel(w / 2 + SIDE[t] * (Hud.TIMER_W + CLOCK_GAP) / 2 * unit, top, unit)
end

local function DrawClock(t, c, panel, unit)
	local alpha = c.paused and DIM_ALPHA or 255
	DrawImage(Hud.TimerBackground(t), panel.bg, alpha)
	local tan = WS.TFHud.TAN_LIGHT
	Shadowed(Format(c.left), Font(Hud.FONT_BUILD, Hud.TIMER_FONT_TALL, unit), panel.value.x, panel.value.y, TEXT_ALIGN_CENTER,
		Color(tan.r, tan.g, tan.b, alpha))
end

-- Sandbox mode shows no clocks, as it shows no round timer; nor does a win
-- panel, which has the scores and the game over timer.
function View:Paint(w, h)
	if WS.GameplayStopped() then return end
	local unit = Hud.Unit(h)
	local top = Hud.TimerTop(math.floor(h * timerY:GetFloat()), unit)
	local shown = {}
	for _, t in ipairs(GAME_TEAMS) do
		local c = Clock(t)
		if c.shown then shown[#shown + 1] = { team = t, clock = c, panel = ClockPanel(t, w, top, unit) } end
	end
	if #shown == 0 then return end
	-- the overtime strip spans both clocks, under them
	local overtime = GetGlobal2Bool("ws_round_overtime", false)
	if overtime then
		local first, last = shown[1].panel.label.strip, shown[#shown].panel.label.strip
		local left, right = math.min(first.x, last.x), math.max(first.x + first.w, last.x + last.w)
		DrawImage(Hud.TIMER_STRIP, { x = left, y = first.y, w = right - left, h = first.h })
	end
	for _, s in ipairs(shown) do DrawClock(s.team, s.clock, s.panel, unit) end
	if overtime then
		local label = shown[1].panel.label
		Shadowed("OVERTIME", Font(Hud.FONT_SMALL, Hud.TIMER_LABEL_FONT_TALL, unit), w / 2, label.y, TEXT_ALIGN_CENTER)
	end
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
