-- games.nextsoldier.vision: what a soldier knows of the enemies it sees,
-- TF2's IVision: seen at once, recognized after a reaction time, remembered
-- where last seen for a while out of sight, and one of them, the most
-- dangerous recognized, its contact.
local T = dofile("tests/harness.lua")
local Vision = nextsoldier.vision

local REACTION, MEMORY = 0.5, 3

local function New()
	return Vision.New({
		reaction = REACTION,
		memory = MEMORY,
	})
end

-- The first enemy in the list is the more dangerous.
local function Ranked(order)
	local rank = {}
	for i, handle in ipairs(order) do rank[handle] = i end
	return function(a, b) return rank[a] < rank[b] end
end
local ANY = Ranked({ "scout", "heavy" })

local function Kinds(events, handle)
	local kinds = {}
	for _, e in ipairs(events) do
		if e.handle == handle then kinds[#kinds + 1] = e.kind end
	end
	return table.concat(kinds, ",")
end

local HERE, THERE = { x = 0, y = 0, z = 0 }, { x = 400, y = 0, z = 0 }

T.test("an enemy coming into sight is seen at once and recognized after the reaction time", function()
	local v = New()
	local events = v:Update(0, { scout = HERE }, ANY)
	T.eq(Kinds(events, "scout"), Vision.SIGHT, "seen, no contact yet")
	T.eq(v:Visible("scout"), true, "in sight")
	T.eq(v:Recognized("scout", 0), false, "not yet recognized")
	T.eq(v:Contact(), nil, "no contact before recognition")
	events = v:Update(REACTION, { scout = HERE }, ANY)
	T.eq(Kinds(events, "scout"), Vision.CONTACT, "recognized: contact")
	T.eq(v:Recognized("scout", REACTION), true, "recognized")
	T.eq(v:Contact(), "scout", "the contact")
end)

T.test("with no reaction time an enemy is a contact as soon as it is seen", function()
	local v = Vision.New({
		reaction = 0,
		memory = MEMORY,
	})
	local events = v:Update(0, { scout = HERE }, ANY)
	T.eq(Kinds(events, "scout"), Vision.SIGHT .. "," .. Vision.CONTACT, "seen and engaged")
end)

T.test("out of sight a contact is remembered where last seen, then forgotten", function()
	local v = New()
	v:Update(0, { scout = THERE }, ANY)
	v:Update(REACTION, { scout = THERE }, ANY)
	local events = v:Update(1, {}, ANY)
	T.eq(Kinds(events, "scout"), Vision.LOST_SIGHT, "lost sight, kept as contact")
	T.eq(v:Visible("scout"), false, "not in sight")
	T.eq(v:Contact(), "scout", "still the contact")
	T.eq(v:LastKnown("scout"), THERE, "where it was last seen")
	-- last seen at REACTION, the last look it was in
	T.eq(Kinds(v:Update(REACTION + MEMORY - 0.1, {}, ANY), "scout"), "", "still remembered")
	events = v:Update(REACTION + MEMORY, {}, ANY)
	T.eq(Kinds(events, "scout"), Vision.CONTACT_LOST, "forgotten")
	T.eq(v:Contact(), nil, "no contact")
	T.eq(v:LastKnown("scout"), nil, "nothing known of it")
end)

T.test("a recognized enemy back in sight before it is forgotten is recognized at once", function()
	local v = New()
	v:Update(0, { scout = HERE }, ANY)
	v:Update(REACTION, { scout = HERE }, ANY)
	v:Update(1, {}, ANY)
	local events = v:Update(1.1, { scout = THERE }, ANY)
	T.eq(Kinds(events, "scout"), Vision.SIGHT, "seen again, the same contact")
	T.eq(v:Recognized("scout", 1.1), true, "no new reaction time")
	T.eq(v:LastKnown("scout"), THERE, "where it is now")
end)

T.test("an enemy glimpsed and lost before it was recognized waits the reaction time again", function()
	local v = New()
	v:Update(0, { scout = HERE }, ANY)
	v:Update(0.2, {}, ANY)
	v:Update(0.3, { scout = HERE }, ANY)
	T.eq(v:Recognized("scout", 0.3 + REACTION - 0.1), false, "the glimpse did not count")
	T.eq(v:Recognized("scout", 0.3 + REACTION), true, "a reaction time from the second sight")
end)

T.test("a more dangerous recognized enemy becomes the contact; the other stays known", function()
	local v = New()
	local danger = Ranked({ "heavy", "scout" })
	v:Update(0, { scout = HERE }, danger)
	v:Update(REACTION, { scout = HERE }, danger)
	T.eq(v:Contact(), "scout", "the only one")
	v:Update(1, { scout = HERE, heavy = THERE }, danger)
	T.eq(v:Contact(), "scout", "the heavy is not recognized yet")
	local events = v:Update(1 + REACTION, { scout = HERE, heavy = THERE }, danger)
	T.eq(Kinds(events, "heavy"), Vision.CONTACT, "the heavy is the contact")
	T.eq(Kinds(events, "scout"), "", "the scout is not lost, only passed over")
	T.eq(v:Contact(), "heavy", "the heavy")
	T.eq(v:LastKnown("scout"), HERE, "the scout is still known")
end)

T.test("a contact in sight is kept over a remembered one out of sight", function()
	local v = New()
	local danger = Ranked({ "heavy", "scout" })
	v:Update(0, { scout = HERE, heavy = THERE }, danger)
	v:Update(REACTION, { scout = HERE, heavy = THERE }, danger)
	T.eq(v:Contact(), "heavy", "the more dangerous")
	v:Update(1, { scout = HERE }, danger)
	T.eq(v:Contact(), "scout", "the one in sight, while the heavy is out of it")
end)

T.test("an enemy forgotten on purpose (it died) ends the contact", function()
	local v = New()
	v:Update(0, { scout = HERE }, ANY)
	v:Update(REACTION, { scout = HERE }, ANY)
	local events = v:Forget("scout")
	T.eq(Kinds(events, "scout"), Vision.CONTACT_LOST, "the contact ends")
	T.eq(v:Visible("scout"), false, "not in sight")
	T.eq(#v:Forget("nobody"), 0, "forgetting a stranger tells nothing")
end)

T.finish()
