-- What a team knows of the enemy, by room (docs/special-missions-plan.md
-- §2.2), for its special missions: knowledge is earned
-- (docs/aiwar-command.md decision 6), so only what its soldiers saw and
-- suffered, and when. Rooms are wartactics.rooms' ids; subjects are opaque
-- enemy handles; times are the caller's.
--
-- New() -> a team's intel:
--   Sight(room, kind, subject, now): an enemy of kind (SOLDIER, TURRET,
--     MEDIC, DISPENSER, TELEPORTER) seen in a room; it counts where it was
--     seen last, and coming into a room (first seen, or seen elsewhere
--     before) is an arrival there. An unknown kind is our bug.
--   Loss(room, now): one of ours died there.
--   Gone(subject): an enemy killed or destroyed: it counts no more.
--   Guarded(room, now) -> how strongly the enemy holds it: the WEIGHTS of
--     the enemies last seen there within GUARD_MEMORY (support within
--     SUPPORT_MEMORY), and LOSS_WEIGHT for each loss there within
--     GUARD_MEMORY.
--   Traffic(room, now) -> the arrivals there within TRAFFIC_MEMORY: where
--     the enemy passes, where an ambush pays.
--   SupportBases(now) -> { room, strength } for each room where enemy
--     support (a turret, medic, dispenser or teleporter) was last seen
--     within SUPPORT_MEMORY, strongest first (the lower room on a tie).
local error, ipairs, pairs, setmetatable, tostring = error, ipairs, pairs, setmetatable, tostring
local sort = table.sort
module(...)

SOLDIER, TURRET, MEDIC, DISPENSER, TELEPORTER = "soldier", "turret", "medic", "dispenser", "teleporter"
WEIGHTS = { [SOLDIER] = 1, [MEDIC] = 1, [TURRET] = 3, [DISPENSER] = 2, [TELEPORTER] = 1 }
local SUPPORT = { [TURRET] = true, [MEDIC] = true, [DISPENSER] = true, [TELEPORTER] = true }

GUARD_MEMORY, TRAFFIC_MEMORY, SUPPORT_MEMORY = 20, 60, 90
LOSS_WEIGHT = 1

local Intel_ = {}
Intel_.__index = Intel_

function New()
	return setmetatable({ seen = {}, arrivals = {}, losses = {} }, Intel_)
end

local function Push(lists, room, value)
	local list = lists[room]
	if not list then
		list = {}
		lists[room] = list
	end
	list[#list + 1] = value
end

function Intel_:Sight(room, kind, subject, now)
	if not WEIGHTS[kind] then error("no enemy kind " .. tostring(kind), 2) end
	local last = self.seen[subject]
	if not last or last.room ~= room then Push(self.arrivals, room, now) end
	self.seen[subject] = { room = room, kind = kind, at = now }
end

function Intel_:Loss(room, now)
	Push(self.losses, room, now)
end

function Intel_:Gone(subject)
	self.seen[subject] = nil
end

local function Memory(kind)
	return SUPPORT[kind] and SUPPORT_MEMORY or GUARD_MEMORY
end

-- How many of a room's times (appended in order) are within memory; the
-- older ones are dropped, so the lists stay short.
local function Recent(list, now, memory)
	if not list then return 0 end
	local first = 1
	while list[first] and now - list[first] > memory do first = first + 1 end
	if first > 1 then
		local n = #list
		for i = first, n do list[i - first + 1] = list[i] end
		for i = n - first + 2, n do list[i] = nil end
	end
	return #list
end

function Intel_:Guarded(room, now)
	local strength = 0
	for _, sight in pairs(self.seen) do
		if sight.room == room and now - sight.at <= Memory(sight.kind) then strength = strength + WEIGHTS[sight.kind] end
	end
	return strength + LOSS_WEIGHT * Recent(self.losses[room], now, GUARD_MEMORY)
end

function Intel_:Traffic(room, now)
	return Recent(self.arrivals[room], now, TRAFFIC_MEMORY)
end

function Intel_:SupportBases(now)
	local strength = {}
	for _, sight in pairs(self.seen) do
		if SUPPORT[sight.kind] and now - sight.at <= SUPPORT_MEMORY then
			strength[sight.room] = (strength[sight.room] or 0) + WEIGHTS[sight.kind]
		end
	end
	local bases = {}
	for room, s in pairs(strength) do bases[#bases + 1] = { room = room, strength = s } end
	sort(bases, function(a, b)
		if a.strength ~= b.strength then return a.strength > b.strength end
		return a.room < b.room
	end)
	return bases
end
