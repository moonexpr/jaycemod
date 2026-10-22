-- Respawn modifiers: what a player did since their last spawn moves their
-- respawn sooner or later, each reason told on the respawn screen. TF2 has
-- none of its own (its waves vary by team: team size, captures' team_spawn);
-- these are Sandcastle's. The total moves the time a dead player's wait
-- counts from (games.gameplay.rounds' MinSpawnTime), so the waves keep their
-- rules: sooner by at most the team's wave, never into the death animation,
-- later by at most MOST_PENALTY.
local format, ipairs, max, min = string.format, ipairs, math.max, math.min
local Credit = require("games.gameplay.kill_credit")
module(...)

-- Reasons, in the order they are told: sooner first, then later.
KILLS, CAPTURE, DEFENSE, FINISHED_OFF, SUICIDE = "kills", "capture", "defense", "finished_off", "suicide"

KILL_SECONDS = 1 -- each kill of an enemy, player or soldier
MOST_KILLS = 3 -- kills past these are told but count for nothing
CAPTURE_SECONDS = 2 -- each point captured standing on it
DEFENSE_SECONDS = 2 -- each capture blocked, named its defender
SUICIDE_SECONDS = 5 -- killing oneself (not a team change)
MOST_PENALTY = 10

local function Entry(reason, count, seconds)
	return { reason = reason, count = count, seconds = seconds }
end

-- facts = { kills, captures, defenses (counts), finishedOff, suicide }
-- since the last spawn -> the reasons that move the respawn, in order:
-- { reason, count, seconds (negative: sooner) }.
function For(facts)
	local list = {}
	if facts.kills > 0 then
		list[#list + 1] = Entry(KILLS, facts.kills, -min(facts.kills, MOST_KILLS) * KILL_SECONDS)
	end
	if facts.captures > 0 then
		list[#list + 1] = Entry(CAPTURE, facts.captures, -facts.captures * CAPTURE_SECONDS)
	end
	if facts.defenses > 0 then
		list[#list + 1] = Entry(DEFENSE, facts.defenses, -facts.defenses * DEFENSE_SECONDS)
	end
	-- a death the world dealt, credited to an enemy (games.gameplay.kill_credit)
	if facts.finishedOff then list[#list + 1] = Entry(FINISHED_OFF, 1, Credit.CREDITED_RESPAWN) end
	if facts.suicide then list[#list + 1] = Entry(SUICIDE, 1, SUICIDE_SECONDS) end
	return list
end

-- The seconds list moves the respawn, for a team whose waves are wave
-- seconds long, and whether a limit cut it.
function Total(list, wave)
	local sum = 0
	for _, m in ipairs(list) do sum = sum + m.seconds end
	local total = max(-wave, min(sum, MOST_PENALTY))
	return total, total ~= sum
end

local WORDS = {
	[KILLS] = function(n) return n == 1 and "1 kill" or format("%d kills", n) end,
	[CAPTURE] = function(n) return n == 1 and "Captured a point" or format("Captured a point (%d)", n) end,
	[DEFENSE] = function(n) return n == 1 and "Defended a point" or format("Defended a point (%d)", n) end,
	[FINISHED_OFF] = function() return "Finished off by an enemy" end,
	[SUICIDE] = function() return "Suicide" end,
}

-- A reason in words, for the respawn screen.
function Describe(m)
	return WORDS[m.reason](m.count)
end

-- Seconds a reason moves the respawn, signed: "-2 s" sooner, "+5 s" later.
function Seconds(seconds)
	return format("%s%g s", seconds > 0 and "+" or "", seconds)
end
