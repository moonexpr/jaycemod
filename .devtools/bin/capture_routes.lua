-- Route demand on the dedicated server, through server_lua.py:
--
--   server_lua.py -f .devtools/bin/capture_routes.lua     defines WSRouteCapture
--   server_lua.py 'return WSRouteCapture.Start(120, true)' capture 120 s, from a round restart
--   server_lua.py 'return WSRouteCapture.Report()'         what was asked, why, and what it cost
--
-- Every Lua route request is recorded with its source (a soldier's, a lane
-- leg, the setup gates' search), team, start and goal nav areas, when it was
-- asked and answered, its expansions, and whether it found the goal; a
-- soldier's with why its Travel planned (a new trip, stuck, the goal moved,
-- by the call site of Travel:Plan); every lane plan with what started it.
WSRouteCapture = WSRouteCapture or {}
local C = WSRouteCapture

-- Travel:Plan's call sites in foundation.aiwar.orders.
local REASONS = { [750] = "new trip", [677] = "stuck", [763] = "goal moved" }

local restore = {}

local function Swap(tbl, key, fn)
	restore[#restore + 1] = { tbl, key, tbl[key] }
	tbl[key] = fn
end

local function Unswap()
	for i = #restore, 1, -1 do restore[i][1][restore[i][2]] = restore[i][3] end
	restore = {}
end

local function TravelClass(aw)
	local found
	local function Walk(action)
		while action and not found do
			if action.name == "Travel" then
				found = getmetatable(action)
				return
			end
			if action._child then Walk(action._child) end
			action = action._buried
		end
	end
	for _, entry in pairs(aw.soldiers) do
		if not found then Walk(entry.npc.behavior.action) end
	end
	return found
end

local function AreaId(pos)
	local area = navmesh.GetNearestNavArea(pos, false, 200, false, true)
	return IsValid(area) and area:GetID() or -1
end

function C.Start(seconds, restart)
	if C.running then return "already running" end
	local aw, npcs = WS.Feature("aiwar"), WS.Feature("npc")
	local HL2 = WS.require("foundation.npc.path.hl2")
	local Lanes = WS.require("foundation.aiwar.lanes")
	C.list, C.plans, C.started, C.running = {}, {}, CurTime(), true
	local reason
	local Travel = TravelClass(aw)
	if Travel then
		local plan = Travel.Plan
		Swap(Travel, "Plan", function(self, me, goal)
			reason = REASONS[debug.getinfo(2, "l").currentline] or "other"
			local r = plan(self, me, goal)
			reason = nil
			return r
		end)
	end
	local planLanes = aw.PlanLanes
	Swap(aw, "PlanLanes", function(self, team, to, field, now)
		local plan = self.lanePlans and self.lanePlans[team]
		local why = "first"
		if plan then
			why = npcs:BlockerGeneration() ~= plan.blockers and "blockers changed"
				or (plan.to and plan.to.x == math.huge and "retry after failing") or "front moved"
		end
		C.plans[#C.plans + 1] = { t = CurTime() - C.started, team = team, why = why }
		return planLanes(self, team, to, field, now)
	end)
	local request = npcs.RequestRoute
	Swap(npcs, "RequestRoute", function(self, req)
		local source = req.ignoreBlockers and "gates" or req.strategy == HL2 and "soldier"
			or req.strategy == Lanes.Strategy and "lanes" or "other"
		local rec = {
			t = CurTime() - C.started,
			source = source,
			team = req.bot and req.bot.team or 0,
			to = AreaId(req.to),
			toPos = req.to,
			reason = source == "soldier" and reason or nil,
		}
		local n = #self.searches
		local r = request(self, req)
		local entry = self.searches[n + 1]
		if entry then
			local search, onDone = entry.search, entry.onDone
			entry.onDone = function(areas, found)
				rec.done, rec.expanded, rec.found = CurTime() - C.started, search.expanded, found
				return onDone(areas, found)
			end
		end
		C.list[#C.list + 1] = rec
		return r
	end)
	timer.Create("ws_route_capture", seconds, 1, function()
		Unswap()
		C.running = false
		C.seconds = seconds
	end)
	if restart then RunConsoleCommand("mp_round_restart") end
	return string.format("capturing route requests for %d s%s", seconds, restart and ", from a round restart" or "")
end

function C.Report()
	local L, seconds = C.list or {}, C.seconds or (CurTime() - (C.started or CurTime()))
	local lines = { string.format("%s; %d requests in %.0f s (%.2f/s)", C.running and "running" or "finished", #L, seconds, #L / math.max(1, seconds)) }
	local by, expanded, missed, reasons = {}, {}, {}, {}
	for _, r in ipairs(L) do
		by[r.source] = (by[r.source] or 0) + 1
		expanded[r.source] = (expanded[r.source] or 0) + (r.expanded or 0)
		if r.found == false then missed[r.source] = (missed[r.source] or 0) + 1 end
		if r.reason then reasons[r.reason] = (reasons[r.reason] or 0) + 1 end
	end
	for source, n in pairs(by) do
		lines[#lines + 1] = string.format("  %-8s %4d requests, %7d expansions, %d not found", source, n, expanded[source], missed[source] or 0)
	end
	local why = {}
	for k, n in pairs(reasons) do why[#why + 1] = k .. " " .. n end
	lines[#lines + 1] = "soldiers asked because: " .. table.concat(why, ", ")
	local plans = {}
	for _, p in ipairs(C.plans or {}) do plans[p.why] = (plans[p.why] or 0) + 1 end
	local pw = {}
	for k, n in pairs(plans) do pw[#pw + 1] = k .. " " .. n end
	lines[#lines + 1] = string.format("lane plans: %d (%s)", #(C.plans or {}), table.concat(pw, ", "))
	local latency = {}
	for _, r in ipairs(L) do if r.done then latency[#latency + 1] = r.done - r.t end end
	table.sort(latency)
	if #latency > 0 then
		lines[#lines + 1] = string.format("request to answer: median %.2f s, p90 %.2f s, worst %.2f s",
			latency[math.ceil(#latency * 0.5)], latency[math.ceil(#latency * 0.9)], latency[#latency])
	end
	return table.concat(lines, "\n")
end
