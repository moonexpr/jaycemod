-- The koth feature's view, drawn from what the koth controller networks
-- (wetsand_koth_clock_<team>_*):
--   - the two team clocks at the top (CTFHudKothTimeStatus): BLU's left and
--     RED's right in team colours, the running one bright and the paused one
--     dimmed, with OVERTIME under them while the round is in overtime; they
--     replace the round timer, which the rounds view hides in koth;
--   - each running clock's countdown, "Mission ends in 60 seconds"... "1", as
--     every TF2 client speaks any timer in koth (CTeamRoundTimer::ClientThink
--     and SendTimeWarning's IsInKothMode). The clocks have no setup, so they
--     never play the siren.
-- The point's unlock countdown and its lines are the capture view's; the
-- overtime line is the rounds view's.
WETSAND.Feature("rounds")
local Timer = WETSAND.require("foundation.rounds.timer")

local RED, BLUE = WETSAND.TEAM_RED, WETSAND.TEAM_BLUE
local GAME_TEAMS = { RED, BLUE }

local CLOCK_WIDTH, CLOCK_HEIGHT, CLOCK_GAP = 120, 46, 8
local LABEL_TOP = CLOCK_HEIGHT + 4
local CORNER = 6
local DIM_ALPHA = 90
local BRIGHT_ALPHA = 230
local PANEL_BG = Color(0, 0, 0, 170)
local GOLD = Color(255, 210, 90)
-- BLU's clock sits left of the centre, RED's right.
local SIDE = {
	[BLUE] = -1,
	[RED] = 1,
}

-- The rounds view's convar: where the timer row starts.
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
	return "wetsand_koth_clock_" .. t .. "_" .. field
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

local function DrawClock(t, c, w, top)
	local x = w / 2 + (SIDE[t] > 0 and CLOCK_GAP / 2 or -CLOCK_GAP / 2 - CLOCK_WIDTH)
	local team = WETSAND.TeamColor[t]
	local alpha = c.paused and DIM_ALPHA or BRIGHT_ALPHA
	draw.RoundedBox(CORNER, x, top, CLOCK_WIDTH, CLOCK_HEIGHT, PANEL_BG)
	draw.RoundedBox(CORNER, x + 2, top + 2, CLOCK_WIDTH - 4, CLOCK_HEIGHT - 4, Color(team.r, team.g, team.b, alpha / 2))
	draw.SimpleText(Format(c.left), "Sandcastle.Hud.Timer", x + CLOCK_WIDTH / 2, top + 4,
		Color(255, 255, 255, alpha), TEXT_ALIGN_CENTER)
end

-- Sandbox mode shows no clocks, as it shows no round timer.
function View:Paint(w, h)
	if WETSAND.GameplayStopped() then return end
	local top = math.floor(h * timerY:GetFloat())
	local any = false
	for _, t in ipairs(GAME_TEAMS) do
		local c = Clock(t)
		if c.shown then
			DrawClock(t, c, w, top)
			any = true
		end
	end
	if any and GetGlobal2Bool("wetsand_round_overtime", false) then
		draw.SimpleText("OVERTIME", "Sandcastle.Hud.Label", w / 2, top + LABEL_TOP, GOLD, TEXT_ALIGN_CENTER)
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
		halted = WETSAND.GameplayStopped(),
		isHud = false,
		koth = true,
	})
	if speaks then Play(Timer.WarningSound(warning, false)) end
end

hook.Add("SandcastleHUDPaint", "wetsand_koth", function(w, h)
	View:Paint(w, h)
end)

hook.Add("Think", "wetsand_koth_announcer", function()
	if not WETSAND.Active() then return end
	for _, t in ipairs(GAME_TEAMS) do View:CountdownThink(t) end
end)

return View
