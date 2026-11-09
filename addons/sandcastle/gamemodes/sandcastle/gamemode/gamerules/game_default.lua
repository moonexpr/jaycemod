-- The base of the games: played nowhere, deciding nothing.
local GAME = {}

function GAME:Applies()
	return false
end

-- The team that has won the round, or nil while it goes on.
function GAME:RoundWinner()
end

-- Adds this game's part of how near each team is to completing the objective.
function GAME:Standing( objective )
end

game_manager.RegisterClass( "game_default", GAME )
