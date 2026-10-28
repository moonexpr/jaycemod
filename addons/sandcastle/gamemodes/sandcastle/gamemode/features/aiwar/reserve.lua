-- The AI war's reserve: drafted soldiers that fell and lie dormant until a
-- respawn wave revives them, instead of the wave spawning new ones. Only the
-- respawn system's own soldiers are kept, and only while waves run; an
-- admin's or a player's soldier dies as it always has.
--
-- Bodies are handles (the controller's entities), kept by team and class,
-- and a wave takes the oldest of the class it drafts.
local huge, pairs, setmetatable = math.huge, pairs, setmetatable
local Queue = list.queue
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
		byTeam = {}, -- team -> class -> a queue of handles, oldest first
		kept = {}, -- handle -> true
	}, Reserve)
end

function Reserve:Keep(handle, team, class)
	if self.kept[handle] then return end
	self.kept[handle] = true
	local classes = self.byTeam[team] or {}
	self.byTeam[team] = classes
	local queue = classes[class] or Queue.New()
	classes[class] = queue
	queue:PushBack(handle)
end

-- The oldest kept body of the team and class, no longer kept, or nil.
function Reserve:Take(team, class)
	local queue = self.byTeam[team] and self.byTeam[team][class]
	while queue and queue:Size() > 0 do
		local handle = queue:PopFront()
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
	for _, queue in pairs(self.byTeam[team] or {}) do
		for _, handle in queue:Values() do
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
