-- A tf_logic_cp_timer (CCPTimerLogic, tf_gamerules.cpp): once its team may
-- capture its control point, a countdown of `length` seconds starts; when
-- it has run out and nobody is capping the point, it ends and resets. While
-- its team may capture the point it holds the round timer at zero
-- (CCPTimerLogic::TimerMayExpire). No I/O: the capture controller asks the
-- capture order and the point's area, and fires OnCountdownStart and
-- OnCountdownEnd on the entity.
--
-- New{ length, team }, thought every THINK_INTERVAL:
--   :Think(now, q) -> events, q = { teamMayCapture, capping, roundWon }:
--     capping is whether any team is capping the point, roundWon whether
--     the round is in GR_STATE_TEAM_WIN. Events are { kind = START, endTime }
--     (OnCountdownStart, and the HUD's SetCPTimerTime) and { kind = END }
--     (OnCountdownEnd, and the HUD's timer cleared);
--   :MayExpire(teamMayCapture); :EndTime() (nil when idle); :Team().
-- The controller thinks a timer only while it has found its point
-- (m_hControlPoint).
local setmetatable = setmetatable
local Teams = require("foundation.teams")
module(...)

-- The CCPTimerLogic constructor.
LENGTH_DEFAULT = 60
TEAM_DEFAULT = Teams.BLUE
THINK_INTERVAL = 0.15

START, END = "start", "end"

local PointTimerModel = {}
PointTimerModel.__index = PointTimerModel

-- endTime is CountdownTimer's timestamp, nil when invalidated.
function New(config)
	return setmetatable({
		length = config.length or LENGTH_DEFAULT,
		team = config.team or TEAM_DEFAULT,
		endTime = nil,
	}, PointTimerModel)
end

function PointTimerModel:Team() return self.team end
function PointTimerModel:EndTime() return self.endTime end

-- CCPTimerLogic::TimerMayExpire
function PointTimerModel:MayExpire(teamMayCapture)
	return not teamMayCapture
end

-- CCPTimerLogic::Think. A won round invalidates the countdown and the think
-- carries on, so a team that may still capture starts it again. The
-- 15/10/5-second flags it keeps fire no output (their COutputEvents are
-- never fired), so they are not kept here. CountdownTimer::IsElapsed is
-- strict: the countdown runs out after its end time, not at it.
function PointTimerModel:Think(now, q)
	if q.roundWon then self.endTime = nil end
	if not q.teamMayCapture then
		self.endTime = nil
		return {}
	end
	if self.endTime == nil then
		self.endTime = now + self.length
		return {
			{
				kind = START,
				endTime = self.endTime,
			},
		}
	end
	-- the point must be fully owned by its owner before the reset
	if now > self.endTime and not q.capping then
		self.endTime = nil
		return { { kind = END } }
	end
	return {}
end
