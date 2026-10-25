-- On the dedicated server: the npc controller's route searches with the
-- blockers and spawn rooms asked as Lua rules, area by area (as
-- sv_routes asked them before), against the same searches told them as
-- data up front (the controller's ClosedFor and SpawnRooms), on the live
-- mesh snapshot, for seeded random area pairs and both teams: each pair's
-- status, expansions and route compared, with the time each took; every
-- second pair asks as lanes do (nor over a link WS.NavLinkCrossable
-- refuses), against the uncrossable links the mesh build gathered.
--
--   dt lua -f .devtools/bin/route_told_check.lua     defines WSRouteToldCheck
--   dt lua 'return WSRouteToldCheck.Run(40)'         40 pairs a team: a report
local Pathfinder = graph.pathfinder
local Doors = nextsoldier.doors
local HL2 = WS.require("foundation.wetsands.path.hl2")

WSRouteToldCheck = WSRouteToldCheck or {}
local Check = WSRouteToldCheck

local function Area(id)
	return navmesh.GetNavAreaByID(id)
end

local function Search(c, team, start, goal, told, rules)
	local bot = { entIndex = 1, now = CurTime(), team = team }
	local max = navmesh.GetNavAreaCount()
	local began = SysTime()
	local search = wetsands.navsearch.New(c.navMesh, HL2, HL2.SOLDIER_LIMITS, bot, start, goal, Area(goal):GetCenter(), max, told, rules)
	while search:Step(max + 1) == Pathfinder.RUNNING do end
	return { status = search.status, expanded = search.expanded, route = table.concat(search:Route(), " "), seconds = SysTime() - began }
end

function Check.Run(count)
	local c = WS.Feature("npc")
	if not c.navMesh then return "the npc controller has no mesh snapshot yet: ask a route first" end
	local areas = navmesh.GetAllNavAreas()
	local x, same, total, asked, told, expansions = 12345, 0, 0, 0, 0, 0
	local function Next(n)
		x = (x * 1103515245 + 12345) % 2147483648
		return x % n + 1
	end
	local mismatches = {}
	for _, team in ipairs({ 2, 3 }) do
		c:RefreshBlockers(CurTime())
		local rules = {
			traversable = function(id)
				return not Doors.Blocks(c.navBlocked[id], team) and not c:EngineBlocks(Area(id), team)
			end,
			room = function(id) return c:SpawnRoomTeam(Area(id)) end,
		}
		-- as lanes ask: nor over a link WS.NavLinkCrossable refuses
		local laneRules = {
			traversable = rules.traversable,
			room = rules.room,
			crossable = function(from, to) return WS.NavLinkCrossable(Area(from), Area(to)) end,
		}
		for i = 1, count do
			local start, goal = areas[Next(#areas)]:GetID(), areas[Next(#areas)]:GetID()
			local lane = i % 2 == 0
			local toldRooms = { closed = c:ClosedFor(team), rooms = c:SpawnRooms(), uncrossable = lane and c.navUncrossable or nil }
			local a = Search(c, team, start, goal, nil, lane and laneRules or rules)
			local b = Search(c, team, start, goal, toldRooms, nil)
			total, asked, told, expansions = total + 1, asked + a.seconds, told + b.seconds, expansions + a.expanded
			if a.status == b.status and a.expanded == b.expanded and a.route == b.route then
				same = same + 1
			elseif #mismatches < 3 then
				mismatches[#mismatches + 1] = string.format("team %d %d->%d rules %s/%d, told %s/%d", team, start, goal, a.status, a.expanded, b.status, b.expanded)
			end
		end
	end
	local rooms, closed = 0, 0
	for _ in pairs(c:SpawnRooms()) do rooms = rooms + 1 end
	for _ in pairs(c:ClosedFor(2)) do closed = closed + 1 end
	return string.format("%s: %d searches, %d alike; %d expansions: rules %.2f us, told %.2f us an expansion (%d room areas, %d closed to RED)%s",
		game.GetMap(), total, same, expansions, asked * 1e6 / math.max(expansions, 1), told * 1e6 / math.max(expansions, 1),
		rooms, closed, #mismatches > 0 and ("; " .. table.concat(mismatches, "; ")) or "")
end
