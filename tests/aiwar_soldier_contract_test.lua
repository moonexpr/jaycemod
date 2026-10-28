-- The AI war controller (features/aiwar's server realm) and its soldier entities
-- (ws/sh_war_soldier.lua) agree on the fields the controller sets on a
-- soldier to steer it: each one the controller writes (self.ent.X = ...)
-- the soldier reads (self.X). A field written under one name and read under
-- another leaves the soldier ignoring it (a gait it never hears walks).
local T = dofile("tests/harness.lua")

local ROOT = T.ROOT

local function ReadFile(path)
	local f = assert(io.open(path, "r"))
	local text = f:read("*a")
	f:close()
	return text
end

local controller = T.RealmSource("aiwar", "sv")
local soldier = ReadFile(ROOT .. "ws/sh_war_soldier.lua")

T.test("the soldier reads every steering field the controller sets on it", function()
	local count = 0
	for field in controller:gmatch("self%.ent%.([%w_]+)%s*=[^=]") do
		count = count + 1
		T.eq(soldier:find("self%." .. field .. "[^%w_]") ~= nil, true, field .. " is read by the soldier")
	end
	T.eq(count > 0, true, "the controller sets some")
end)

T.finish()
