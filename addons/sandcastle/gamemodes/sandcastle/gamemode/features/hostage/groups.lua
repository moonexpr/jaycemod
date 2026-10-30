-- Hostage groups: the hostages standing near one another, which the AI war
-- organises its squads by. Each team forms a squad for every group, and every
-- squad owns one group: BLU's to free it and lead it out, RED's to guard it
-- (features.aiwar.scenario.hostage). Positions are { x, y, z } tables.
local error, ipairs, pairs, sort = error, ipairs, pairs, table.sort
local concat, remove = table.concat, table.remove
local Distance = math.geometry.Distance
module(...)

-- Hostages this near one another, linked through their neighbours, are one
-- group.
RADIUS = 400

-- hostages: { id, pos }s, ids distinct strings. Groups ordered by their
-- lowest id, each { index, ids (sorted), center (the middle of its
-- hostages) }; groups.key names the whole arrangement.
function Cluster(hostages)
	local sorted, seen = {}, {}
	for i, h in ipairs(hostages) do
		if seen[h.id] then error("hostage " .. h.id .. " is listed twice", 2) end
		seen[h.id] = true
		sorted[i] = h
	end
	sort(sorted, function(a, b) return a.id < b.id end)

	local owner = {}
	local groups = {}
	for _, h in ipairs(sorted) do
		if not owner[h.id] then
			local group = { index = #groups + 1, ids = {}, members = {} }
			groups[#groups + 1] = group
			local queue = { h }
			owner[h.id] = group
			while #queue > 0 do
				local at = remove(queue)
				group.members[#group.members + 1] = at
				for _, other in ipairs(sorted) do
					if not owner[other.id] and Distance(at.pos, other.pos) <= RADIUS then
						owner[other.id] = group
						queue[#queue + 1] = other
					end
				end
			end
		end
	end

	local keys = {}
	for i, group in ipairs(groups) do
		local x, y, z = 0, 0, 0
		for _, m in ipairs(group.members) do
			group.ids[#group.ids + 1] = m.id
			x, y, z = x + m.pos.x, y + m.pos.y, z + (m.pos.z or 0)
		end
		sort(group.ids)
		local n = #group.members
		group.center = { x = x / n, y = y / n, z = z / n }
		group.members = nil
		keys[i] = concat(group.ids, ",")
	end
	groups.key = concat(keys, "|")
	return groups
end

-- The group holding the hostage.
function Of(groups, id)
	for _, group in ipairs(groups) do
		for _, member in ipairs(group.ids) do
			if member == id then return group end
		end
	end
	error("no group holds hostage " .. tostring(id), 2)
end

-- Gives each squad of a job in jobs (role -> true) a group of the groups,
-- team by team: the least taken, the lowest on a tie, and keeps the group a
-- squad has while the groups are the same arrangement (groups.key). Squads
-- of other jobs, and every squad when there are no groups, hold none.
-- fireTeams: features.aiwar.model's, each { team, role }.
function Assign(fireTeams, groups, jobs)
	local taken = {}
	local waiting = {}
	for _, fireTeam in ipairs(fireTeams) do
		if jobs[fireTeam.role] and #groups > 0 then
			if fireTeam.groupKey == groups.key and groups[fireTeam.groupIndex] then
				local counts = taken[fireTeam.team] or {}
				taken[fireTeam.team] = counts
				counts[fireTeam.groupIndex] = (counts[fireTeam.groupIndex] or 0) + 1
			else
				waiting[#waiting + 1] = fireTeam
			end
		else
			fireTeam.groupKey, fireTeam.groupIndex, fireTeam.group = nil, nil, nil
		end
	end
	for _, fireTeam in ipairs(waiting) do
		local counts = taken[fireTeam.team] or {}
		taken[fireTeam.team] = counts
		local best = 1
		for i = 2, #groups do
			if (counts[i] or 0) < (counts[best] or 0) then best = i end
		end
		counts[best] = (counts[best] or 0) + 1
		fireTeam.groupKey, fireTeam.groupIndex = groups.key, best
	end
	for _, fireTeam in ipairs(fireTeams) do
		if fireTeam.groupIndex then fireTeam.group = groups[fireTeam.groupIndex] end
	end
end
