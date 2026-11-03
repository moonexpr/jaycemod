-- What failed route searches learned: a search that runs out of areas
-- before the goal (failed, not cut off by its cap) has walked every area
-- its start can reach, so that region is exactly where its start leads. A
-- later request starting inside the region, with its goal outside, is out of
-- reach too, and is answered without a search (docs/ns-performance-
-- baseline.md: failed searches did nine tenths of the work after a round
-- restart, a few starts asked for many goals beyond them).
--
-- Reachability rests on less than a route's cost: the strategy's
-- impassable steps, and what the asker's rules refuse. A penalty only
-- prices a step, and a bot's spread of routes only weighs one, so neither
-- is in the key: the strategy and limits, the crossable rule, whether the
-- search goes through the blockers, the team and the round's winner (spawn
-- rooms). What the asker refuses (an area closed to it, a link it cannot
-- cross) changes (a cart moving, a door shutting), so a region proves a goal
-- out of reach only while every refusal at its edge still holds for the
-- asker; one opened since, and a search runs as before. That check catches
-- every blocker change, which only opens or closes areas; a change to the
-- mesh's links does not show in a refusal, so a region is dropped once one
-- has happened since its generation (the blockers' count when its search
-- ran).
--
--   New{ clock, term, capacity } -> a memo (an expiring cache), keys -> its
--     newest REGIONS_PER_KEY regions
--   memo:Key(request) -> the key; request = { strategy, limits, bot,
--     ignoreBlockers, crossable }, as features/npc/sv_routes.lua takes it
--   memo:Learn(key, region, generation)
--   memo:Unreachable(key, start, goal, open(id), crossable(fromId, toId),
--     generation, known(since)) -> a region holding start and not goal whose
--     edges still hold, or nil; known(since): whether every change since that
--     generation opened or closed areas (the blockers' log), so the edges'
--     check covers it
--   Region(start, parents (id -> the id it was reached from), refused (id ->
--     true: closed to the asker), uncrossable (from -> to -> true)) -> a
--     region: region[id] (whether it holds the area), region:Size() (#region
--     where # honours __len), region:RouteTo(id) (its search's way there from
--     its start), region:Nearest(goalPos, center(id)) (the area nearest the
--     goal: where a search for it would have come closest)
local Cache = cache.base
local Class = core.class
local Expiring = cache.expiring
local Geometry = math.geometry
local concat, ipairs, pairs, rawget, setmetatable, type = table.concat, ipairs, pairs, rawget, setmetatable, type
module(...)

REGIONS_PER_KEY = 4

local YES, NO = 1, 0

-- Strategies, limits and crossable rules by number, so a key is a short
-- string of numbers.
local numbers = setmetatable({}, { __mode = "k" })
local counted = 0

local function Number(value)
	if value == nil then return NO end
	local n = numbers[value]
	if not n then
		counted = counted + 1
		n = counted
		numbers[value] = n
	end
	return n
end

-- Regions ----------------------------------------------------------------------------

local function Size(region)
	return region.size
end

RegionClass = Class.Extend(nil, {
	__index = function(region, key)
		if type(key) == "number" then return rawget(region, "reached")[key] == true end
		return RegionClass[key]
	end,
	__len = Size,
	__tostring = function(region) return "region from " .. region.start .. ": " .. region.size .. " areas" end,
	Size = Size,
	RouteTo = function(self, id)
		local parents, reversed = self.parents, { id }
		while parents[id] ~= nil do
			id = parents[id]
			reversed[#reversed + 1] = id
		end
		local route = {}
		for i = #reversed, 1, -1 do route[#route + 1] = reversed[i] end
		return route
	end,
	Nearest = function(self, goalPos, center)
		local best, bestDistance
		for id in pairs(self.reached) do
			local d = Geometry.Distance(center(id), goalPos)
			if not bestDistance or d < bestDistance or (d == bestDistance and id < best) then best, bestDistance = id, d end
		end
		return best
	end,
})

function Region(start, parents, refused, uncrossable)
	local reached, size = { [start] = true }, 1
	for id in pairs(parents) do
		if not reached[id] then
			reached[id] = true
			size = size + 1
		end
	end
	return Class.New(RegionClass, {
		start = start,
		parents = parents,
		refused = refused,
		uncrossable = uncrossable,
		reached = reached,
		size = size,
	})
end

-- Whether every refusal at the region's edge still holds for the asker.
local function Holds(region, open, crossable)
	for id in pairs(region.refused) do
		if open(id) then return false end
	end
	for from, tos in pairs(region.uncrossable) do
		for to in pairs(tos) do
			if crossable(from, to) then return false end
		end
	end
	return true
end

-- The memo ----------------------------------------------------------------------------

local function Now(memo)
	return Cache.State(memo).clock:Now()
end

ReachMemo = Class.Extend(Expiring.Expiring, {
	kind = "reach memo",
	Key = function(self, request)
		local bot = request.bot
		return concat({
			Number(request.strategy),
			Number(request.limits),
			Number(request.crossable),
			request.ignoreBlockers and YES or NO,
			bot.team,
			bot.roundWon and YES or NO,
			bot.winningTeam,
		}, ":")
	end,
	Learn = function(self, key, region, generation)
		region.learnedAt, region.generation = Now(self), generation
		local kept = { region }
		for _, old in ipairs(self:Peek(key) or {}) do
			if #kept < REGIONS_PER_KEY and old.start ~= region.start then kept[#kept + 1] = old end
		end
		self[key] = kept
	end,
	Unreachable = function(self, key, start, goal, open, crossable, generation, known)
		local term, now = Cache.State(self).term, Now(self)
		for _, region in ipairs(self[key] or {}) do
			if now - region.learnedAt <= term and region[start] and not region[goal]
				and (region.generation == generation or known(region.generation))
				and Holds(region, open, crossable) then
				return region
			end
		end
		return nil
	end,
})

function New(options)
	return Class.Construct(ReachMemo, options)
end
