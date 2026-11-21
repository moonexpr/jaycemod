-- features.aiwar.drive_orders: what a bot soldier's look sends its native drive
-- (nextsoldier.engine.Drive), which makes its keys every tick until the next look.
local T = dofile ("tests/harness.lua")
local Orders = T.require ("features.aiwar.drive_orders")

local PAN = { frequency = 3, damping = 1, pursuit = 1 }

-- What a look gathered, as sv_bots.lua's look gathers it.
local function Gathered (fields)
	local gathered =
	{
		now = 12,
		interval = 0.015,
		walk = false,
		walkSpeed = 200,
		slowWalkSpeed = 100,
		target = { x = 100, y = 0, z = 0 },
		pan = PAN,
		aimRadius = 16,
		fire = true
	}
	for k, v in pairs (fields or {}) do gathered [k] = v end
	return gathered
end

T.test ("a run is its walk speed, as its keys pressed no sprint; a walk its slow walk's, as IN_WALK did", function ()
	T.eq (Orders.Of (Gathered ()).speed,                200, "a run")
	T.eq (Orders.Of (Gathered ({ walk = true })).speed, 100, "a walk")
end)

T.test ("the orders carry what the look gathered, as engine.Drive names it", function ()
	local weapon = { automatic = true, melee = false, reach = 1500, clip = 30, reserve = 90 }
	local look = { x = 0, y = 50, z = 64 }
	local orders = Orders.Of (Gathered (
		{
			crouchArea = true,
			jumpArea = false,
			hop = true,
			lowBlocked = true,
			headBlocked = false,
			doorAhead = true,
			look = look,
			lookPriority = true,
			chase = 1000,
			avoid = 750,
			weapon = weapon
		}
	))
	T.eq (orders.now,          12,     "game time")
	T.eq (orders.interval,     0.015,  "a tick")
	T.eq (orders.target.x,     100,    "where it is sent")
	T.eq (orders.crouchArea,   true,   "crouch area")
	T.eq (orders.jumpArea,     false,  "jump area")
	T.eq (orders.hop,          true,   "a hop")
	T.eq (orders.lowBlocked,   true,   "a hurdle")
	T.eq (orders.headBlocked,  false,  "no lintel")
	T.eq (orders.doorAhead,    true,   "a door")
	T.eq (orders.look,         look,   "where to look")
	T.eq (orders.lookPriority, true,   "over its enemy")
	T.eq (orders.pan,          PAN,    "its hand")
	T.eq (orders.aimRadius,    16,     "its enemy's width")
	T.eq (orders.chase,        1000,   "its weapon's chase")
	T.eq (orders.avoid,        750,    "and avoid")
	T.eq (orders.fire,         true,   "may fire")
	T.eq (orders.weapon,       weapon, "what it holds")
end)

T.test ("standing, with nothing in hand, it is sent nowhere and holds no weapon", function ()
	local orders = Orders.Of (Gathered ({ target = false, fire = false }))
	T.eq (orders.target, nil,   "sent nowhere")
	T.eq (orders.weapon, nil,   "nothing held")
	T.eq (orders.fire,   false, "holds its fire")
end)

T.test ("its heading is the way to where it is sent, across the ground; none standing", function ()
	T.near (Orders.Heading ({ x = 0, y = 0, z = 0 }, { x = 0, y = 100, z = 50 }), 90,  1e-9, "north")
	T.near (Orders.Heading ({ x = 10, y = 0, z = 0 }, { x = -90, y = 0, z = 0 }), 180, 1e-9, "west")
	T.eq (Orders.Heading ({ x = 0, y = 0, z = 0 }, nil), nil, "standing")
end)

T.finish ()
