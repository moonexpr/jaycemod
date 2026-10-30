-- The CS:S gamerules' rules (cs_gamerules forwards to them): what CS:S's
-- round-end inputs do to a round, and when a timed round runs out.
local Rounds = gameplay.rounds
local Teams = gameplay.teams
module(...)

local W = Rounds.WINREASON

-- A map's round-end input, lower-cased, to how it ends the round: the winner
-- and why, or draw. The terrorists are RED, the counter-terrorists BLU.
local INPUTS = {
	endround_terroristswin = { winner = Teams.RED, reason = W.OPPONENTS_DEAD },
	endround_counterterroristswin = { winner = Teams.BLUE, reason = W.OPPONENTS_DEAD },
	endround_hostagesrescued = { winner = Teams.BLUE, reason = W.HOSTAGES_RESCUED },
	endround_hostagesnotrescued = { winner = Teams.RED, reason = W.HOSTAGES_NOT_RESCUED },
	endround_draw = { draw = true },
}

-- The ending the input asks for, or nil when it is not a round-end input.
function Input(name)
	return INPUTS[name]
end

-- Whether a timed round (limit seconds, 0 for untimed) has run out after
-- elapsed seconds.
function Expired(limit, elapsed)
	return limit > 0 and elapsed >= limit
end
