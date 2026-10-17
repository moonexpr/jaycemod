-- The AI war's reserve: drafted soldiers that fell and lie dormant until a
-- respawn wave revives them, instead of the wave spawning new ones. Only the
-- respawn system's own soldiers are kept, and only while waves run; an
-- admin's or a player's soldier dies as it always has.
--
-- Bodies are handles (the controller's entities), kept by team and class,
-- and a wave takes the oldest of the class it drafts.
local huge, ipairs, pairs, remove, setmetatable = math.huge, ipairs, pairs, table.remove, setmetatable
module(...)

-- Whether a fallen soldier is kept: revives on (enabled), drafted by the
-- respawn system, and a next wave due (waveLength, seconds; huge when
-- respawns are stopped).
function Keeps(enabled, drafted, waveLength)
	return enabled and drafted and waveLength < huge
end

local Reserve = {}
Reserve.__index = Reserve

function New()
	return setmetatable({
		byTeam = {}, -- team -> class -> handles, oldest first
		kept = {}, -- handle -> true
	}, Reserve)
end

function Reserve:Keep(handle, team, class)
	if self.kept[handle] then return end
	self.kept[handle] = true
	local classes = self.byTeam[team] or {}
	self.byTeam[team] = classes
	local list = classes[class] or {}
	classes[class] = list
	list[#list + 1] = handle
end

-- The oldest kept body of the team and class, no longer kept, or nil.
function Reserve:Take(team, class)
	local list = self.byTeam[team] and self.byTeam[team][class]
	while list and #list > 0 do
		local handle = remove(list, 1)
		if self.kept[handle] then
			self.kept[handle] = nil
			return handle
		end
	end
	return nil
end

-- A kept body that is gone (removed by the map, an admin or a cleanup).
function Reserve:Forget(handle)
	self.kept[handle] = nil
end

function Reserve:Count(team)
	local n = 0
	for _, list in pairs(self.byTeam[team] or {}) do
		for _, handle in ipairs(list) do
			if self.kept[handle] then n = n + 1 end
		end
	end
	return n
end

-- Every kept body, which the reserve no longer keeps.
function Reserve:Drain()
	local drained = {}
	for handle in pairs(self.kept) do drained[#drained + 1] = handle end
	self.byTeam, self.kept = {}, {}
	return drained
end
