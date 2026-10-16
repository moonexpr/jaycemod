-- The mode every rule keys on, from the facts the server replicates:
-- whether rounds run, whether an admin stopped the game, and whether an AI
-- war or an arena is what runs. A stopped game is Sandbox mode even while an
-- AI war is set up: the map plays like Sandbox until a game begins again.
-- foundation.gamemode owns the transition between modes; this only names
-- the one a rule should apply.
local error, type = error, type
module(...)

SANDBOX, GAMEPLAY, AIWAR, ARENA = "sandbox", "gameplay", "aiwar", "arena"

local FACTS = { "roundsActive", "gameplayStopped", "aiwar", "arena" }

-- facts = { roundsActive, gameplayStopped, aiwar, arena }, booleans.
function Of(facts)
	for i = 1, #FACTS do
		if type(facts[FACTS[i]]) ~= "boolean" then error("play mode: fact " .. FACTS[i] .. " is not a boolean", 2) end
	end
	if not facts.roundsActive or facts.gameplayStopped then return SANDBOX end
	if facts.aiwar then return AIWAR end
	if facts.arena then return ARENA end
	return GAMEPLAY
end

function IsSandbox(mode)
	return mode == SANDBOX
end
