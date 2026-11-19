-- nextsoldier.behavior.battery: off by default, a battery spends and recharges nothing and is
-- never exhausted, so nothing it forces happens (an actor's walk, retreat, slowest look, refused
-- jump and backing off; a squad's muster). On, it is drawn, exhausted, and recovers as before.
local T = dofile ("tests/harness.lua")
local Battery = nextsoldier.behavior.battery

local function Spec () return { capacity = 100, recharge = 10, empty = 0, recovered = 50 } end

T.test ("batteries are off until the operator turns them on", function ()
	T.eq (Battery.Enabled (), false)
end)

T.test ("off, a battery stays full: a draw spends nothing and it is never exhausted", function ()
	local battery = Battery.New (Spec ())
	T.eq (battery:Draw (0, 150), 0,     "nothing spent")
	T.eq (battery:Level (0),     100,   "full")
	T.eq (battery:Exhausted (0), false, "never exhausted")
	battery:Reward (1, 50)
	T.eq (battery:Level (1), 100, "still full")
end)

T.test ("on, a battery is drawn, exhausted and recovers", function ()
	Battery.Enable (true)
	local battery = Battery.New (Spec ())
	T.eq (battery:Draw (0, 150), 100,   "what it had")
	T.eq (battery:Exhausted (0), true,  "spent")
	T.eq (battery:Exhausted (4), true,  "40 of 50 back: not recovered")
	T.eq (battery:Exhausted (5), false, "50 back: recovered")
	battery:Reward (5, 30)
	T.eq (battery:Level (5), 80)
	Battery.Enable (false)
	T.eq (battery:Exhausted (5), false, "off again")
end)

T.finish ()
