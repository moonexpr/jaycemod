-- King of the Hill: the koth mode of games.gameplay.rounds (CTFGameRules's
-- IsInKothMode branches) and the tf_logic_koth logic (CKothLogic,
-- tf_gamerules.cpp). A tf_logic_koth chooses it.
--
-- Each team has a clock, a team_round_timer named zz_<team>_koth_timer
-- that maps address by name. They are made paused at every RoundSpawn; at
-- RoundActivate every point is locked for unlock_point seconds. Capturing
-- the hill runs the capper's clock and pauses the other's (the map's
-- OnCapTeam -> tf_gamerules.Set<Team>KothClockActive). A team owning the
-- hill wins when its clock reads zero and the timer may expire, so an
-- enemy on the point holds it at zero in overtime.
local Rounds = require("games.gameplay.rounds")
local ControlPoints = require("features.rounds.control_points")
local Teams = require("games.gameplay.teams")
local ipairs, setmetatable = ipairs, setmetatable
module(...)

local RED, BLUE = Teams.RED, Teams.BLUE

-- The CKothLogic constructor's defaults (the FGD's too).
TIMER_LENGTH_DEFAULT = 180
UNLOCK_POINT_DEFAULT = 30

-- CKothLogic::InputRoundSpawn's names, which 7 maps AddOutput or send
-- inputs to.
CLOCK_NAME = {
	[BLUE] = "zz_blue_koth_timer",
	[RED] = "zz_red_koth_timer",
}
-- InputRoundSpawn creates BLU's clock, then RED's.
local CLOCK_ORDER = { BLUE, RED }

-- CTFGameRules::PlaySpecialCapSounds: in koth every cap plays this to each team.
POINT_CAPTURED = "Hud.PointCaptured"

-- The team_round_timer inputs doing what CKothLogic's clock inputs do:
-- SetTimeRemaining and AddTimerSeconds.
TIMER_SET = "settime"
TIMER_ADD = "addtime"

-- tf_logic_koth's clock inputs (lower-cased) -> the team's clock and the
-- timer input.
CLOCK_INPUTS = {
	setredtimer = {
		team = RED,
		timerInput = TIMER_SET,
	},
	setbluetimer = {
		team = BLUE,
		timerInput = TIMER_SET,
	},
	addredtimer = {
		team = RED,
		timerInput = TIMER_ADD,
	},
	addbluetimer = {
		team = BLUE,
		timerInput = TIMER_ADD,
	},
}

local ENEMY = {
	[RED] = BLUE,
	[BLUE] = RED,
}

-- The mode ---------------------------------------------------------------------------

Mode = ControlPoints.Mode:Extend("koth")
Mode.PRIORITY = 3
Mode.HUD = Rounds.HUD_KOTH
-- CTeamplayRoundBasedRules::CreateTimeLimitTimer returns in koth.
Mode.CREATES_TIME_LIMIT_TIMER = false
-- CTeamRoundTimer::AddTimerSeconds announces nothing in koth.
Mode.ANNOUNCES_TIME_ADDED = false

-- CTeamControlPointMaster::CheckWinConditions (team_control_point_master.cpp,
-- and team_control_point_round.cpp's): the owner of every point wins only at
-- its clock's zero and while TimerMayExpire holds. Without a clock, at once.
function Mode:MayWinByPoints(team, q)
	return q.clockRemaining == nil or (q.clockRemaining <= 0 and q.timerMayExpire)
end

-- PlaySpecialCapSounds: in koth every cap, winning or not and whatever the
-- score style, plays Hud.PointCaptured, then Success to the cappers and
-- Failure to the other game teams, from FIRST_GAME_TEAM up.
function Mode:CapSounds(capTeam, q)
	local lines = {}
	for _, team in ipairs({ RED, BLUE }) do
		lines[#lines + 1] = {
			team = team,
			sound = POINT_CAPTURED,
		}
		lines[#lines + 1] = {
			team = team,
			sound = team == capTeam and ControlPoints.SUCCESS or ControlPoints.FAILURE,
		}
	end
	return lines
end

-- CTFGameRulesProxy::InputSet<Team>KothClockActive: the team's clock
-- resumes and the enemy's pauses. Returns (resume, pause).
function ClockActive(team)
	return team, ENEMY[team]
end

-- The logic ---------------------------------------------------------------------------

local Logic = {}
Logic.__index = Logic

-- kv = { timerLength, unlockPoint }, the map's timer_length and
-- unlock_point; either absent takes CKothLogic's default.
function New(kv)
	return setmetatable({
		timerLength = kv.timerLength or TIMER_LENGTH_DEFAULT,
		unlockPoint = kv.unlockPoint or UNLOCK_POINT_DEFAULT,
	}, Logic)
end

-- InputRoundSpawn: the clocks to make, in order, each set to timer_length
-- and paused: { { team, name, length }... }.
function Logic:Clocks()
	local clocks = {}
	for _, team in ipairs(CLOCK_ORDER) do
		clocks[#clocks + 1] = {
			team = team,
			name = CLOCK_NAME[team],
			length = self.timerLength,
		}
	end
	return clocks
end

-- InputRoundActivate, for every point: SetLocked with unlock_point
-- (CTeamControlPoint::InputSetLocked locks for a value > 0), then
-- SetUnlockTime when it is positive. { locked, unlockTime or nil }.
function Logic:PointLock()
	local timed = self.unlockPoint > 0
	return {
		locked = timed,
		unlockTime = timed and self.unlockPoint or nil,
	}
end
