-- nextsoldier.senses.vision: what a soldier knows of the enemies it sees,
-- TF2's IVision: seen at once, recognized after a reaction time, remembered
-- where last seen for a while out of sight, and one of them, the most
-- dangerous recognized, its contact.
local T = dofile ("tests/harness.lua")
local Vision = nextsoldier.senses.vision

local REACTION, MEMORY = 0.5, 3
-- How it reads an enemy's motion from its looks (an alpha-beta-gamma filter).
local TRACK = { alpha = 0.7, beta = 0.4, gamma = 0.08 }

local function New ()
	return Vision.New (
		{
			reaction = REACTION,
			memory = MEMORY,
			track = TRACK
		}
	)
end

-- The first enemy in the list is the more dangerous.
local function Ranked (order)
	local rank = {}
	for i, handle in ipairs (order) do rank [handle] = i end
	return function (a, b) return rank [a] < rank [b] end
end
local ANY = Ranked ({ "scout", "heavy" })

local function Kinds (events, handle)
	local kinds = {}
	for _, e in ipairs (events) do
		if e.handle == handle then kinds [#kinds + 1] = e.kind end
	end
	return table.concat (kinds, ",")
end

local HERE, THERE = { x = 0, y = 0, z = 0 }, { x = 400, y = 0, z = 0 }

T.test ("an enemy coming into sight is seen at once and recognized after the reaction time", function ()
	local v = New ()
	local events = v:Update (0, { scout = HERE }, ANY)
	T.eq (Kinds (events, "scout"),   Vision.SIGHT, "seen, no contact yet")
	T.eq (v:Visible ("scout"),       true,         "in sight")
	T.eq (v:Recognized ("scout", 0), false,        "not yet recognized")
	T.eq (v:Contact (),              nil,          "no contact before recognition")
	events = v:Update (REACTION, { scout = HERE }, ANY)
	T.eq (Kinds (events, "scout"),          Vision.CONTACT, "recognized: contact")
	T.eq (v:Recognized ("scout", REACTION), true,           "recognized")
	T.eq (v:Contact (),                     "scout",        "the contact")
end)

T.test ("with no reaction time an enemy is a contact as soon as it is seen", function ()
	local v = Vision.New (
		{
			reaction = 0,
			memory = MEMORY,
			track = TRACK
		}
	)
	local events = v:Update (0, { scout = HERE }, ANY)
	T.eq (Kinds (events, "scout"), Vision.SIGHT .. "," .. Vision.CONTACT, "seen and engaged")
end)

T.test ("out of sight a contact is remembered where last seen, then forgotten", function ()
	local v = New ()
	v:Update (0,        { scout = THERE }, ANY)
	v:Update (REACTION, { scout = THERE }, ANY)
	local events = v:Update (1, {}, ANY)
	T.eq (Kinds (events, "scout"), Vision.LOST_SIGHT, "lost sight, kept as contact")
	T.eq (v:Visible ("scout"),     false,             "not in sight")
	T.eq (v:Contact (),            "scout",           "still the contact")
	T.eq (v:LastKnown ("scout"),   THERE,             "where it was last seen")
	-- last seen at REACTION, the last look it was in
	T.eq (Kinds (v:Update (REACTION + MEMORY - 0.1, {}, ANY), "scout"), "", "still remembered")
	events = v:Update (REACTION + MEMORY, {}, ANY)
	T.eq (Kinds (events, "scout"), Vision.CONTACT_LOST, "forgotten")
	T.eq (v:Contact (),            nil,                 "no contact")
	T.eq (v:LastKnown ("scout"),   nil,                 "nothing known of it")
end)

T.test ("a recognized enemy back in sight before it is forgotten is recognized at once", function ()
	local v = New ()
	v:Update (0,        { scout = HERE }, ANY)
	v:Update (REACTION, { scout = HERE }, ANY)
	v:Update (1,        {},               ANY)
	local events = v:Update (1.1, { scout = THERE }, ANY)
	T.eq (Kinds (events, "scout"),     Vision.SIGHT, "seen again, the same contact")
	T.eq (v:Recognized ("scout", 1.1), true,         "no new reaction time")
	T.eq (v:LastKnown ("scout"),       THERE,        "where it is now")
end)

T.test ("an enemy glimpsed and lost before it was recognized waits the reaction time again", function ()
	local v = New ()
	v:Update (0,   { scout = HERE }, ANY)
	v:Update (0.2, {},               ANY)
	v:Update (0.3, { scout = HERE }, ANY)
	T.eq (v:Recognized ("scout", 0.3 + REACTION - 0.1), false, "the glimpse did not count")
	T.eq (v:Recognized ("scout", 0.3 + REACTION),       true,  "a reaction time from the second sight")
end)

T.test ("a more dangerous recognized enemy becomes the contact; the other stays known", function ()
	local v = New ()
	local danger = Ranked ({ "heavy", "scout" })
	v:Update (0,        { scout = HERE }, danger)
	v:Update (REACTION, { scout = HERE }, danger)
	T.eq (v:Contact (), "scout", "the only one")
	v:Update (1, { scout = HERE, heavy = THERE }, danger)
	T.eq (v:Contact (), "scout", "the heavy is not recognized yet")
	local events = v:Update (1 + REACTION, { scout = HERE, heavy = THERE }, danger)
	T.eq (Kinds (events, "heavy"), Vision.CONTACT, "the heavy is the contact")
	T.eq (Kinds (events, "scout"), "",             "the scout is not lost, only passed over")
	T.eq (v:Contact (),            "heavy",        "the heavy")
	T.eq (v:LastKnown ("scout"),   HERE,           "the scout is still known")
end)

T.test ("a contact in sight is kept over a remembered one out of sight", function ()
	local v = New ()
	local danger = Ranked ({ "heavy", "scout" })
	v:Update (0,        { scout = HERE, heavy = THERE }, danger)
	v:Update (REACTION, { scout = HERE, heavy = THERE }, danger)
	T.eq (v:Contact (), "heavy", "the more dangerous")
	v:Update (1, { scout = HERE }, danger)
	T.eq (v:Contact (), "scout", "the one in sight, while the heavy is out of it")
end)

-- Pursuing (TF2's GetPrimaryKnownThreat with onlyVisibleThreats false): with
-- none in sight, the most dangerous remembered enemy is the contact.
local function Pursuing ()
	return Vision.New (
		{
			reaction = REACTION,
			memory = MEMORY,
			unseen = true,
			track = TRACK
		}
	)
end

T.test ("pursuing, with none in sight the most dangerous remembered enemy is the contact", function ()
	local danger = Ranked ({ "heavy", "scout" })
	for _, case in ipairs ({ { Pursuing (), "heavy" }, { New (), "scout" } }) do
		local v, expected = case [1], case [2]
		v:Update (0,        { scout = HERE, heavy = THERE }, danger)
		v:Update (REACTION, { scout = HERE, heavy = THERE }, danger)
		v:Update (1,        { scout = HERE },                danger)
		T.eq (v:Contact (), "scout", "the one in sight comes first")
		v:Update (1.1, {}, danger)
		T.eq (v:Contact (), expected, "none in sight")
	end
end)

T.test ("pursuing, a contact forgotten (it died) gives way to a remembered enemy at once", function ()
	local v = Pursuing ()
	v:Update (0,        { scout = HERE, heavy = THERE }, ANY)
	v:Update (REACTION, { scout = HERE, heavy = THERE }, ANY)
	v:Update (1,        {},                              ANY)
	T.eq (v:Contact (), "scout", "the more dangerous")
	local events = v:Forget ("scout", ANY)
	T.eq (Kinds (events, "heavy"), Vision.CONTACT, "the heavy, remembered, is the contact")
	T.eq (v:Contact (),            "heavy",        "pursued out of sight")
end)

-- Heard (TF2's OnSound adding a known entity): known where it was heard,
-- not in sight.
T.test ("an enemy heard is known where it was heard, out of sight, and pursued", function ()
	local v = Pursuing ()
	local events = v:Hear (0, "scout", THERE, ANY)
	T.eq (Kinds (events, "scout"), Vision.CONTACT, "a contact, no sight")
	T.eq (v:Visible ("scout"),     false,          "not in sight")
	T.eq (v:LastKnown ("scout"),   THERE,          "where it was heard")
	events = v:Update (0.1, { scout = HERE }, ANY)
	T.eq (Kinds (events, "scout"),     Vision.SIGHT, "seen: the same contact")
	T.eq (v:Recognized ("scout", 0.1), true,         "known to be an enemy, no reaction time")
end)

T.test ("an enemy heard again is remembered from then, where it was heard", function ()
	local v = New ()
	v:Hear (0, "scout", HERE, ANY)
	T.eq (v:Contact (), nil, "not pursuing: heard is no contact")
	v:Hear (MEMORY - 0.5, "scout", THERE, ANY)
	v:Update (MEMORY + 0.1, {}, ANY)
	T.eq (v:LastKnown ("scout"), THERE, "remembered from the second time")
	v:Update (MEMORY - 0.5 + MEMORY, {}, ANY)
	T.eq (v:LastKnown ("scout"), nil, "forgotten a memory after")
end)

T.test ("pruned, every known enemy no longer alive is forgotten, the contact with it", function ()
	local v = Pursuing ()
	v:Update (0,        { scout = HERE, heavy = THERE }, ANY)
	v:Update (REACTION, { scout = HERE, heavy = THERE }, ANY)
	v:Update (1,        {},                              ANY)
	local gone = { scout = true }
	local events = v:Prune (function (handle) return not gone [handle] end, ANY)
	T.eq (Kinds (events, "heavy"),                     Vision.CONTACT, "the heavy, still alive, is pursued")
	T.eq (v:LastKnown ("scout"),                       nil,            "the scout is forgotten")
	T.eq (#v:Prune (function () return true end, ANY), 0,              "all alive: nothing told")
end)

T.test ("a glimpse not recognized is not pursued", function ()
	local v = Pursuing ()
	v:Update (0,   { scout = HERE }, ANY)
	v:Update (0.1, {},               ANY)
	T.eq (v:Contact (), nil, "no contact")
end)

T.test ("an enemy forgotten on purpose (it died) ends the contact", function ()
	local v = New ()
	v:Update (0,        { scout = HERE }, ANY)
	v:Update (REACTION, { scout = HERE }, ANY)
	local events = v:Forget ("scout")
	T.eq (Kinds (events, "scout"), Vision.CONTACT_LOST, "the contact ends")
	T.eq (v:Visible ("scout"),     false,               "not in sight")
	T.eq (#v:Forget ("nobody"),    0,                   "forgetting a stranger tells nothing")
end)

-- Motion: each look reads where an enemy is going, as an
-- alpha-beta-gamma filter does, and Estimate says where it is now.

local LOOK = 0.2

-- An enemy at x = path(t) looked at every LOOK seconds from 0 to seconds.
local function Watch (v, path, seconds, from)
	local t = from or 0
	while t <= seconds + 1e-9 do
		v:Update (t, { scout = { x = path (t), y = 0, z = 0 } }, ANY)
		t = t + LOOK
	end
	return t - LOOK
end

local function Tracking (gains)
	return Vision.New (
		{
			reaction = 0,
			memory = MEMORY,
			track = gains
		}
	)
end

T.test ("an enemy first seen is read as standing still", function ()
	local v = New ()
	v:Update (0, { scout = THERE }, ANY)
	local at, velocity = v:Estimate ("scout", 0.5)
	T.eq (at.x == THERE.x and at.y == THERE.y and at.z == THERE.z, true, "where it was seen")
	T.eq (velocity.x == 0 and velocity.y == 0 and velocity.z == 0, true, "not moving")
end)

T.test ("an enemy moving steadily is read at its speed, and where it will be", function ()
	local SPEED = 250
	local v = Tracking (TRACK)
	local last = Watch (v, function (t) return SPEED * t end, 6)
	local at, velocity = v:Estimate ("scout", last + LOOK / 2)
	T.eq (math.abs (velocity.x - SPEED) < 1,               true, "its speed: " .. velocity.x)
	T.eq (math.abs (at.x - SPEED * (last + LOOK / 2)) < 1, true, "ahead of the last look: " .. at.x)
end)

T.test ("an enemy turning back is read late, then caught up with", function ()
	local SPEED, TURN = 250, 2
	local function Path (t) return t < TURN and SPEED * t or SPEED * (2 * TURN - t) end
	local v = Tracking (TRACK)
	Watch (v, Path, TURN)
	local _, before = v:Estimate ("scout", TURN)
	Watch (v, Path, TURN + LOOK, TURN + LOOK)
	local _, after = v:Estimate ("scout", TURN + LOOK)
	T.eq (after.x > 0 and after.x < before.x, true, "still read as going on, but slower: " .. after.x)
	Watch (v, Path, TURN + 6, TURN + 2 * LOOK)
	local _, settled = v:Estimate ("scout", TURN + 6)
	T.eq (math.abs (settled.x + SPEED) < 1, true, "then read going back: " .. settled.x)
end)

T.test ("an accelerating enemy is followed closely only by an eye that reads acceleration", function ()
	local ACCELERATION = 400
	local function Path (t) return 0.5 * ACCELERATION * t * t end
	local function Miss (gamma)
		local v = Tracking ({ alpha = TRACK.alpha, beta = TRACK.beta, gamma = gamma })
		local last = Watch (v, Path, 6)
		local at = v:Estimate ("scout", last + LOOK)
		return math.abs (at.x - Path (last + LOOK))
	end
	T.eq (Miss (TRACK.gamma) < 1,             true, "reading it: " .. Miss (TRACK.gamma))
	T.eq (Miss (0) > 10 * Miss (TRACK.gamma), true, "blind to it, it falls behind: " .. Miss (0))
end)

T.test ("an enemy back in sight, or heard, is read afresh", function ()
	local v = Tracking (TRACK)
	local last = Watch (v, function (t) return 250 * t end, 2)
	v:Update (last + LOOK,     {},                ANY)
	v:Update (last + 2 * LOOK, { scout = THERE }, ANY)
	local _, back = v:Estimate ("scout", last + 2 * LOOK)
	T.eq (back.x, 0, "back in sight: still")
	Watch (v, function (t) return 250 * t end, last + 4, last + 3 * LOOK)
	v:Hear (last + 5, "scout", HERE, ANY)
	local at, heard = v:Estimate ("scout", last + 6)
	T.eq (heard.x == 0 and at.x == HERE.x, true, "heard: still, where it was heard")
end)

T.finish ()
