-- Telling friend from foe while teams play (ws/cl_friendly_id.lua). teamPlay
-- is WS.TeamPlay(): in Sandbox mode there are no sides. Spectators have none.
local Teams = gameplay.teams
local floor = math.floor
module (...)

function Friendly (teamPlay, mine, theirs)
	return teamPlay and Teams.EnemyOf (mine) ~= nil and mine == theirs
end

function Enemy (teamPlay, mine, theirs)
	return teamPlay and Teams.EnemyOf (mine) == theirs
end

-- A building's target id: its team's, and its builder's (who has no team without sides).
function SeesBuilding (teamPlay, mine, buildingTeam, isBuilder)
	return isBuilder or Friendly (teamPlay, mine, buildingTeam)
end

-- Its lines: its name, then its health, or how far up it is while it goes up.
function BuildingLines (name, health, maxHealth, constructed)
	if constructed < 1 then return { name, "Building: " .. floor (constructed * 100) .. "%" } end
	return { name, "Health: " .. health .. " / " .. maxHealth }
end
