-- features.npc.bot_steering: how a bot player's body takes its group's push, the spacing the
-- engine's tree beside its main one works out (native/nextsoldier's group.rs).
local T = dofile ("tests/harness.lua")
local BotSteering = T.require ("features.npc.bot_steering")

local Vec
local Meta =
{
	__add = function (a, b) return Vec (a.x + b.x, a.y + b.y, a.z + b.z) end,
	__sub = function (a, b) return Vec (a.x - b.x, a.y - b.y, a.z - b.z) end
}
Vec = function (x, y, z) return setmetatable ({ x = x, y = y, z = z }, Meta) end

local push = { 0, 0 }
nextsoldier.engine = { GroupPush = function () return push [1], push [2] end }

local Class = {}
Class.__index = Class
BotSteering.Apply (Class,
	{
		util =
		{
			TraceHull = function () return { Hit = false } end,
			TraceLine = function () return { Hit = true } end
		},
		Vector = Vec,
		mask = 1
	}
)
local function Soldier ()
	return setmetatable (
		{
			ent = { GetHull = function () return Vec (-24, -24, 0), Vec (24, 24, 82) end }
		}, Class)
end

local AT = Vec (0, 0, 0)
local AHEAD = { x = 500, y = 0, z = 0 }

T.test ("with no push its way is as it was", function ()
	push = { 0, 0 }
	local point = Soldier ():SteerOn (AT, AHEAD)
	T.eq (point.x, 500, "ahead")
	T.eq (point.y, 0,   "straight")
end)

T.test ("walking, its group's push leans its way aside", function ()
	push = { 0, 1 }
	local point = Soldier ():SteerOn (AT, AHEAD)
	T.eq (point.y > 0, true, "off to where it is pushed")
	T.eq (point.x,     500,  "still going where it goes")
end)

T.test ("a drop's ledge is stepped off as it was, the push no matter", function ()
	push = { 0, 1 }
	local below = { x = 10, y = 0, z = -188 }
	local soldier = Soldier ()
	T.eq (soldier:SteerOn (Vec (0, 0, 100), below).y == 0 or soldier:SteerOn (Vec (0, 0, 100), below) == below, true, "no leaning off a ledge")
end)

T.test ("standing with a teammate on it, it moves aside", function ()
	push = { 1, 0 }
	local point = Soldier ():Spread (AT)
	T.eq (point.x > 16, true, "far enough for a body to start walking")
end)

T.test ("with room enough it stands, not shuffling for a slight push", function ()
	push = { 0, 0 }
	T.eq (Soldier ():Spread (AT), nil, "no push")
	push = { 0.05, 0 }
	T.eq (Soldier ():Spread (AT), nil, "a slight one")
end)

T.test ("where the binary lacks it, there is no push", function ()
	local engine = nextsoldier.engine
	nextsoldier.engine = {}
	T.eq (Soldier ():Spread (AT),           nil, "nothing to read")
	T.eq (Soldier ():SteerOn (AT, AHEAD).y, 0,   "its way as it was")
	nextsoldier.engine = engine
end)

T.finish ()
