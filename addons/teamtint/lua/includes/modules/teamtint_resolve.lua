-- Which team a body shows (its representation): RED, BLU, or ORIGINAL, as
-- its model was made. In order: a debug override (the teamtint tool's,
-- stored on the body as a networked integer), a team given in code (a
-- ragdoll inherits its body's), then the team the gamemode says it fights
-- for (the TeamTintTeamOf hook's answer). A value that is none of the
-- three is no answer. GMod's require("teamtint_resolve") loads it.
module("teamtint_resolve")

RED = "red"
BLU = "blu"
ORIGINAL = "original"

local REPRESENTATIONS = { [RED] = true, [BLU] = true, [ORIGINAL] = true }

-- An override on the network: 0 for none.
NO_OVERRIDE = 0
local TO_NETWORK = { [RED] = 1, [BLU] = 2, [ORIGINAL] = 3 }
local FROM_NETWORK = { [1] = RED, [2] = BLU, [3] = ORIGINAL }

function ToNetwork(rep)
	return TO_NETWORK[rep] or NO_OVERRIDE
end

function FromNetwork(value)
	return FROM_NETWORK[value]
end

local function Valid(rep)
	return REPRESENTATIONS[rep] and rep or nil
end

-- What says, in order: { override, given, team }; each a representation
-- or nil.
function Representation(says)
	return Valid(says.override) or Valid(says.given) or Valid(says.team) or ORIGINAL
end

-- Which of them decided: "override", "given", "team" or "none".
function Source(says)
	if Valid(says.override) then return "override" end
	if Valid(says.given) then return "given" end
	if Valid(says.team) then return "team" end
	return "none"
end
