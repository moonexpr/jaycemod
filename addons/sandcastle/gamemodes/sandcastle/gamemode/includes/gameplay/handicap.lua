-- The handicap a passed Help Other Team vote grants (decision Q6,
-- docs/spawn-menu-design.md): the helped team respawns in a shorter wave
-- (WAVE_SCALE of what it would wait; the Round applies it,
-- Round:SetWaveScale) and its soldiers gain CAPABILITIES. One team at a
-- time, for the rest of the match: a match's start and a scramble clear it.
-- An immutable value.
--   New() -> nobody helped; handicap:Grant(team) -> a new value, or the
--   refusal ALREADY_SUPPORTED; handicap:Supported() -> the team, or
--   Teams.UNASSIGNED; handicap:WaveScale(team); handicap:Capabilities(team)
local Capabilities = gameplay.capabilities
local Teams = gameplay.teams
local Transaction = transaction
local setmetatable = setmetatable
module(...)

-- The share of its respawn wave a helped team waits (tuning).
WAVE_SCALE = 0.5
NO_SCALE = 1

ALREADY_SUPPORTED = "already supported"

-- What a helped team's soldiers gain.
local HELPED = Capabilities.None():With(Capabilities.AMBUSH)
local NONE = Capabilities.None()

local Handicap = {}
Handicap.__index = Handicap

local function Of(team)
	return setmetatable({ supported = team }, Handicap)
end

function New()
	return Of(Teams.UNASSIGNED)
end

function Handicap:Grant(team)
	if self.supported == team then Transaction.Refuse(ALREADY_SUPPORTED, "That team is already being helped.") end
	return Of(team)
end

function Handicap:Supported() return self.supported end

function Handicap:WaveScale(team)
	return team == self.supported and WAVE_SCALE or NO_SCALE
end

function Handicap:Capabilities(team)
	return team == self.supported and HELPED or NONE
end
