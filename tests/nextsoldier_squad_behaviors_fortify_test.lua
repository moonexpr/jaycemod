-- nextsoldier.squad.behaviors.fortify: a squad's support members set up their works in a room (a
-- teleporter entrance where the squad set out, a sentry at the room's middle facing the way the
-- enemy comes in, a dispenser on its right, the teleporter's exit on its left), the rest mustered
-- round them.
local T = dofile ("tests/harness.lua")
local Fortify = nextsoldier.squad.behaviors.fortify
local Orders = nextsoldier.squad.orders
local GIB = nextsoldier.behavior.gib_behaviors
local R = dofile ("tests/fake_room.lua")
local F = dofile ("tests/fake_legs.lua")

local FAR_HOME = { x = Fortify.TELEPORT_MIN + 500, y = 0, z = 0 }

local function Fortifying (enemyFlows, count, home)
	local order = Fortify.Fortify (R.Room ({ 0, 0, 0, 0 }, enemyFlows), home)
	local at = R.East (count or 4)
	return order, order:Places (at, R.SPACING, R.AdmitAt (R.CENTER), R.AdmitAt), at
end

local function Kinds (order)
	local kinds = {}
	for i, work in ipairs (order:Works ()) do kinds [i] = work.kind end
	return table.concat (kinds, ",")
end

-- A member who builds the kinds given, standing where it was placed.
local function Builder (order, place, kinds)
	local me, _, orders = F.OnOrder (order, place)
	me.built, me.swung = {}, 0
	function me:NSLegsBuilds (kind) return kinds == nil or kinds [kind] == true end
	-- its team's building needing it most (me.tend), and its wrench on it within reach (me.reach)
	function me:NSLegsTend () return self.tend end
	function me:NSLegsWrench ()
		if self.reach then self.swung = self.swung + 1 end
		return self.reach == true
	end
	-- what it sets down is a handle standing until destroyed (me.standing[handle] = false), in one
	-- world: what one sets down stands for all, and is its own
	me.standing = order.standing or {}
	order.standing = me.standing
	me.mine = {}
	function me:NSLegsBuild (kind, at, facing)
		if self.refuse then return nil end
		local handle = { kind = kind, at = at, facing = facing }
		self.built [#self.built + 1] = handle
		self.standing [handle] = true
		self.mine [handle] = true
		return handle
	end
	function me:NSLegsStands (handle) return self.standing [handle] == true end
	-- what it set down is its own (me.owns[handle] = true gives it another's, as a respawn keeps them)
	me.owns = {}
	function me:NSLegsOwns (handle) return self.mine [handle] == true or self.owns [handle] == true end
	return me, orders
end

T.test ("a fortification's works, in the order they go up: a sentry a member, then its dispenser", function ()
	local order = Fortifying ({ 0, 0, 3, 0 }, 3)
	T.eq (order.kind, "Fortify", "a fortification")
	T.eq (Kinds (order), "sentry,sentry,sentry,dispenser", "no teleporter without a home far off")
	T.eq (Kinds (Fortifying ({ 0, 0, 3, 0 }, 1)), "sentry,dispenser", "one member, one sentry")
	T.eq (#Fortifying ({ 0, 0, 3, 0 }, Fortify.SENTRIES_MAX + 2):WorksOf (Fortify.SENTRY), Fortify.SENTRIES_MAX, "at most SENTRIES_MAX")
end)

T.test ("a sentry past the first stands SENTRY_SPREAD to a side of it, by turns, facing as it does", function ()
	local sentries = Fortifying ({ 0, 0, 3, 0 }, 3):WorksOf (Fortify.SENTRY)
	T.near (R.Distance2D (sentries [2].at, sentries [1].at), Fortify.SENTRY_SPREAD,     0.001, "the second beside it")
	T.near (R.Distance2D (sentries [3].at, sentries [1].at), Fortify.SENTRY_SPREAD,     0.001, "the third beside it")
	T.near (R.Distance2D (sentries [2].at, sentries [3].at), 2 * Fortify.SENTRY_SPREAD, 0.001, "on its other side")
	T.eq (sentries [2].facing,        sentries [1].facing, "facing as it does")
	T.eq (R.Inside (sentries [3].at), true,                "inside")
end)

T.test ("set out from far off, its teleporter's entrance goes first, where it set out, and its exit last", function ()
	local order = Fortifying ({ 0, 0, 3, 0 }, 4, FAR_HOME)
	T.eq (Kinds (order), "teleporter_entrance,sentry,sentry,sentry,dispenser,teleporter_exit", "the build order")
	T.eq (order:Works () [1].at, FAR_HOME, "the entrance where it set out")
	local near = Fortifying ({ 0, 0, 3, 0 }, 4, { x = Fortify.TELEPORT_MIN - 1, y = 0, z = 0 })
	T.eq (Kinds (near), "sentry,sentry,sentry,dispenser", "none for a walk too short to save")
end)

T.test ("the sentry goes at the room's middle, facing the entrance the most of the enemy comes in by", function ()
	local work = Fortifying ({ 0, 1, 3, 0 }):WorksOf (Fortify.SENTRY) [1]
	T.eq (work.at.x,   R.CENTER.x,  "at the middle: x")
	T.eq (work.at.y,   R.CENTER.y,  "at the middle: y")
	T.eq (work.facing, R.DOORS [3], "facing the enemy's way in")
end)

T.test ("with no enemy known to come, the sentry faces the entrance furthest from the one the squad came in by", function ()
	T.eq (Fortifying ({ 0, 0, 0, 0 }):WorksOf (Fortify.SENTRY) [1].facing, R.DOORS [4], "facing the way on")
end)

T.test ("the dispenser stands beside the sentry on its right, inside, facing as it does", function ()
	local order = Fortifying ({ 0, 0, 3, 0 })
	local dispenser, sentry = order:WorksOf (Fortify.DISPENSER) [1], order:WorksOf (Fortify.SENTRY) [1]
	T.near (R.Distance2D (dispenser.at, sentry.at), Fortify.DISPENSER_BESIDE, 0.001, "beside it")
	T.eq (R.Inside (dispenser.at), true,          "inside")
	T.eq (dispenser.facing,        sentry.facing, "facing as it does")
	local exit = Fortifying ({ 0, 0, 3, 0 }, 4, FAR_HOME):WorksOf (Fortify.EXIT) [1]
	T.eq (R.Distance2D (dispenser.at, exit.at) > Fortify.DISPENSER_BESIDE, true, "the other side from the exit")
end)

T.test ("a fortification sets no doors", function ()
	T.eq (#Fortifying ({ 0, 0, 3, 0 }, 4, FAR_HOME):WorksOf ("door"), 0, "none")
end)

T.test ("in a narrow room the sentries past the first find room round it, clear of every work", function ()
	local order = Fortify.Fortify (R.Room ({ 0, 0, 0, 0 }, { 0, 0, 3, 0 }), FAR_HOME)
	-- only near the middle is admitted: no room SENTRY_SPREAD to a side
	local near = function (slot) if R.Distance2D (slot, R.CENTER) <= 150 then return { x = slot.x, y = slot.y, z = slot.z } end return nil end
	order:Places (R.East (3), R.SPACING, near)
	local works = order:Works ()
	T.eq (#order:WorksOf (Fortify.SENTRY), 3, "each its sentry")
	for i, a in ipairs (works) do
		if a.kind ~= Fortify.ENTRANCE then
			for j = i + 1, #works do
				if works [j].kind ~= Fortify.ENTRANCE then
					T.eq (R.Distance2D (a.at, works [j].at) >= Fortify.SENTRY_CLEAR, true, a.kind .. " clear of " .. works [j].kind)
				end
			end
		end
	end
end)

T.test ("the teleporter's exit hides outside the entrance furthest from the enemy's ways in, out of the room's sight", function ()
	local exit = Fortifying ({ 0, 0, 3, 0 }, 4, FAR_HOME):WorksOf (Fortify.EXIT) [1]
	T.eq (R.Inside (exit.at), false, "outside the room")
	T.eq (R.Seen (exit.at), false, "out of the room's sight")
	T.eq (R.DoorOf (exit.at), 2, "by the north door, across from the enemy's south")
	T.eq (R.Distance2D (exit.at, R.DOORS [2]) <= nextsoldier.behavior.group_identity.STACK_REACH, true, "near it")
end)

T.test ("with no hidden ground outside, the exit hides inside, out of sight of the enemy's ways in, away from them", function ()
	local room = R.Room ({ 0, 0, 0, 0 }, { 0, 0, 3, 0 })
	-- the room sees all round it: nothing outside is out of its sight
	room.seen = function () return true end
	local order = Fortify.Fortify (room, FAR_HOME)
	order:Places (R.East (4), R.SPACING, R.AdmitAt (R.CENTER), R.AdmitAt)
	local exit = order:WorksOf (Fortify.EXIT) [1]
	T.eq (R.Inside (exit.at), true, "inside")
	T.eq (R.Watched (exit.at, R.DOORS [3]), false, "out of sight from the enemy's door")
	T.eq (R.Distance2D (exit.at, R.DOORS [3]) > R.Distance2D (R.CENTER, R.DOORS [3]), true, "further from it than the middle")
	T.eq (R.Distance2D (exit.at, R.CENTER) <= Fortify.EXIT_REACH, true, "near the objective")
	for _, work in ipairs (order:Works ()) do
		if work ~= exit and work.kind ~= Fortify.ENTRANCE then
			T.eq (R.Distance2D (exit.at, work.at) >= Fortify.SENTRY_CLEAR, true, "clear of the " .. work.kind)
		end
	end
end)

T.test ("in a room seen all through, the exit stands the furthest from the enemy's ways in", function ()
	local room = R.Room ({ 0, 0, 0, 0 }, { 0, 0, 3, 0 })
	room.seen = function () return true end
	room.watched = function () return true end
	local order = Fortify.Fortify (room, FAR_HOME)
	order:Places (R.East (4), R.SPACING, R.AdmitAt (R.CENTER), R.AdmitAt)
	local exit = order:WorksOf (Fortify.EXIT) [1]
	T.eq (R.Inside (exit.at), true, "inside")
	T.eq (R.Distance2D (exit.at, R.DOORS [3]) > R.Distance2D (R.CENTER, R.DOORS [3]) + Fortify.EXIT_BESIDE, true, "well away from the enemy's door")
	T.eq (R.Distance2D (exit.at, R.CENTER) <= Fortify.EXIT_REACH, true, "near the objective")
end)

T.test ("with no word of what the room or its ways in see, the exit stands beside the sentry, facing as it does", function ()
	local room = R.Room ({ 0, 0, 0, 0 }, { 0, 0, 3, 0 })
	room.seen, room.watched = nil, nil
	local order = Fortify.Fortify (room, FAR_HOME)
	order:Places (R.East (4), R.SPACING, R.AdmitAt (R.CENTER), R.AdmitAt)
	local exit, sentry = order:WorksOf (Fortify.EXIT) [1], order:WorksOf (Fortify.SENTRY) [1]
	T.near (R.Distance2D (exit.at, sentry.at), Fortify.EXIT_BESIDE, 0.001, "beside it")
	T.eq (exit.facing, sentry.facing, "facing as it does")
end)

T.test ("the squad musters round the works, inside, clear of them", function ()
	local order, places = Fortifying ({ 0, 0, 3, 0 }, 4, FAR_HOME)
	for i = 1, 4 do
		T.eq (places [i] ~= nil,     true, "placed: " .. i)
		T.eq (R.Inside (places [i]), true, "inside: " .. i)
		for _, work in ipairs (order:Works ()) do
			T.eq (R.Distance2D (places [i], work.at) >= Fortify.BUILD_CLEARANCE, true, "clear of the " .. work.kind .. ": " .. i)
		end
	end
end)

T.test ("a builder stands BUILD_STANDOFF behind the sentry, away from where it faces", function ()
	local work = Fortifying ({ 0, 0, 3, 0 }):WorksOf (Fortify.SENTRY) [1]
	T.near (R.Distance2D (work.stand, work.at), Fortify.BUILD_STANDOFF, 0.001, "its standoff")
	T.eq (R.Distance2D (work.stand, work.facing) > R.Distance2D (work.at, work.facing), true, "behind it")
end)

T.test ("one builder claims each work, the once", function ()
	local order = Fortifying ({ 0, 0, 3, 0 })
	local id, a, b = order:Works () [1].id, {}, {}
	T.eq (order:Claim (id, a), true,  "claimed")
	T.eq (order:Claim (id, a), true,  "still its own")
	T.eq (order:Claim (id, b), false, "another's")
	T.eq (order:Builder (id),  a,     "its builder")
end)

T.test ("a fortification is no mission awaiting its leader: its members fight as they see fit", function ()
	local order = Fortifying ({ 0, 0, 3, 0 })
	T.eq (Orders.Awaiting (order), false, "not awaiting")
end)

T.test ("its leader killed, a fortification is not abandoned: its builders come back to it", function ()
	local Command = nextsoldier.squad.interactions.command
	local order, places = Fortifying ({ 0, 0, 3, 0 })
	local leader, member = {}, {}
	order:Lead (leader)
	Command.Casualty (order, leader, places [1])
	order:Casualty (leader)
	T.eq (Command.Abandon (order, member), nil,   "no fall back")
	T.eq (order.routed == true,            false, "held")
end)

-- Updates a builder, standing it at each stand it heads for, until it heads for its own place.
local function BuildAll (me, legs)
	for _ = 1, 30 do
		legs:Update (me)
		if me.spot == me.place then break end
		me.at = me.spot
	end
end

T.test ("told to fortify, a builder runs to each work's stand in turn and sets it down there, once each", function ()
	local order, places = Fortifying ({ 0, 0, 3, 0 }, 4, FAR_HOME)
	local me, legs = Builder (order, places [1])
	order:Lead (me)
	T.eq (legs.name, "LegsFortify", "fortifying")
	-- setting out, near home, where its entrance goes, though not within reach of it
	me.at = { x = FAR_HOME.x + 2 * Fortify.BUILD_REACH, y = FAR_HOME.y, z = 0 }
	legs:Update (me)
	local first = order:Works () [1]
	T.eq (me.spot,   first.stand,  "to the first work's stand")
	T.eq (me.gait,   GIB.GAIT.RUN, "running")
	T.eq (#me.built, 0,            "nothing built on the way")
	BuildAll (me, legs)
	T.eq (#me.built, #order:Works (), "each built")
	for i, work in ipairs (order:Works ()) do
		T.eq (me.built [i].kind,     work.kind, "in order: " .. i)
		T.eq (me.built [i].at,       work.at,   "at its work: " .. i)
		T.eq (order:Built (work.id), true,      "up: " .. i)
	end
	legs:Update (me)
	T.eq (#me.built, #order:Works (), "once each")
	T.eq (me.spot,   me.place,        "then to its place")
end)

T.test ("with its works up, a builder runs to a building needing tending and wrenches it within reach", function ()
	local order, places = Fortifying ({ 0, 0, 3, 0 })
	local me, legs = Builder (order, places [1])
	order:Lead (me)
	BuildAll (me, legs)
	me.tend = { x = 40, y = 40, z = 0 }
	legs:Update (me)
	T.eq (me.spot,  me.tend,      "to it")
	T.eq (me.gait,  GIB.GAIT.RUN, "running")
	T.eq (me.swung, 0,            "out of reach")
	me.reach = true
	legs:Update (me)
	T.eq (me.swung, 1,             "wrenched")
	T.eq (me.gait,  GIB.GAIT.REST, "stood at it")
	me.tend, me.reach = nil, false
	legs:Update (me)
	T.eq (me.spot, me.place, "all whole: to its place")
end)

T.test ("a work left to build comes before one to tend", function ()
	local order, places = Fortifying ({ 0, 0, 3, 0 })
	local me, legs = Builder (order, places [1])
	order:Lead (me)
	me.tend, me.reach = { x = 40, y = 40, z = 0 }, true
	legs:Update (me)
	T.eq (me.spot,  order:Works () [1].stand, "to its work")
	T.eq (me.swung, 0,                        "not tending yet")
end)

T.test ("a work destroyed is built again by its builder", function ()
	local order, places = Fortifying ({ 0, 0, 3, 0 })
	local me, legs = Builder (order, places [1])
	order:Lead (me)
	BuildAll (me, legs)
	local sentry = me.built [1]
	me.standing [sentry] = false
	-- away from it when it falls
	me.at = R.East (1) [1]
	legs:Update (me)
	T.eq (order:Built (order:Works () [1].id), false,                    "down")
	T.eq (me.spot,                             order:Works () [1].stand, "back to its stand")
	me.at = me.spot
	legs:Update (me)
	T.eq (#me.built,                           #order:Works () + 1, "built again")
	T.eq (order:Built (order:Works () [1].id), true,                "up again")
end)

T.test ("a builder gone leaves its works to the others", function ()
	local order, places = Fortifying ({ 0, 0, 3, 0 })
	local a, legsA = Builder (order, places [1])
	local b, legsB = Builder (order, places [2], { dispenser = true })
	order:Lead (a)
	legsA:Update (a)
	T.eq (order:Builder (order:Works () [1].id), a, "the first's")
	order:Casualty (a)
	legsB:Update (b)
	T.eq (order:Builder (order:Works () [1].id),                    nil, "the sentry free again, though b builds none")
	T.eq (order:Builder (order:WorksOf (Fortify.DISPENSER) [1].id), b,   "b takes the dispenser")
end)

T.test ("a teleporter's entrance far off is left to a member near it", function ()
	local order, places = Fortifying ({ 0, 0, 3, 0 }, 4, FAR_HOME)
	local far, legsFar = Builder (order, places [1])
	far.at = R.East (1) [1]
	legsFar:Update (far)
	local entrance = order:WorksOf (Fortify.ENTRANCE) [1]
	T.eq (order:Builder (entrance.id), nil, "not the one at the works")
	local near, legsNear = Builder (order, places [2])
	near.at = FAR_HOME
	legsNear:Update (near)
	T.eq (order:Builder (entrance.id), near, "the one by it")
end)

T.test ("the teleporter's exit is set down from beside it, not from on it", function ()
	local exit = Fortifying ({ 0, 0, 3, 0 }, 4, FAR_HOME):WorksOf (Fortify.EXIT) [1]
	T.near (R.Distance2D (exit.stand, exit.at), Fortify.BUILD_STANDOFF, 0.001, "its standoff")
end)

T.test ("a builder kept from its stand builds from within BUILD_REACH of the work", function ()
	local order, places = Fortifying ({ 0, 0, 3, 0 })
	local me, legs = Builder (order, places [1])
	order:Lead (me)
	local sentry = order:Works () [1]
	-- across the work from its stand, not on it
	me.at = { x = 2 * sentry.at.x - sentry.stand.x, y = 2 * sentry.at.y - sentry.stand.y, z = 0 }
	legs:Update (me)
	T.eq (order:Built (sentry.id), true, "built from there")
end)

T.test ("two builders share the works, each its own", function ()
	local order, places = Fortifying ({ 0, 0, 3, 0 })
	local a, legsA = Builder (order, places [1])
	local b, legsB = Builder (order, places [2])
	order:Lead (a)
	legsA:Update (a)
	legsB:Update (b)
	T.eq (a.spot ~= b.spot,                      true, "to different works")
	T.eq (order:Builder (order:Works () [1].id), a,    "the first to ask takes the first")
	T.eq (order:Builder (order:Works () [2].id), b,    "the next the next")
end)

T.test ("a member who builds nothing takes its place round the works", function ()
	local order, places = Fortifying ({ 0, 0, 3, 0 })
	local me, legs = Builder (order, places [2], {})
	me.at = R.East (1) [1]
	legs:Update (me)
	T.eq (me.spot,                               me.place, "to its place")
	T.eq (order:Builder (order:Works () [1].id), nil,      "claims nothing")
end)

T.test ("set down refused, the builder tries again BUILD_RETRY later", function ()
	local order = Fortifying ({ 0, 0, 3, 0 })
	local me, legs = Builder (order, nil)
	local sentry = order:Works () [1]
	me.refuse = true
	me.at = sentry.stand
	legs:Update (me)
	T.eq (order:Built (sentry.id), false, "refused")
	me.refuse = false
	me.now = Fortify.BUILD_RETRY / 2
	legs:Update (me)
	T.eq (#me.built, 0, "not yet")
	me.now = Fortify.BUILD_RETRY
	legs:Update (me)
	T.eq (#me.built, 1, "again")
end)

T.test ("falling back, it evacuates", function ()
	local order, places = Fortifying ({ 0, 0, 3, 0 })
	local me, legs = Builder (order, places [2], {})
	order:Lead (me)
	order:Endanger ({ x = -500, y = 0, z = 0 })
	T.eq (legs:Update (me).action.name, "LegsEvacuate", "evacuating")
end)

T.test ("a teleporter's ends are one builder's: one end up, the other is its builder's alone", function ()
	local order = Fortifying ({ 0, 0, 3, 0 }, 4, FAR_HOME)
	local entrance = order:WorksOf (Fortify.ENTRANCE) [1]
	local exit = order:WorksOf (Fortify.EXIT) [1]
	local ends = { [Fortify.ENTRANCE] = true, [Fortify.EXIT] = true }
	local owner = Builder (order, exit.stand, ends)
	order:SetBuilt (exit.id, owner:NSLegsBuild (Fortify.EXIT, exit.at, exit.facing))
	local other, otherLegs = Builder (order, entrance.at, ends)
	otherLegs:Update (other)
	T.eq (order:Builder (entrance.id), nil, "not another's to build")
	local back, backLegs = Builder (order, entrance.at, ends)
	back.owns [order:Object (exit.id)] = true
	backLegs:Update (back)
	T.eq (order:Builder (entrance.id), back, "the exit's builder, come back, builds it")
end)

T.test ("its builders falling, the fortification holds: they come back to their works, no rout", function ()
	local order, places = Fortifying ({ 0, 0, 3, 0 })
	local me, legs = Builder (order, places [2], {})
	order:Lead (me)
	for _ = 1, #places do order:Casualty ({}) end
	T.eq (order:Rout (),           false, "no rout")
	T.eq (legs:Update (me).action, nil,   "still fortifying")
end)

T.test ("the tuning of a fortification is defined", function ()
	T.defined (Fortify.BUILD_STANDOFF,  "BUILD_STANDOFF")
	T.defined (Fortify.BUILD_CLEARANCE, "BUILD_CLEARANCE")
	T.defined (Fortify.BUILD_RETRY,     "BUILD_RETRY")
	T.defined (Fortify.TELEPORT_MIN,    "TELEPORT_MIN")
	T.defined (Fortify.EXIT_BESIDE,     "EXIT_BESIDE")
end)

T.finish ()
