-- Who is credited with a death nobody dealt, as TF2 credits it: a victim
-- remembers the enemies who hurt it last (CTFPlayer's damager history), and
-- a death by the world, a trigger or a fall within ENVIRONMENT_WINDOW of an
-- enemy's hit is that enemy's kill (CTFPlayer::Event_Killed's assisted
-- suicide, "finished off"). The victim of such a death respawns sooner
-- (CREDITED_RESPAWN). The controller (ws/sv_kill_credit.lua) records the
-- hits and rewrites the lethal one's attacker.
local floor, ipairs, setmetatable = math.floor, ipairs, setmetatable
module(...)

HISTORY = 4 -- MAX_ACHIEVEMENT_HISTORY_SLOTS
ENVIRONMENT_WINDOW = 5 -- Event_Killed's window for a world death
ASSIST_WINDOW = 3 -- TF_TIME_ASSIST_KILL

-- Seconds added to the respawn time of one whose environmental death was
-- credited to another: they come back sooner.
CREDITED_RESPAWN = -3

-- TF_SCORE_KILL_ASSISTS_PER_POINT: the assists a point is worth.
ASSISTS_PER_POINT = 2

-- A player's (or soldier's) points, as CTFGameRules::CalcPlayerScore counts
-- them: a point a kill, and one for every ASSISTS_PER_POINT assists.
function Points(kills, assists)
	return kills + floor(assists / ASSISTS_PER_POINT)
end

-- Whether a hit is remembered: only an enemy's (CTFPlayer::OnTakeDamage
-- ignores its own team's, so a rocket jump or a teammate's splash never
-- takes the kill).
function Remembered(attackerTeam, victimTeam, selfHarm)
	return not selfHarm and attackerTeam ~= victimTeam
end

local History = {}
History.__index = History

-- The damagers a victim remembers, the latest first, each once.
function Damagers()
	return setmetatable({ list = {} }, History)
end

function History:Record(damager, now)
	local kept = { { damager = damager, at = now } }
	for _, entry in ipairs(self.list) do
		if entry.damager ~= damager and #kept < HISTORY then kept[#kept + 1] = entry end
	end
	self.list = kept
end

-- The latest damager who hit within the last within seconds, other than
-- skip (the one credited, asking for an assister), or nil.
function History:Recent(now, within, skip)
	for _, entry in ipairs(self.list) do
		if now - entry.at > within then return nil end
		if entry.damager ~= skip then return entry.damager end
	end
	return nil
end

-- The damagers held, the latest first.
function History:Held()
	local held = {}
	for i, entry in ipairs(self.list) do held[i] = entry.damager end
	return held
end
