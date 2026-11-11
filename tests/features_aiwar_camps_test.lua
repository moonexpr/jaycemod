-- features.aiwar.camps: a spot an enemy kills from again and again, its CAMP_KILLS kills within
-- CAMP_WINDOW of each other, each from within CAMP_REACH of the spot, is a camp, named once.
local T = dofile ("tests/harness.lua")
local Camps = T.require ("features.aiwar.camps")

local RED, BLUE = 2, 3
local SPOT = { x = 100, y = 200, z = 0 }

local function Near (dx) return { x = SPOT.x + dx, y = SPOT.y, z = SPOT.z } end

T.test ("a killer's CAMP_KILLS kills from one spot within the window make a camp there, the victims' to know", function ()
	local camps = Camps.New ()
	local found
	for i = 1, Camps.CAMP_KILLS do
		found = camps:Kill ("sentry", BLUE, RED, Near (i), i)
		if i < Camps.CAMP_KILLS then T.eq (found, nil, "not yet: " .. i) end
	end
	T.eq (found ~= nil, true, "a camp")
	T.eq (found.team,   RED,  "the victims' team")
	T.near (found.pos.x, SPOT.x + (Camps.CAMP_KILLS + 1) / 2, 0.001, "where it killed from: x")
	T.eq (found.pos.y, SPOT.y, "where it killed from: y")
end)

T.test ("a camp is named once; more kills from it name nothing new", function ()
	local camps = Camps.New ()
	for i = 1, Camps.CAMP_KILLS do camps:Kill ("sniper", BLUE, RED, SPOT, i) end
	T.eq (camps:Kill ("sniper", BLUE, RED, SPOT, Camps.CAMP_KILLS + 1), nil, "already named")
end)

T.test ("kills spread in time or place, or by different killers, make no camp", function ()
	local slow = Camps.New ()
	for i = 1, Camps.CAMP_KILLS do
		T.eq (slow:Kill ("a", BLUE, RED, SPOT, i * Camps.CAMP_WINDOW), nil, "too far apart in time: " .. i)
	end
	local roaming = Camps.New ()
	for i = 1, Camps.CAMP_KILLS do
		T.eq (roaming:Kill ("a", BLUE, RED, Near (i * Camps.CAMP_REACH * 2), i), nil, "too far apart: " .. i)
	end
	local many = Camps.New ()
	for i = 1, Camps.CAMP_KILLS do
		T.eq (many:Kill ("killer" .. i, BLUE, RED, SPOT, i), nil, "each its own killer: " .. i)
	end
end)

T.test ("a killer's own team is no victim of its camp", function ()
	local camps = Camps.New ()
	for i = 1, Camps.CAMP_KILLS do
		T.eq (camps:Kill ("traitor", BLUE, BLUE, SPOT, i), nil, "a teammate: " .. i)
	end
end)

T.test ("the camp rules are defined", function ()
	T.defined (Camps.CAMP_KILLS,  "CAMP_KILLS")
	T.defined (Camps.CAMP_WINDOW, "CAMP_WINDOW")
	T.defined (Camps.CAMP_REACH,  "CAMP_REACH")
end)

T.finish ()
