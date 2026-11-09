-- Telling friend from foe while teams play (ws/cl_friendly_id.lua). teamPlay
-- is WS.TeamPlay(): in Sandbox mode there are no sides. Spectators have none.
local Teams = gameplay.teams
module(...)

function Friendly(teamPlay, mine, theirs)
	return teamPlay and Teams.EnemyOf(mine) ~= nil and mine == theirs
end

function Enemy(teamPlay, mine, theirs)
	return teamPlay and Teams.EnemyOf(mine) == theirs
end
