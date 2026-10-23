-- features.aiwar.health: when a soldier in cover leaves it for a health
-- kit (CTFBotGetHealth's urgency and search range, and how far the enemy
-- has drawn off), and which kit.
local T = dofile("tests/harness.lua")
local Health = T.require("features.aiwar.health")

local function P(x, y) return { x = x, y = y, z = 0 } end

T.test("urgency is 0 at TF2's ok health, 1 at its critical health or on fire", function()
	T.eq(Health.Urgency(Health.OK, false), 0, "ok")
	T.eq(Health.Urgency(1, false), 0, "full")
	T.eq(Health.Urgency(Health.CRITICAL, false), 1, "critical")
	T.eq(Health.Urgency(0.05, false), 1, "below critical")
	T.near(Health.Urgency((Health.OK + Health.CRITICAL) / 2, false), 0.5, 1e-9, "halfway")
	T.eq(Health.Urgency(0.9, true), 1, "on fire")
end)

T.test("the more urgent, the farther it goes for health", function()
	T.eq(Health.SearchRange(0), Health.NEAR_RANGE, "barely hurt: near")
	T.eq(Health.SearchRange(1), Health.FAR_RANGE, "critical: far")
end)

T.test("safety grows as the enemy draws off or falls quiet", function()
	T.eq(Health.Safety(nil, 0), 1, "no known threat")
	T.eq(Health.Safety(Health.THREAT_NEAR, 0), 0, "close and loud")
	T.eq(Health.Safety(Health.THREAT_FAR, 0), 1, "far off")
	T.near(Health.Safety((Health.THREAT_NEAR + Health.THREAT_FAR) / 2, 0), 0.5, 1e-9, "halfway off")
	T.eq(Health.Safety(Health.THREAT_NEAR, Health.QUIET_TIME), 1, "close but quiet long enough")
end)

T.test("it leaves cover when urgency and safety together make 1", function()
	T.eq(Health.Leaves(1, 0), true, "critical: whatever the danger")
	T.eq(Health.Leaves(0, 1), true, "barely hurt: only when safe")
	T.eq(Health.Leaves(0.5, 0.4), false, "half hurt, not safe enough")
	T.eq(Health.Leaves(0.5, 0.5), true, "half and half")
end)

T.test("the kit is the nearest within the search range", function()
	local kits = { { pos = P(1500, 0) }, { pos = P(300, 0) }, { pos = P(5000, 0) } }
	T.eq(Health.PickKit(kits, P(0, 0), 1000), kits[2], "the nearest")
	T.eq(Health.PickKit({ kits[1], kits[3] }, P(0, 0), 1000), nil, "none in range")
	T.eq(Health.PickKit({}, P(0, 0), 2000), nil, "none at all")
end)

T.finish()
