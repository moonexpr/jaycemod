-- features.hostage.hud: the hostage HUD, TF2 Classified's VIP track (its
-- home on the left, the getaway car on the right) with a Civilian's marker
-- for each hostage, as far along as it is from where it was held to the
-- rescue zone, in its state's tint: held, following, rescued (at the car),
-- or killed (where it fell).
local T = dofile("tests/harness.lua")
local Hud = T.require("features.hostage.hud")
local Rescue = T.require("features.hostage.model")

local function P(x) return { x = x, y = 0, z = 0 } end
local HOME, ZONE = P(0), P(1000)

T.test("a hostage's way along the track: from its home (0) to the zone (1)", function()
	T.eq(Hud.Progress(HOME, HOME, ZONE), 0, "at home")
	T.eq(Hud.Progress(P(250), HOME, ZONE), 0.75 - 0.5, "a quarter of the way")
	T.eq(Hud.Progress(ZONE, HOME, ZONE), 1, "at the zone")
	T.eq(Hud.Progress(P(-500), HOME, ZONE), 0, "farther than home: home")
	T.eq(Hud.Progress(P(5), P(0), P(0)), 1, "a home in the zone: there")
end)

T.test("each state has its tint; a rescued hostage sits at the car", function()
	local markers = Hud.Markers({
		{ state = Rescue.HELD, progress = 0 },
		{ state = Rescue.FOLLOWING, progress = 0.4 },
		{ state = Rescue.RESCUED, progress = 0.9 },
		{ state = Rescue.KILLED, progress = 0.3 },
	})
	local by = {}
	for _, m in ipairs(markers) do by[m.tint] = m end
	T.eq(by[Hud.HELD].at, 0, "held, at home")
	T.eq(by[Hud.FOLLOWING].at, 0.4, "following, where it is")
	T.eq(by[Hud.RESCUED].at, 1, "rescued, at the car")
	T.eq(by[Hud.KILLED].at, 0.3, "killed, where it fell")
end)

T.test("the markers furthest along are drawn last, on top", function()
	local markers = Hud.Markers({ { state = Rescue.FOLLOWING, progress = 0.8 }, { state = Rescue.HELD, progress = 0.1 } })
	T.eq(markers[1].at, 0.1, "the nearer home first")
	T.eq(markers[2].at, 0.8, "the furthest last")
end)

T.test("the tally: rescued of all", function()
	T.eq(Hud.Tally({ { state = Rescue.RESCUED }, { state = Rescue.HELD }, { state = Rescue.KILLED } }), "1/3", "one of three")
end)

T.finish()
