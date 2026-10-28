-- Part of the AI war controller (sv.lua): the slot plan, sizes, pins, and syncing them to viewers.
local Controller, Map = ...
local AiWar = WS.require("features.aiwar.model")
local Squad = wartactics.squad
local Slots = WS.require("features.aiwar.slots")
local Scenario = WS.require("features.aiwar.scenario")
local RED, BLUE = Map.RED, Map.BLUE
local TeamSize = Map.TeamSize

-- Slots (features.aiwar.slots) -------------------------------------------------------
-- Each faction's slots are its size; while mp_aiwar_team_size is a size,
-- every faction is resized to it. The AI War panel's slot list edits them
-- (mp_aiwar_slots_*, ws/sh_aiwar.lua), which turns the team size to
-- Slots.CUSTOM_SIZE, and shows them to the admins who asked (game_aiwar_slots).

local SLOT_SYNC_INTERVAL = 0.5

-- The slot list, read from its store the first time; a stored list that is
-- none is said in the server console and a new one begun.
function Controller:SlotPlan()
	if self.slots then return self.slots end
	local saved, plan, why = self.slotStore:Read(), nil, nil
	if saved ~= nil then plan, why = Slots.Load(saved) end
	if why then print("AI war: the saved slot list is unusable (" .. why .. "); starting a new one") end
	self.slots = plan or Slots.New()
	return self.slots
end

-- The faction fighting for team: the war's, as factions trade sides; with
-- no war, the one that starts on it (its home faction).
function Controller:Faction(team)
	return self.war and self.war:Faction(team) or AiWar.HomeFaction(team)
end

function Controller:FactionName(team)
	return self:Faction(team).name
end

-- A slot's soldier leaves with its slot: an NPC is removed, a bot player
-- kicked (a player is never Removed).
local function Dismiss(ent)
	if ent:IsPlayer() then ent:Kick("AI war slot removed") else ent:Remove() end
end

-- At a team size each faction is resized to its side's share of it (the
-- scenario's TeamSizes: MvM's invaders outnumber the defenders), and the
-- soldiers whose slots go leave. Returns whether a faction's size changed.
function Controller:ResizeSlots(size)
	local plan, changed = self:SlotPlan(), false
	local sizes = (self.scenario or Scenario.Scenario):TeamSizes(size)
	for _, team in ipairs({ RED, BLUE }) do
		local faction = self:FactionName(team)
		local before = plan:Size(faction)
		for _, ent in ipairs(plan:Resize(faction, sizes[team])) do Dismiss(ent) end
		changed = changed or plan:Size(faction) ~= before
	end
	return changed
end

-- Each team's size (for the war's waves): its faction's slots.
function Controller:Sizes()
	local plan, size = self:SlotPlan(), TeamSize()
	if size ~= Slots.CUSTOM_SIZE and self:ResizeSlots(size) then self.slotStore:Write(plan:Saved()) end
	local sizes = {}
	for _, team in ipairs({ RED, BLUE }) do sizes[team] = plan:Size(self:FactionName(team)) end
	return sizes
end

-- From the first edit, the slots are edited one by one: each faction keeps
-- the slots it has at the team size, and the team size says so.
function Controller:CustomSlots()
	local size = TeamSize()
	if size == Slots.CUSTOM_SIZE then return end
	self:ResizeSlots(size)
	GetConVar("mp_aiwar_team_size"):SetInt(Slots.CUSTOM_SIZE)
end

-- After an edit: kept, and shown at once.
function Controller:SlotsChanged()
	self.slotStore:Write(self.slots:Saved())
	self:SyncSlots(true)
end

-- The side's faction keeps `count` slots (the panel's slider); the
-- soldiers of slots dropped leave, slots added are filled at once. Returns
-- the lines to tell whoever asked.
function Controller:SetSlotCount(team, count)
	self:CustomSlots()
	local faction = self:FactionName(team)
	local before = self.slots:Size(faction)
	for _, ent in ipairs(self.slots:Resize(faction, count)) do Dismiss(ent) end
	if self.war and count > before then self.war:CallWave(team) end
	self:SlotsChanged()
	return { string.format("mp_aiwar_slots_size: the %s (%s) keep %d slots", faction, WS.TeamName[team], count) }
end

-- The slots go, and their soldiers with them (the slot list's Remove).
function Controller:RemoveSlots(ids)
	self:CustomSlots()
	local lines = {}
	for _, id in ipairs(ids) do
		local slot = self.slots:Remove(id)
		if slot == nil then
			lines[#lines + 1] = string.format("mp_aiwar_slots_remove: no slot %d", id)
		else
			if slot.holder ~= nil then Dismiss(slot.holder) end
			lines[#lines + 1] = string.format("mp_aiwar_slots_remove: slot %d removed", id)
		end
	end
	self:SlotsChanged()
	return lines
end

-- pin: Squad.LEADER, Squad.MEMBER or nil; a slot's soldier takes it at once.
function Controller:PinSlots(command, ids, pin)
	local lines = {}
	for _, id in ipairs(ids) do
		local slot = self:SlotPlan():Pin(id, pin)
		if slot == nil then
			lines[#lines + 1] = string.format("%s: no slot %d", command, id)
		else
			if slot.holder ~= nil then self.war:Member(slot.holder).pin = pin end
			lines[#lines + 1] = string.format("%s: slot %d %s", command, id, pin or "unpinned")
		end
	end
	self:SlotsChanged()
	return lines
end

-- The slot list as the game_aiwar_slots event carries it: each team's faction
-- and its slots in order, with the soldier in each, its job and its fire
-- team, and whether it leads it.
function Controller:SlotFields()
	local plan = self:SlotPlan()
	local teams = {}
	for _, team in ipairs({ RED, BLUE }) do
		local faction = self:FactionName(team)
		local rows = {}
		for i, slot in ipairs(plan:Slots(faction)) do
			local ent = slot.holder
			local member = ent and self.war:Member(ent)
			local fireTeam = member and member.fireTeam
			rows[i] = {
				id = slot.id,
				pin = slot.pin or Slots.NONE,
				index = ent and ent:EntIndex() or 0,
				class = ent and (ent:IsPlayer() and ent:Nick() or ent:GetClass()) or "",
				role = member and member.role or "",
				squad = fireTeam and string.format("%s %d", fireTeam.role, fireTeam.index + 1) or "",
				leads = fireTeam ~= nil and Squad.Leader(fireTeam) == member,
				squad_by_hand = fireTeam ~= nil and fireTeam.manual == true,
				job_by_hand = member ~= nil and member.roleByHand == true,
			}
		end
		teams[#teams + 1] = {
			team = team,
			faction = faction,
			slots = rows,
		}
	end
	return {
		custom = TeamSize() == Slots.CUSTOM_SIZE,
		jobs = self:Jobs(),
		teams = teams,
	}
end

local function Signature(fields)
	local parts = { tostring(fields.custom), table.concat(fields.jobs, ",") }
	for _, entry in ipairs(fields.teams) do
		parts[#parts + 1] = entry.faction
		for _, row in ipairs(entry.slots) do
			parts[#parts + 1] = table.concat({ row.id, row.pin, row.index, row.role, row.squad, tostring(row.leads),
				tostring(row.squad_by_hand), tostring(row.job_by_hand) }, ",")
		end
	end
	return table.concat(parts, "|")
end

-- The admins watching, still here.
function Controller:SlotViewers()
	local list = {}
	for ply in pairs(self.slotViewers) do
		if IsValid(ply) then list[#list + 1] = ply else self.slotViewers[ply] = nil end
	end
	return list
end

-- Sends the viewers the slots when they changed since last sent (now:
-- whatever they are), at most every SLOT_SYNC_INTERVAL otherwise.
function Controller:SyncSlots(now)
	if not now and CurTime() < self.nextSlotSync then return end
	self.nextSlotSync = CurTime() + SLOT_SYNC_INTERVAL
	local viewers = self:SlotViewers()
	if #viewers == 0 then return end
	local fields = self:SlotFields()
	local signature = Signature(fields)
	if not now and signature == self.slotSignature then return end
	self.slotSignature = signature
	WS.Events.Fire("game_aiwar_slots", fields, viewers)
end

-- An admin's AI War panel asks for the slots: they are sent now and
-- whenever they change.
function Controller:WatchSlots(ply)
	self.slotViewers[ply] = true
	WS.Events.Fire("game_aiwar_slots", self:SlotFields(), ply)
end

-- The slot list in the console (mp_aiwar_slots_print).
function Controller:SlotReport()
	local lines = { "mp_aiwar_team_size " .. TeamSize() .. (TeamSize() == Slots.CUSTOM_SIZE and " (each side's own slots)" or "") }
	for _, entry in ipairs(self:SlotFields().teams) do
		lines[#lines + 1] = string.format("%s (%s): %d slots", WS.TeamName[entry.team], entry.faction, #entry.slots)
		for _, row in ipairs(entry.slots) do
			local soldier = row.index > 0 and string.format("%s #%d, %s, %s%s", row.class, row.index, row.role, row.squad,
				row.leads and " (leads)" or "") or "empty"
			lines[#lines + 1] = string.format("  %d  %-6s  %s", row.id, row.pin, soldier)
		end
	end
	return lines
end
