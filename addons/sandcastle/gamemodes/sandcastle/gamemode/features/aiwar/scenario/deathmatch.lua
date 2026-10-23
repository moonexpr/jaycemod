-- The deathmatch scenario (features.aiwar.scenario): a tied match's
-- deathmatch (games.gameplay.rounds' DeathmatchMode), frags alone deciding it,
-- fought as arena's round is before its point opens
-- (features.aiwar.scenario.arena): every squad explores the map and hunts
-- what it sees. The map's objective counts for nothing, so its points are
-- none to the scenario, and none are needed.
local Base = require("features.aiwar.scenario")
local Arena = require("features.aiwar.scenario.arena")
module(...)

MODE = "deathmatch"

Scenario = Arena.Scenario:Extend(MODE)
Scenario.NEEDS = { Base.BASES, Base.WAYPOINTS }

local NO_POINTS = {}

function Scenario:Brief(field, now)
	field.points = NO_POINTS
	Arena.Scenario.Brief(self, field, now)
end
