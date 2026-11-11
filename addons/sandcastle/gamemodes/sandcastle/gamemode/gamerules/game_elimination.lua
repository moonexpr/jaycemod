-- The game every map can play: the last team standing wins the round.
local GAME = {}

function GAME:Applies ()
	return true
end

local function Alive (id)

	local count = 0
	for _, ply in ipairs (team.GetPlayers (id)) do
		if ply:Alive () then count = count + 1 end
	end
	return count

end

function GAME:RoundWinner ()

	local red, blue = Alive (TEAM_RED), Alive (TEAM_BLUE)
	if red == 0 and blue > 0 then return TEAM_BLUE end
	if blue == 0 and red > 0 then return TEAM_RED end

end

game_manager.RegisterClass ("game_elimination", GAME, "game_default")
