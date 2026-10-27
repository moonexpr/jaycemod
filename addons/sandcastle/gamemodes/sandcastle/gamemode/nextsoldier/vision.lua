-- What a soldier knows of the enemies it sees, as TF2's bots know it
-- (IVision, CKnownEntity): an enemy in sight is seen at once and
-- recognized only after the soldier's reaction time (tf_bot_difficulty's,
-- features.aiwar.marksmanship); once recognized it stays so, remembered
-- where it was last seen, until it has been out of sight for the memory.
-- The most dangerous recognized enemy in sight is the soldier's contact,
-- kept while remembered when none is in sight.
--
-- Its events are the orders' (features.aiwar.orders): the caller tells the
-- soldier's behaviour each one, with the enemy's handle.
local pairs = pairs
local setmetatable = setmetatable
module(...)

SIGHT, LOST_SIGHT = "OnSight", "OnLostSight"
CONTACT, CONTACT_LOST = "OnContact", "OnContactLost"

local Vision = {}
Vision.__index = Vision

-- tuning: { reaction, memory }, in seconds.
function New(tuning)
	return setmetatable({
		reaction = tuning.reaction,
		memory = tuning.memory,
		known = {}, -- handle -> { pos, seenAt, since (in sight from, nil out of it), recognized }
		contact = nil,
	}, Vision)
end

local function Add(events, kind, handle)
	events[#events + 1] = {
		kind = kind,
		handle = handle,
	}
end

function Vision:Visible(handle)
	local entry = self.known[handle]
	return entry ~= nil and entry.since ~= nil
end

function Vision:Recognized(handle, now)
	local entry = self.known[handle]
	if not entry then return false end
	return entry.recognized or (entry.since ~= nil and now - entry.since >= self.reaction)
end

-- Where it was last seen, and when; nil once forgotten.
function Vision:LastKnown(handle)
	local entry = self.known[handle]
	if not entry then return nil end
	return entry.pos, entry.seenAt
end

function Vision:Contact()
	return self.contact
end

-- The contact after this look: the most dangerous (better(a, b): a is) of
-- the recognized enemies in sight; with none in sight, the contact as it
-- was while it is remembered.
local function PickContact(self, better)
	local best
	for handle, entry in pairs(self.known) do
		if entry.since and entry.recognized and (best == nil or better(handle, best)) then best = handle end
	end
	if best then return best end
	if self.contact and self.known[self.contact] then return self.contact end
	return nil
end

local function SetContact(self, contact, events)
	if contact == self.contact then return end
	local old = self.contact
	self.contact = contact
	if contact then
		Add(events, CONTACT, contact)
	else
		Add(events, CONTACT_LOST, old)
	end
end

-- A look at now: seen = handle -> its position, for every enemy in sight.
-- Returns the events, in the order they happened.
function Vision:Update(now, seen, better)
	local events = {}
	for handle, pos in pairs(seen) do
		local entry = self.known[handle]
		if not entry then
			entry = {}
			self.known[handle] = entry
		end
		if not entry.since then
			entry.since = now
			Add(events, SIGHT, handle)
		end
		entry.pos, entry.seenAt = pos, now
		if not entry.recognized and now - entry.since >= self.reaction then entry.recognized = true end
	end
	for handle, entry in pairs(self.known) do
		if not seen[handle] then
			if entry.since then
				Add(events, LOST_SIGHT, handle)
				entry.since = nil
			end
			-- a glimpse not recognized is not remembered: seen again, it waits the reaction time again
			if not entry.recognized or now - entry.seenAt >= self.memory then self.known[handle] = nil end
		end
	end
	SetContact(self, PickContact(self, better), events)
	return events
end

-- Forgets an enemy at once (it died or left); the events, as Update's.
function Vision:Forget(handle)
	local events = {}
	if not self.known[handle] then return events end
	self.known[handle] = nil
	if self.contact == handle then
		-- the next look picks another contact; until then there is none
		SetContact(self, nil, events)
	end
	return events
end
