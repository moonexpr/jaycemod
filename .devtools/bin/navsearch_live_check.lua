-- On the dedicated server, with native/wetsands installed over
-- wetsands.navsearch: the live mesh snapshotted into both implementations
-- (the native one in place, the Lua twin loaded beside it), the same
-- searches between seeded random area pairs run through each, and each
-- pair's status, expansions and route compared, with the time each took.
--
--   dt lua -f .devtools/bin/navsearch_live_check.lua      defines WSNavSearchCheck
--   dt lua 'return WSNavSearchCheck.Run(40)'              40 pairs: a report
--
-- Builds both meshes in one call (a hitch of up to a second): a dev server's
-- tool, never a live game's.
local Pathfinder = graph.pathfinder
local HL2 = WS.require("foundation.wetsands.path.hl2")

WSNavSearchCheck = WSNavSearchCheck or {}
local Check = WSNavSearchCheck

-- The Lua twin, loaded apart from the global the native module replaced.
local function LuaTwin()
	local chunk = CompileFile(GAMEMODE.FolderName .. "/gamemode/foundation/wetsands/navsearch.lua")
	local env = setmetatable({}, { __index = _G })
	setfenv(chunk, env)("ws_navsearch_check.lua_twin")
	return package.loaded["ws_navsearch_check.lua_twin"] or env
end

local function Snapshot(NavSearch, areas)
	local mesh = NavSearch.Mesh()
	for _, area in ipairs(areas) do
		local c = area:GetCenter()
		mesh:Area(area:GetID(), c.x, c.y, c.z, area:GetAttributes())
	end
	for _, area in ipairs(areas) do
		local c = area:GetCenter()
		for _, other in ipairs(area:GetAdjacentAreas()) do
			mesh:Link(area:GetID(), other:GetID(), other:GetCenter():Distance(c), area:ComputeAdjacentConnectionHeightChange(other))
		end
	end
	mesh:Seal()
	return mesh
end

local function Run1(NavSearch, mesh, start, goal, goalPos, max)
	local bot = { entIndex = 1, now = CurTime(), team = 2 }
	local began = SysTime()
	local search = NavSearch.New(mesh, HL2, HL2.SOLDIER_LIMITS, bot, start, goal, goalPos, max)
	while search:Step(max + 1) == Pathfinder.RUNNING do end
	return { status = search.status, expanded = search.expanded, route = table.concat(search:Route(), " "), seconds = SysTime() - began }
end

function Check.Run(pairs)
	local Native = wetsands.navsearch
	if debug.getinfo(Native.New, "S").what ~= "C" then return "wetsands.navsearch is not the native one" end
	local Lua = LuaTwin()
	local areas = navmesh.GetAllNavAreas()
	local began = SysTime()
	local nativeMesh = Snapshot(Native, areas)
	local nativeBuild = SysTime() - began
	began = SysTime()
	local luaMesh = Snapshot(Lua, areas)
	local luaBuild = SysTime() - began
	local x, same, nativeTime, luaTime, expansions, found = 12345, 0, 0, 0, 0, 0
	local function Next(n)
		x = (x * 1103515245 + 12345) % 2147483648
		return x % n + 1
	end
	local mismatches = {}
	for _ = 1, pairs do
		local start, goal = areas[Next(#areas)], areas[Next(#areas)]
		local goalPos = goal:GetCenter()
		local a = Run1(Native, nativeMesh, start:GetID(), goal:GetID(), goalPos, #areas)
		local b = Run1(Lua, luaMesh, start:GetID(), goal:GetID(), goalPos, #areas)
		nativeTime, luaTime, expansions = nativeTime + a.seconds, luaTime + b.seconds, expansions + b.expanded
		if a.status == Pathfinder.FOUND then found = found + 1 end
		if a.status == b.status and a.expanded == b.expanded and a.route == b.route then
			same = same + 1
		elseif #mismatches < 3 then
			mismatches[#mismatches + 1] = string.format("%d->%d native %s/%d, Lua %s/%d", start:GetID(), goal:GetID(), a.status, a.expanded, b.status, b.expanded)
		end
	end
	return string.format("%s, %d areas: mesh built natively in %.1f ms, in Lua in %.1f ms; %d pairs (%d found), %d alike; %d expansions: native %.2f us, Lua %.2f us an expansion (JIT %s)%s",
		game.GetMap(), #areas, nativeBuild * 1e3, luaBuild * 1e3, pairs, found, same, expansions,
		nativeTime * 1e6 / math.max(expansions, 1), luaTime * 1e6 / math.max(expansions, 1), jit.status() and "on" or "off",
		#mismatches > 0 and ("; " .. table.concat(mismatches, "; ")) or "")
end
