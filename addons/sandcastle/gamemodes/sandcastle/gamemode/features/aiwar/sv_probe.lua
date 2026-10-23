-- Part of the AI war controller (sv.lua): path probes along the lanes (ns_lanes_probe).
local Controller, Map = ...
local Probe = nextsoldier.probe
local ToVector, OnFloor, SPAWN_LIFT = Map.ToVector, Map.OnFloor, Map.SPAWN_LIFT

-- One probe (ws_drg_probe) walks each lane of each team from its first
-- point (games.nextsoldier.probe), on its team (a spawn door opens for it,
-- and its path keeps off doors shut to it, as a soldier's does); when the
-- last is done, the report is printed and kept (probeReport).
local PROBE_CLASS = "ws_drg_probe"
local PROBE_TIMER = "ns_lanes_probe"
local PROBE_STEP = 0.25

function Controller:ProbeLanes()
	self:EndProbes()
	local npcs = WS.Feature("npc")
	local runs, now = {}, CurTime()
	for team, lanes in pairs(self.laneSets or {}) do
		for index, lane in ipairs(lanes) do
			local ent = ents.Create(PROBE_CLASS)
			if IsValid(ent) then
				ent:SetPos(OnFloor(ToVector(lane.points[1])) + SPAWN_LIFT)
				ent:Spawn()
				ent:Activate()
				WS.SetTeamMember(ent, team)
				ent.NSAreaClosed = function(area) return npcs:NavBlocks(area, team) or self:ShutDoorIn(area, team) end
				local points = { unpack(lane.points, 2) }
				runs[#runs + 1] = { ent = ent, team = team, lane = index, kind = lane.kind, count = #points,
					probe = Probe.New(points, now), started = now }
			end
		end
	end
	self.probes = runs
	timer.Create(PROBE_TIMER, PROBE_STEP, 0, function() self:StepProbes() end)
	return { string.format("ns_lanes_probe: %d probes sent along the lanes; the report prints when the last is done", #runs) }
end

function Controller:StepProbes()
	local now, running = CurTime(), false
	for _, run in ipairs(self.probes or {}) do
		if not run.took then
			if not IsValid(run.ent) then
				run.took, run.lost = now - run.started, true
			else
				local pos = run.ent:GetPos()
				local command = run.probe:Step(pos, now, self:OnMesh(pos))
				if command.kind == Probe.DONE then
					run.took = now - run.started
					run.ent:Remove()
				elseif command.kind == Probe.REPATH then
					run.ent:NSRepath()
				elseif command.kind == Probe.RECOVER then
					run.ent:SetPos(command.to + SPAWN_LIFT)
				elseif command.kind == Probe.HOP then
					run.ent:NSHop(OnFloor(ToVector(command.to)))
				elseif run.to ~= command.to then
					run.to = command.to
					run.ent.NSTarget = OnFloor(ToVector(command.to))
				end
				running = running or not run.took
			end
		end
	end
	if running then return end
	timer.Remove(PROBE_TIMER)
	self.probeReport = self:ProbeReport()
	for _, line in ipairs(self.probeReport) do print(line) end
end

local function At(p) return string.format("(%.0f %.0f %.0f)", p.x, p.y, p.z) end

-- A line per lane, then one per point it stalled at.
function Controller:ProbeReport()
	local lines, totals = {}, {}
	for _, run in ipairs(self.probes or {}) do
		local counts = {}
		for _, found in ipairs(run.probe:Findings()) do
			counts[found.kind] = (counts[found.kind] or 0) + 1
			totals[found.kind] = (totals[found.kind] or 0) + 1
		end
		lines[#lines + 1] = string.format("team %d lane %d (%s): %d/%d points in %.0f s%s; fresh paths %d, hops %d, stuck %d, slow %d, off the mesh %d",
			run.team, run.lane, run.kind, run.probe:Reached(), run.count, run.took or 0, run.lost and ", probe lost" or "",
			counts[Probe.REPATH] or 0, counts[Probe.HOP] or 0, counts[Probe.STUCK] or 0, counts[Probe.SLOW] or 0, counts[Probe.OFFMESH] or 0)
		for _, found in ipairs(run.probe:Findings()) do
			if found.kind == Probe.STUCK or found.kind == Probe.SLOW or found.kind == Probe.OFFMESH then
				lines[#lines + 1] = string.format("  %s at point %d %s, standing at %s", found.kind, found.index, At(found.point), At(found.at))
			end
		end
	end
	lines[#lines + 1] = string.format("ns_lanes_probe: fresh paths %d, hops %d, stuck %d, slow %d, off the mesh %d",
		totals[Probe.REPATH] or 0, totals[Probe.HOP] or 0, totals[Probe.STUCK] or 0, totals[Probe.SLOW] or 0, totals[Probe.OFFMESH] or 0)
	return lines
end

function Controller:EndProbes()
	timer.Remove(PROBE_TIMER)
	for _, run in ipairs(self.probes or {}) do
		if IsValid(run.ent) then run.ent:Remove() end
	end
	self.probes = nil
end
