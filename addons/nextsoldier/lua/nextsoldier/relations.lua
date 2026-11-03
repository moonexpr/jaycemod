-- Whom a soldier fights: its dispositions toward entities and factions,
-- answered when asked, as TF2's INextBot::IsEnemy and IsFriend are, never
-- pushed to every entity on the map as they change (DrGBase's way, about
-- 34 ms a change in the war). Dispositions are the caller's values (GMod's
-- D_HT, D_LI, D_FR, D_NU); priorities are numbers, 0 when none is given.
--
-- New{ default, ally } -> relations: default, the disposition toward
--   anyone nothing else names; ally, toward one sharing a faction with it
-- relations:SetEntity(other, disposition[, priority]) (nil disposition: clear)
-- relations:SetFaction(faction, disposition[, priority]) (likewise)
-- relations:Join(faction), Leave(faction), InFaction(faction), Factions()
--   (sorted)
-- relations:Disposition(other, factionsOf) -> disposition, priority: its own
--   entity disposition when set; else, of its factions (factionsOf(other)
--   -> a list, asked only then), the highest priority faction disposition,
--   a tie to the faction first by name; else the ally disposition when it
--   shares one of them; else the default.
local error, ipairs, pairs, setmetatable, sort, type = error, ipairs, pairs, setmetatable, table.sort, type
module(...)

local Relations = {}
Relations.__index = Relations

function New(spec)
	if type(spec) ~= "table" or spec.default == nil then error("relations need a default disposition", 2) end
	if spec.ally == nil then error("relations need an ally disposition", 2) end
	return setmetatable({
		default = spec.default,
		ally = spec.ally,
		entities = setmetatable({}, { __mode = "k" }),
		factions = {},
		joined = {},
	}, Relations)
end

local function Entry(disposition, priority)
	if disposition == nil then return nil end
	return { disposition = disposition, priority = priority or 0 }
end

function Relations:SetEntity(other, disposition, priority)
	self.entities[other] = Entry(disposition, priority)
end

function Relations:SetFaction(faction, disposition, priority)
	self.factions[faction] = Entry(disposition, priority)
end

function Relations:Join(faction) self.joined[faction] = true end
function Relations:Leave(faction) self.joined[faction] = nil end
function Relations:InFaction(faction) return self.joined[faction] == true end

function Relations:Factions()
	local list = {}
	for faction in pairs(self.joined) do list[#list + 1] = faction end
	sort(list)
	return list
end

function Relations:Disposition(other, factionsOf)
	local own = self.entities[other]
	if own then return own.disposition, own.priority end
	local best, bestName, shared
	for _, faction in ipairs(factionsOf(other)) do
		local entry = self.factions[faction]
		if entry and (best == nil or entry.priority > best.priority
			or (entry.priority == best.priority and faction < bestName)) then
			best, bestName = entry, faction
		end
		if self.joined[faction] then shared = true end
	end
	if best then return best.disposition, best.priority end
	if shared then return self.ally, 0 end
	return self.default, 0
end
