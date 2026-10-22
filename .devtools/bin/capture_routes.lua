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
-- A lane leg is also recorded with its plan's reason, its lane's kind, its
-- lane and leg index, and whether it starts and ends where the same leg of
-- the team's last plan did (within SAME_LEG): the legs a re-plan could keep.
WSRouteCapture = WSRouteCapture or {}
local C = WSRouteCapture

-- Travel:Plan's call sites in foundation.aiwar.orders.
local REASONS = { [750] = "new trip", [677] = "stuck", [763] = "goal moved" }

-- How near a leg's ends must be to the last plan's to count as the same leg.
local SAME_LEG = 64

-- A lane plan's front must move this far to re-plan (sv_field.lua's LANE_REPLAN).
local LANE_REPLAN = 1024

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
	local HL2 = WS.require("games.ns.path.hl2")
	local Lanes = WS.require("games.ns.lanes")
	C.list, C.plans, C.started, C.running = {}, {}, CurTime(), true
	-- team -> the last plan's legs (lane -> leg -> { from, to }); team -> the
	-- plan being asked for and its legs so far; team -> why that plan ran
	local lastLegs, current, planWhy = {}, {}, {}
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
			why = (plan.to.x == math.huge and "retry after failing")
				or (Vector(to.x, to.y, to.z):Distance(Vector(plan.to.x, plan.to.y, plan.to.z)) > LANE_REPLAN and "front moved")
				or "blockers changed"
		end
		planWhy[team] = why
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
		local plan = source == "lanes" and aw.lanePlans and aw.lanePlans[rec.team]
		local spec = plan and plan.specs[plan.tries]
		if spec then
			local team = rec.team
			if not current[team] or current[team].plan ~= plan then
				lastLegs[team] = current[team] and current[team].legs or {}
				current[team] = { plan = plan, legs = {} }
			end
			local lane, leg = plan.tries, 1
			for i, stop in ipairs(spec.stops) do
				if Vector(stop.x, stop.y, stop.z):DistToSqr(req.to) < 1 then leg = i end
			end
			local old = lastLegs[team][lane] and lastLegs[team][lane][leg]
			rec.why, rec.kind, rec.lane, rec.leg = planWhy[team], spec.kind, lane, leg
			rec.same = old ~= nil and old.from:Distance(req.from) < SAME_LEG and old.to:Distance(req.to) < SAME_LEG
			local legs = current[team].legs
			legs[lane] = legs[lane] or {}
			legs[lane][leg] = { from = Vector(req.from), to = Vector(req.to) }
		end
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
	local legs, order = {}, {}
	for _, r in ipairs(L) do
		if r.kind then
			local key = string.format("%-18s %-6s leg %d", r.why or "?", r.kind, r.leg)
			if not legs[key] then legs[key] = { n = 0, expanded = 0, missed = 0, same = 0, sameExpanded = 0 }; order[#order + 1] = key end
			local g = legs[key]
			g.n, g.expanded = g.n + 1, g.expanded + (r.expanded or 0)
			if r.found == false then g.missed = g.missed + 1 end
			if r.same then g.same, g.sameExpanded = g.same + 1, g.sameExpanded + (r.expanded or 0) end
		end
	end
	table.sort(order)
	if #order > 0 then
		lines[#lines + 1] = "lane legs by plan reason, kind, leg: count, expansions, not found; same ends as last plan: count, expansions"
		for _, key in ipairs(order) do
			local g = legs[key]
			lines[#lines + 1] = string.format("  %s  %3d %7d %3d   same %3d %7d", key, g.n, g.expanded, g.missed, g.same, g.sameExpanded)
		end
	end
	local latency = {}
	for _, r in ipairs(L) do if r.done then latency[#latency + 1] = r.done - r.t end end
	table.sort(latency)
	if #latency > 0 then
		lines[#lines + 1] = string.format("request to answer: median %.2f s, p90 %.2f s, worst %.2f s",
			latency[math.ceil(#latency * 0.5)], latency[math.ceil(#latency * 0.9)], latency[#latency])
	end
	return table.concat(lines, "\n")
end
