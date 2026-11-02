-- TF2's per-area nav attributes (tf_nav_area.h's TF_NAV_*), which GMod's
-- nav loader cannot read. .devtools/bin/nav_convert.py writes the ones TF2
-- saves (TF_NAV_PERSISTENT_ATTRIBUTES: sentry and sniper spots, setup gates,
-- one-way doors...) to maps/<map>.tfnav.txt beside the converted mesh: a
-- "tfnav 1" line, then "<area id> <flags>" a line. The converted mesh keeps
-- TF2's area ids, so an id here is the GMod area's GetID().
--
-- Parse(text) reads one, refusing anything else: the file is ours, so a bad
-- one is our bug. None() is the empty set, for a map without one. Both give:
--   mesh:Has(id, name)   whether area id has the attribute
--   mesh:Names(id)       its attribute names, in the order of their bits
--   mesh:Areas(name)     the ids of the areas with it, in id order
-- A name is a key of FLAGS; any other is our bug.
local band, error, ipairs, pairs, setmetatable, sort, tonumber = bit.band, error, ipairs, pairs, setmetatable, table.sort, tonumber
local gmatch, match = string.gmatch, string.match
local Sets = world.sets
module(...)

HEADER = "tfnav 1"

-- The persistent flags, in the order of their bits.
local ORDERED = {
	{ "BLUE_SETUP_GATE", 0x00000800 },
	{ "RED_SETUP_GATE", 0x00001000 },
	{ "BLOCKED_AFTER_POINT_CAPTURE", 0x00002000 },
	{ "BLOCKED_UNTIL_POINT_CAPTURE", 0x00004000 },
	{ "BLUE_ONE_WAY_DOOR", 0x00008000 },
	{ "RED_ONE_WAY_DOOR", 0x00010000 },
	{ "WITH_SECOND_POINT", 0x00020000 },
	{ "WITH_THIRD_POINT", 0x00040000 },
	{ "WITH_FOURTH_POINT", 0x00080000 },
	{ "WITH_FIFTH_POINT", 0x00100000 },
	{ "SNIPER_SPOT", 0x00200000 },
	{ "SENTRY_SPOT", 0x00400000 },
	{ "NO_SPAWNING", 0x02000000 },
	{ "RESCUE_CLOSET", 0x04000000 },
	{ "DOOR_NEVER_BLOCKS", 0x10000000 },
	{ "DOOR_ALWAYS_BLOCKS", 0x20000000 },
	{ "UNBLOCKABLE", 0x40000000 },
}

FLAGS = {}
local names, persistent = {}, 0
for i, entry in ipairs(ORDERED) do
	FLAGS[entry[1]], names[i], persistent = entry[2], entry[1], persistent + entry[2]
end
local NAME = Sets.Named("nav attribute", names)

local Mesh = {}
Mesh.__index = Mesh

local function New(flags)
	return setmetatable({ flags = flags }, Mesh)
end

function Mesh:Has(id, name)
	local flag = FLAGS[NAME:Check(name)]
	return band(self.flags[id] or 0, flag) ~= 0
end

function Mesh:Names(id)
	local flags, found = self.flags[id] or 0, {}
	for _, entry in ipairs(ORDERED) do
		if band(flags, entry[2]) ~= 0 then found[#found + 1] = entry[1] end
	end
	return found
end

function Mesh:Areas(name)
	local flag, ids = FLAGS[NAME:Check(name)], {}
	for id, flags in pairs(self.flags) do
		if band(flags, flag) ~= 0 then ids[#ids + 1] = id end
	end
	sort(ids)
	return ids
end

function None()
	return New({})
end

local function Refuse(lineNumber, line)
	error("nav attributes: line " .. lineNumber .. " is not an area id and its flags: " .. line, 3)
end

function Parse(text)
	local header, body = match(text, "^([^\n]*)\n(.*)$")
	if header ~= HEADER then error("nav attributes: not a sidecar; its first line must be " .. HEADER, 2) end
	local lineNumber, flags = 1, {}
	for line in gmatch(body, "([^\n]*)\n") do
		lineNumber = lineNumber + 1
		local id, value = match(line, "^(%d+) (%d+)$")
		id, value = tonumber(id), tonumber(value)
		if not id or value == 0 or band(value, persistent) ~= value then Refuse(lineNumber, line) end
		flags[id] = value
	end
	return New(flags)
end
