-- nextsoldier.locomotion: a hard landing slows a body to IMPACT_SPEED while it
-- recovers, its gait given back after.
local T = dofile ("tests/harness.lua")
local Locomotion = nextsoldier.locomotion

T.defined (Locomotion.IMPACT_RECOVERY, "IMPACT_RECOVERY")

T.test ("a body slowed by an impact is 100 units a second, a player's walk after a fall", function ()
	T.eq (Locomotion.IMPACT_SPEED, 100)
end)

T.test ("no impact leaves its gait alone", function ()
	T.eq (Locomotion.Recovering (250, 10, nil), 250)
end)

T.test ("while it recovers a body is held to IMPACT_SPEED", function ()
	T.eq (Locomotion.Recovering (500, 10, 10.1), Locomotion.IMPACT_SPEED)
end)

T.test ("a gait already slower than that stays as it is", function ()
	T.eq (Locomotion.Recovering (Locomotion.IMPACT_SPEED - 20, 10, 10.1), Locomotion.IMPACT_SPEED - 20)
end)

T.test ("recovered, it has its gait back", function ()
	T.eq (Locomotion.Recovering (500, 10.1, 10.1), 500)
	T.eq (Locomotion.Recovering (500, 11, 10.1), 500)
end)

T.finish ()
