-- Arena: the arena mode of foundation.rounds (TF_GAMETYPE_ARENA, the
-- IsInArenaMode branches of teamplayroundbased_gamerules.cpp and
-- tf_gamerules.cpp) and the tf_logic_arena logic (CArenaLogic). A
-- tf_logic_arena chooses it.
--
-- The pre-round lasts tf_arena_preround_time; then the round is fought in
-- STALEMATE, with no respawns, timed by tf_arena_round_time (0, untimed). It
-- starts with OnArenaRoundStart and sets the cap-enable time:
-- tf_arena_override_cap_enable_time when above 0, else the map's
-- CapEnableDelay. Until then no point may be captured (TeamMayCapturePoint);
-- the points' own locks are the map's. OnCapEnabled fires once as that time
-- passes. A team wins by killing the other or by capturing the point.
local setmetatable = setmetatable
local ControlPoints = require("foundation.rounds.control_points")
local State = require("foundation.rounds.state")
module(...)

-- The FGD's CapEnableDelay default.
CAP_ENABLE_DELAY_DEFAULT = 0

-- tf_arena_preround_time's bounds (teamplayroundbased_gamerules.cpp).
PREROUND_MIN, PREROUND_MAX = 5, 15

-- SetupOnStalemateStart's line as the arena round starts.
ROUND_START_LINE = "Announcer.AM_RoundStartRandom"
-- CHudArenaCapPointCountdown::OnTick: the seconds before the point opens,
-- spoken, then the cap-enabled line.
COUNTDOWN_LINES = {
	[5] = "Announcer.RoundBegins5Seconds",
	[4] = "Announcer.RoundBegins4Seconds",
	[3] = "Announcer.RoundBegins3Seconds",
	[2] = "Announcer.RoundBegins2Seconds",
	[1] = "Announcer.RoundBegins1Seconds",
}
CAP_ENABLED_LINE = "Announcer.AM_CapEnabledRandom"

-- The mode ---------------------------------------------------------------------------

Mode = ControlPoints.Mode:Extend("arena")
-- Over every other game type: CTFGameRules::Activate makes a map with a
-- tf_logic_arena arena, whatever else it has.
Mode.PRIORITY = 4
-- CTeamplayRoundBasedRules::CreateTimeLimitTimer returns in arena.
Mode.CREATES_TIME_LIMIT_TIMER = false
-- State_Think_PREROUND goes to STALEMATE in arena.
Mode.ROUND_STATE = State.STALEMATE
Mode.STALEMATE_IS_ROUND = true
-- SetWinningTeam skips the auto scramble in arena (tf_arena_max_streak
-- scrambles instead).
Mode.AUTO_SCRAMBLE = false

-- settings.arenaPreroundTime: tf_arena_preround_time.
function Mode:PreroundSeconds(settings)
	return settings.arenaPreroundTime
end

-- settings.arenaRoundTime: tf_arena_round_time.
function Mode:StalemateSeconds(settings)
	return settings.arenaRoundTime
end

-- CTFGameRules::SetupOnStalemateStart: the override when above 0, else the map's.
function CapEnableDelay(override, mapDelay)
	if override > 0 then return override end
	return mapDelay
end

-- The logic ---------------------------------------------------------------------------

local Logic = {}
Logic.__index = Logic

-- kv = { capEnableDelay }, the map's CapEnableDelay or nil for the FGD's.
function New(kv)
	return setmetatable({
		capEnableDelay = kv.capEnableDelay or CAP_ENABLE_DELAY_DEFAULT,
		fired = false,
	}, Logic)
end

-- The round's delay, given tf_arena_override_cap_enable_time.
function Logic:CapEnableDelay(override)
	return CapEnableDelay(override, self.capEnableDelay)
end

-- CArenaLogic::ArenaLogicThink: whether OnCapEnabled fires now. Only in
-- STALEMATE; it fires once as the round's cap-enable time (capEnableAt, nil
-- for none) passes, and a time still to come re-arms it.
function Logic:Think(now, state, capEnableAt)
	if state ~= State.STALEMATE or capEnableAt == nil then return false end
	if capEnableAt > now then
		self.fired = false
		return false
	end
	if self.fired then return false end
	self.fired = true
	return true
end
