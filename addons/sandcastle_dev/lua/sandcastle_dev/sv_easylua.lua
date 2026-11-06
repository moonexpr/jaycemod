-- Players by team for easylua, made as easylua makes all, humans and bots (CreateAllFunction):
-- RED, BLU and SPEC. Called, each gives its team's players now (RED()); a method called on it
-- runs on each of them (RED:SetHealth(1), BLU:AddCondition("URINE", 5), SPEC:Kill()). Only where
-- luadev's easylua is loaded, as on the dev server.
if not CreateAllFunction then return end

local function Team(number)
	return function() return team.GetPlayers(number) end
end

RED = CreateAllFunction(Team(WS.TEAM_RED))
BLU = CreateAllFunction(Team(WS.TEAM_BLUE))
SPEC = CreateAllFunction(Team(WS.TEAM_SPECTATOR))
