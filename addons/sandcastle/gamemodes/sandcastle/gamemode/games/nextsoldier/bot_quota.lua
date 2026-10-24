-- How many bot players a server keeps (the AI war's bot soldiers), by TF2's
-- tf_bot_quota rules (CTFBotManager::MaintainBotQuota): tf_bot_quota_mode
-- says what the quota counts, tf_bot_join_after_player waits for a human,
-- and, as tf_bot_auto_vacate does, the bots leave one slot free for a human
-- to join. The bots change one at a time: added to a team the way a player
-- is auto-assigned (gameplay.teams' AutoTeam), kicked from the team with
-- more players.
local Teams = gameplay.teams
local lower, max, min = string.lower, math.max, math.min
module(...)

-- tf_bot_quota_mode: NORMAL keeps quota bots; FILL tops the players on the
-- game teams up to quota; MATCH keeps quota bots for each of them.
NORMAL, FILL, MATCH = "normal", "fill", "match"
local MODES = {
	[NORMAL] = NORMAL,
	[FILL] = FILL,
	[MATCH] = MATCH,
}

-- What a step does.
ADD, KICK = "add", "kick"

-- The slots the bots leave free (tf_bot_auto_vacate's one).
local VACATE = 1

-- A tf_bot_quota_mode value, or nil for none of its words.
function Mode(text)
	return MODES[lower(text)]
end

-- The bots wanted. settings: { mode, quota, joinAfterPlayer }; population:
-- { humans (on the game teams), spectators (humans on no game team),
-- bots, slots (the server's most players) }.
function Wanted(settings, population)
	local humans = population.humans
	local wanted = settings.quota
	if settings.mode == FILL then
		wanted = wanted - humans
	elseif settings.mode == MATCH then
		wanted = wanted * humans
	end
	if settings.joinAfterPlayer and humans == 0 then wanted = 0 end
	wanted = min(wanted, population.slots - humans - population.spectators - VACATE)
	return max(wanted, 0)
end

-- ADD or KICK one bot toward the quota, or nil on it.
function Step(settings, population)
	local wanted = Wanted(settings, population)
	if population.bots < wanted then return ADD end
	if population.bots > wanted then return KICK end
	return nil
end

-- The team a bot is kicked from: teams[team] = { players, bots } for RED
-- and BLU; the one with more players, on an even split the one with more
-- bots, and only a team with a bot to kick. nil with no bots.
function TeamToKick(teams)
	local red, blue = teams[Teams.RED], teams[Teams.BLUE]
	if red.bots == 0 and blue.bots == 0 then return nil end
	if red.bots == 0 then return Teams.BLUE end
	if blue.bots == 0 then return Teams.RED end
	if red.players ~= blue.players then return red.players > blue.players and Teams.RED or Teams.BLUE end
	if red.bots ~= blue.bots then return red.bots > blue.bots and Teams.RED or Teams.BLUE end
	return Teams.RED
end
