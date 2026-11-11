-- NextSoldier's behaviours in what !print of a soldier shows (ulx_luadev's luadev_overlay, its
-- ULXLuaDevDescribe hook): its main tree's stack and its TacticalLeggings tree's, each down
-- to the behaviour it runs now. A NextBot has a main tree; a bot player is a NextSoldier when it
-- has the group tree, which only player.CreateNextSoldier's are given.
local function Shape(frames)
	local names = {}
	for i, frame in ipairs(frames) do names[i] = frame.name end
	return table.concat(names, " > ")
end

hook.Add("ULXLuaDevDescribe", "sandcastle_dev", function(ent, lines)
	local engine = nextsoldier.engine
	local group = engine.GroupStack(ent)
	if not (ent:IsNextBot() or #group > 0) then return end
	lines[#lines + 1] = "behavior: " .. Shape(engine.Stack(ent))
	if #group > 0 then lines[#lines + 1] = "group: " .. Shape(group) end
end)

-- Players by team for easylua, made as easylua makes all, humans and bots (CreateAllFunction):
-- RED, BLU and SPEC. Called, each gives its team's players now (RED()); a method called on it
-- runs on each of them (RED:SetHealth(1), BLU:AddCondition("URINE", 5), SPEC:Kill()). Only where
-- luadev's easylua is loaded, as on the dev server.
if not CreateAllFunction then return end

local function Team(number)
	return function() return team.GetPlayers(number) end
end

RED, BLU, SPEC = nil, nil, nil

hook.Add("InitPostEntity", "luadev_gamemode_done", function()
	RED = CreateAllFunction(Team(WS.TEAM_RED))
	BLU = CreateAllFunction(Team(WS.TEAM_BLUE))
	SPEC = CreateAllFunction(Team(WS.TEAM_SPECTATOR))
end)
