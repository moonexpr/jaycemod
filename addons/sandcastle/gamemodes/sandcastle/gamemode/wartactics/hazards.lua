-- The nav areas that keep forcing the war's soldiers to respawn: a soldier
-- dead to the world (a fall, a pit, a trigger; not an enemy's push, which
-- kill credit gives the enemy) or recovered back to its spawn is laid on
-- the last area it stood on, and an area that has done so THRESHOLD times
-- is disabled: its routes keep out of it (the caller closes it, unless it
-- is a spawn room's or blocked already). The hazards are kept across maps
-- (Encode, Decode) until someone inspects the areas and clears them; and
-- when closing them cuts a team's spawns off from the objective it fights
-- for (Separated), the area is a keystone, the only way through: the caller
-- spares it (Spare), open again and never disabled after, so the map stays
-- playable.
--
-- An entry: { id, count, causes (cause -> count), where ({ x, y, z }: the
-- area's centre when it was first laid on it, to know it again on a mesh
-- made since), disabled, spared }.
local error, ipairs, pairs, setmetatable, sort, tostring = error, ipairs, pairs, setmetatable, table.sort, tostring
module(...)

THRESHOLD = 2
VERSION = 1

-- Why a soldier had to respawn.
FELL = "fell" -- dead to the world, by nobody's hand
RECOVERED = "recovered" -- stranded or off the mesh, put back at its spawn
local CAUSES = { [FELL] = true, [RECOVERED] = true }

local Hazards = {}
Hazards.__index = Hazards

function New()
	return setmetatable({ areas = {} }, Hazards)
end

-- A soldier forced to respawn by area id (cause, the area's centre where):
-- whether this disables the area now.
function Hazards:Record(id, cause, where)
	if not CAUSES[cause] then error("unknown hazard cause " .. tostring(cause), 2) end
	local entry = self.areas[id]
	if not entry then
		entry = { id = id, count = 0, causes = {}, where = { x = where.x, y = where.y, z = where.z }, disabled = false }
		self.areas[id] = entry
	end
	entry.count = entry.count + 1
	entry.causes[cause] = (entry.causes[cause] or 0) + 1
	if entry.disabled or entry.spared or entry.count < THRESHOLD then return false end
	entry.disabled = true
	return true
end

-- A keystone: open again, and never disabled after. Whether it was laid on.
function Hazards:Spare(id)
	local entry = self.areas[id]
	if not entry then return false end
	entry.disabled, entry.spared = false, true
	return true
end

function Hazards:IsDisabled(id)
	local entry = self.areas[id]
	return entry ~= nil and entry.disabled
end

-- The disabled areas, id -> true, a set of the caller's own.
function Hazards:Disabled()
	local set = {}
	for id, entry in pairs(self.areas) do
		if entry.disabled then set[id] = true end
	end
	return set
end

-- Every area laid on, in id order.
function Hazards:Entries()
	local list = {}
	for _, entry in pairs(self.areas) do list[#list + 1] = entry end
	sort(list, function(a, b) return a.id < b.id end)
	return list
end

-- An area inspected: forgotten, open again, counted afresh. Whether it was known.
function Hazards:Clear(id)
	if not self.areas[id] then return false end
	self.areas[id] = nil
	return true
end

function Hazards:ClearAll()
	self.areas = {}
end

-- The hazards as plain data, to save.
function Encode(hazards)
	local areas = {}
	for i, entry in ipairs(hazards:Entries()) do
		local causes = {}
		for cause, count in pairs(entry.causes) do causes[cause] = count end
		areas[i] = { id = entry.id, count = entry.count, causes = causes, where = entry.where, disabled = entry.disabled, spared = entry.spared }
	end
	return { version = VERSION, areas = areas }
end

-- Hazards from what Encode saved; another version is refused.
function Decode(data)
	if data.version ~= VERSION then error("nav hazards of version " .. tostring(data.version) .. ", not " .. VERSION, 2) end
	local hazards = New()
	for _, saved in ipairs(data.areas) do
		local causes = {}
		for cause, count in pairs(saved.causes) do
			if not CAUSES[cause] then error("unknown hazard cause " .. tostring(cause), 2) end
			causes[cause] = count
		end
		hazards.areas[saved.id] = {
			id = saved.id,
			count = saved.count,
			causes = causes,
			where = { x = saved.where.x, y = saved.where.y, z = saved.where.z },
			disabled = saved.disabled == true,
			spared = saved.spared == true,
		}
	end
	return hazards
end

-- Whether the war is separated: fronts, { team, reaches } for each team that
-- fights for an objective, reaches whether its spawns reach it with the
-- disabled areas closed. One team cut off is enough.
function Separated(fronts)
	for _, front in ipairs(fronts) do
		if not front.reaches then return true end
	end
	return false
end
