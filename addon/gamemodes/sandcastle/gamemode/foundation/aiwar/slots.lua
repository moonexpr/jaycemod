-- Slots: the places each faction keeps for the soldiers the war drafts (the
-- AI War panel's slot list). A faction's slots are its size: a wave fills
-- its free slots, and a soldier frees its slot when it dies or leaves.
-- While mp_aiwar_team_size is a size, every faction is resized to it; at
-- CUSTOM_SIZE the slots are edited one by one, so the sides may differ (a
-- side alone, for testing). A slot may be pinned: its soldier leads its fire
-- team (LEADER), or never leads while another is in it (MEMBER;
-- foundation.aiwar.squad's Leader).
--
-- A slot is { id, pin (LEADER, MEMBER or nil), holder (its soldier's
-- handle, or nil) }; slots are kept by faction name, as factions trade
-- sides (foundation.aiwar's SwapFactions) and their slots go with them.
local format, ipairs, pairs, remove, setmetatable, sort, tonumber, type, upper =
	string.format, ipairs, pairs, table.remove, setmetatable, table.sort, tonumber, type, string.upper
local floor = math.floor
local Teams = require("foundation.teams")
module(...)

LEADER, MEMBER = "leader", "member"

-- mp_aiwar_team_size's value while the slots are edited one by one.
CUSTOM_SIZE = -1

-- The aiwar_slots event's widths (wetsand/sh_aiwar.lua): slot ids, and the
-- slots a faction may have (foundation.aiwar's TEAM_SIZE_MAX fits).
ID_BITS = 16
COUNT_BITS = 6

-- A saved pin's word: an unpinned slot is saved as NONE.
NONE = "none"
local PIN_OF_WORD = {
	[LEADER] = LEADER,
	[MEMBER] = MEMBER,
	[NONE] = false,
}

Plan = {}
Plan.__index = Plan

function New()
	return setmetatable({
		factions = {}, -- faction name -> its slots, in order
		lastId = 0,
	}, Plan)
end

local function List(plan, faction)
	local list = plan.factions[faction]
	if list == nil then
		list = {}
		plan.factions[faction] = list
	end
	return list
end

-- The faction's slots, in order (the plan's own: read them, change them
-- only through the plan).
function Plan:Slots(faction)
	return List(self, faction)
end

function Plan:Size(faction)
	return #List(self, faction)
end

function Plan:Add(faction, pin)
	self.lastId = self.lastId + 1
	local slot = {
		id = self.lastId,
		pin = pin,
		holder = nil,
	}
	local list = List(self, faction)
	list[#list + 1] = slot
	return slot
end

-- The list holding the slot with this id, its place in it and its faction;
-- nil for an unknown id.
local function Locate(plan, id)
	for faction, list in pairs(plan.factions) do
		for i, slot in ipairs(list) do
			if slot.id == id then return list, i, faction end
		end
	end
	return nil
end

-- The removed slot (its holder is the controller's to remove), or nil.
function Plan:Remove(id)
	local list, i = Locate(self, id)
	if list == nil then return nil end
	return remove(list, i)
end

-- The slot pinned (pin: LEADER, MEMBER or nil), or nil for an unknown id.
function Plan:Pin(id, pin)
	local list, i = Locate(self, id)
	if list == nil then return nil end
	list[i].pin = pin
	return list[i]
end

function Plan:FactionOf(id)
	local _, _, faction = Locate(self, id)
	return faction
end

-- The faction keeps exactly `size` slots: new ones are unpinned; a smaller
-- size drops empty slots from the end first, then held ones from the end.
-- Returns the holders of the slots dropped.
function Plan:Resize(faction, size)
	local list = List(self, faction)
	while #list < size do self:Add(faction, nil) end
	local dropped = {}
	while #list > size do
		local victim = #list
		for i = #list, 1, -1 do
			if list[i].holder == nil then
				victim = i
				break
			end
		end
		local slot = remove(list, victim)
		if slot.holder ~= nil then dropped[#dropped + 1] = slot.holder end
	end
	return dropped
end

-- The first free slot of the faction, now the holder's, or nil when none is free.
function Plan:Fill(faction, holder)
	for _, slot in ipairs(List(self, faction)) do
		if slot.holder == nil then
			slot.holder = holder
			return slot
		end
	end
	return nil
end

function Plan:SlotOf(holder)
	for _, list in pairs(self.factions) do
		for _, slot in ipairs(list) do
			if slot.holder == holder then return slot end
		end
	end
	return nil
end

-- The holder's slot, now free, or nil when it held none.
function Plan:Vacate(holder)
	local slot = self:SlotOf(holder)
	if slot then slot.holder = nil end
	return slot
end

-------------------------------------------------------------------------------
-- Saving: each faction's pins in order, as words

function Plan:Saved()
	local saved = {}
	for faction, list in pairs(self.factions) do
		local words = {}
		for i, slot in ipairs(list) do words[i] = slot.pin or NONE end
		saved[faction] = words
	end
	return saved
end

-- A plan from what Saved gave, its slots empty; or nil and why it is no plan.
function Load(saved)
	if type(saved) ~= "table" then return nil, "not a table of factions" end
	local plan = New()
	for faction, words in pairs(saved) do
		if type(words) ~= "table" then return nil, format("%s: not a list of pins", faction) end
		for i, word in ipairs(words) do
			local pin = PIN_OF_WORD[word]
			if pin == nil then
				return nil, format("%s's slot %d: '%s' is not %s, %s or %s", faction, i, word, LEADER, MEMBER, NONE)
			end
			plan:Add(faction, pin or nil)
		end
	end
	return plan
end

-------------------------------------------------------------------------------
-- The slot list's tree (wetsand/cl_aiwar_slots.lua)

local function LeaderFirst(a, b)
	if a.leads ~= b.leads then return a.leads end
	return a.id < b.id
end

-- A side's slots as the aiwar_slots event gives them ({ id, squad, leads,
-- ... }), as its tree shows them: { squads = { name, slots } in the order
-- first met, each squad's slots leader first then by id, loose = the slots
-- in no squad (empty, or a soldier in none) }.
function Tree(rows)
	local squads, byName, loose = {}, {}, {}
	for _, row in ipairs(rows) do
		if row.squad == "" then
			loose[#loose + 1] = row
		else
			local squad = byName[row.squad]
			if squad == nil then
				squad = {
					name = row.squad,
					slots = {},
				}
				byName[row.squad] = squad
				squads[#squads + 1] = squad
			end
			squad.slots[#squad.slots + 1] = row
		end
	end
	for _, squad in ipairs(squads) do sort(squad.slots, LeaderFirst) end
	return {
		squads = squads,
		loose = loose,
	}
end

-------------------------------------------------------------------------------
-- The commands' words

local TEAM_OF_WORD = {
	RED = Teams.RED,
	BLU = Teams.BLUE,
}

-- RED or BLU, in any case, as a team; nil for anything else.
function ParseTeam(word)
	return TEAM_OF_WORD[upper(word)]
end

-- Slot ids, one a token; or nil and the first token that is none ("" for no tokens).
function ParseIds(tokens)
	if #tokens == 0 then return nil, "" end
	local ids = {}
	for i, token in ipairs(tokens) do
		local id = tonumber(token)
		if id == nil or id < 1 or id ~= floor(id) then return nil, token end
		ids[i] = id
	end
	return ids
end
