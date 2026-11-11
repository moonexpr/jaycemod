-- A fortification: a squad sets up its works in a room, its support members building them and the
-- rest mustered round them. The works go up in TF2's engineer's order:
--   ENTRANCE  a teleporter's entrance where the squad set out (home), when that is TELEPORT_MIN or
--             more from the room's middle, a walk worth saving; built by a member within
--             ENTRANCE_REACH of it, as one sets out (none goes back for it)
--   SENTRY    at the room's middle (or the floor's spot nearest it the map admits), facing the
--             entrance the most of the enemy's flow comes in by, or, with none known, the one
--             furthest from where the squad came in; one a member (TF2's engineer each keeps his
--             own), up to SENTRIES_MAX, the rest round it where the map admits (SENTRY_SPOTS)
--   DISPENSER DISPENSER_BESIDE to the sentry's right, facing as it does (TF2's nest)
--   EXIT      the teleporter's exit hidden outside the entrance the enemy comes in by least (and of
--             those the furthest from those it does), out of the room's sight as an assault stages
--             (group_identity's Hidden; Places' admitAt the map's word outside); else inside, out
--             of sight of the enemy's ways in (room.watched), the furthest from them within
--             EXIT_REACH of the objective; else EXIT_BESIDE to the sentry's left
-- Each work is claimed by one builder, the first member able to build it (me:NSLegsBuilds(kind))
-- to ask while it is free, one work at a time; it sets it down from its stand (BUILD_STANDOFF
-- behind it: me:NSLegsBuild(kind, at, facing) -> what stands, or nil), again BUILD_RETRY after a
-- refusal, then takes the next; one destroyed (me:NSLegsStands(handle) false) is built again, and a
-- member gone leaves its claims to the others; a teleporter's end goes to the builder of its other end,
-- once that stands (me:NSLegsOwns(handle)). With none left it keeps its team's buildings up (me:NSLegsTend() ->
-- where the one needing it most stands, or nil; me:NSLegsWrench() -> whether it is within its
-- wrench's reach, swinging when it is), and with all whole it takes its place. It is no mission awaiting its
-- leader: its members fight as any.
--
-- Fortify(room[, home]) -> an order: Places(members, spacing, admit) (each a muster's place round
-- the sentry, BUILD_CLEARANCE clear of every work); Works() -> { id, kind, at, facing, stand } in
-- build order (none before Places); WorksOf(kind); Claim(id, member) (true for its builder);
-- Builder(id); SetBuilt(id, handle), Built(id), Object(id). Its leggings' action is LegsFortify: a builder to its work's
-- stand at a run, there building; the rest to their places; falling back, it evacuates.
local Action = nextsoldier.behavior.action
local Orders = nextsoldier.squad.orders
local Legs = nextsoldier.squad.behaviors.legs
local GroupIdentity = nextsoldier.behavior.group_identity
local GIB = nextsoldier.behavior.gib_behaviors
local Geometry = math.geometry
local ipairs, pairs, min, math = ipairs, pairs, math.min, math
module ("nextsoldier.squad.behaviors.fortify")

-- The kinds of work, as the body building them names them.
SENTRY, DISPENSER, ENTRANCE, EXIT = "sentry", "dispenser", "teleporter_entrance", "teleporter_exit"

-- A builder stands BUILD_STANDOFF behind its work; the squad keeps BUILD_CLEARANCE clear of the
-- works; a work the map refused is tried again BUILD_RETRY seconds later.
BUILD_STANDOFF, BUILD_CLEARANCE, BUILD_RETRY = 48, 64, 3
-- A builder kept from its stand (a corner, a prop) sets its work down from within BUILD_REACH of it.
BUILD_REACH = 160
-- A teleporter is set up for a walk of TELEPORT_MIN or more (straight across the ground), its exit
-- EXIT_BESIDE from the sentry; the dispenser stands DISPENSER_BESIDE from it.
TELEPORT_MIN, EXIT_BESIDE, DISPENSER_BESIDE = 1200, 96, 96
-- Hidden inside the room, the exit stands within EXIT_REACH of the objective. A teleporter's entrance
-- is built by a member within ENTRANCE_REACH of it, as it sets out: none goes back from the works.
EXIT_REACH, ENTRANCE_REACH = 512, 600
-- A sentry a member, at most SENTRIES_MAX, each past the first at the first of SENTRY_SPOTS round it
-- the map admits SENTRY_CLEAR from every other work: SENTRY_SPREAD to a side, then behind
-- aslant, behind, ahead aslant; then the same two thirds as far. A spot is { along (from the
-- way it faces, back), across (to the left) }.
SENTRIES_MAX, SENTRY_SPREAD, SENTRY_CLEAR = 3, 192, 80
SENTRY_SPOTS = {}
for _, reach in ipairs ({ SENTRY_SPREAD, SENTRY_SPREAD * 2 / 3 }) do
	for _, degrees in ipairs ({ 90, -90, 135, -135, 180, 45, -45 }) do
		local radians = math.rad (degrees)
		SENTRY_SPOTS [#SENTRY_SPOTS + 1] = { -reach * math.cos (radians), reach * math.sin (radians) }
	end
end

local Hold = Orders.Kind ()

-- The entrance the most of the enemy comes in by; with none known, the one furthest from the entry.
local function Facing (room)
	local best
	for _, e in ipairs (room.entrances or {}) do
		if (e.enemyFlow or 0) > 0 and (not best or e.enemyFlow > best.enemyFlow) then best = e end
	end
	if best then return best.pos end
	local far, length
	for _, e in ipairs (room.entrances or {}) do
		local d = Geometry.Distance2D (e.pos, room.entry)
		if not far or d > length then far, length = e.pos, d end
	end
	return far
end

-- p moved distance along the ground from toward (away when distance is negative), or p itself.
local function Back (p, from, distance)
	local away = Geometry.Normalize2D (Geometry.Sub (p, from))
	if not away then return p end
	return { x = p.x + away.x * distance, y = p.y + away.y * distance, z = p.z }
end

function Hold:Works () return self.works end

function Hold:WorksOf (kind)
	local found = {}
	for _, work in ipairs (self.works) do
		if work.kind == kind then found [#found + 1] = work end
	end
	return found
end

-- The entrance the fight comes in by least, and of those the furthest from those it does.
local function Quietest (room)
	local best, bestFlow, bestApart
	for _, e in ipairs (room.entrances or {}) do
		local flow, apart = e.enemyFlow or 0, math.huge
		for _, other in ipairs (room.entrances) do
			if (other.enemyFlow or 0) > 0 then apart = min (apart, Geometry.Distance2D (e.pos, other.pos)) end
		end
		if not best or flow < bestFlow or (flow == bestFlow and apart > bestApart) then best, bestFlow, bestApart = e, flow, apart end
	end
	return best
end

-- Where the teleporter's exit hides: outside the quietest entrance, out of the room's sight (as an
-- assault stages); nil without word of what the room sees or of the ground outside.
local function HiddenExit (room, spacing, admitAt)
	local quiet = room.seen and admitAt and Quietest (room)
	return quiet and GroupIdentity.Hidden (room, quiet.pos, 1, spacing, admitAt) [1]
end

-- Where the exit hides inside: of the room's floor within EXIT_REACH of the objective and free of the
-- works, out of sight of every entrance the enemy comes in by (room.watched) where any is, the
-- furthest from them; nil without word of what they see, or none the enemy comes in by.
local BEYOND = 1e6 -- out of sight outranks any distance
local function HiddenInside (room, spacing, admit, center, Free)
	if not room.watched then return nil end
	local theirs = {}
	for _, e in ipairs (room.entrances or {}) do
		if (e.enemyFlow or 0) > 0 then theirs [#theirs + 1] = e.pos end
	end
	if #theirs == 0 then return nil end
	local best, bestApart
	for _, p in ipairs (Legs.Floor (room, spacing, admit)) do
		if Geometry.Distance2D (p, center) <= EXIT_REACH and Free (p) then
			local apart, seen = math.huge, false
			for _, door in ipairs (theirs) do
				seen = seen or room.watched (p, door)
				apart = min (apart, Geometry.Distance2D (p, door))
			end
			-- out of their sight first, then the furthest from them
			local rank = (seen and 0 or BEYOND) + apart
			if not best or rank > bestApart then best, bestApart = p, rank end
		end
	end
	return best
end

function Hold:Places (members, spacing, admit, admitAt)
	admit = admit or function (slot) return slot end
	local room, works = self.room, {}
	local function Add (kind, at, facing, stand)
		works [#works + 1] = { id = #works + 1, kind = kind, at = at, facing = facing, stand = stand or at }
	end
	local center = admit (room.center) or Legs.Nearest (Legs.Floor (room, spacing, admit), room.center, 1, spacing) [1]
	local dispenser = admit (Geometry.Offset2D (center, self.facing, 0, -DISPENSER_BESIDE))
	-- a sentry a member (TF2's engineer each keeps his own): the first at the middle, the rest the
	-- first spot round it the map admits, clear of every other work
	local taken = { center, dispenser }
	local function Free (spot)
		if not spot then return nil end
		for _, other in pairs (taken) do
			if Geometry.Distance2D (spot, other) < SENTRY_CLEAR then return nil end
		end
		return spot
	end
	local sentries = { center }
	for _ = 2, min (#members, SENTRIES_MAX) do
		for _, spot in ipairs (SENTRY_SPOTS) do
			local at = Free (admit (Geometry.Offset2D (center, self.facing, spot [1], spot [2])))
			if at then
				sentries [#sentries + 1], taken [#taken + 1] = at, at
				break
			end
		end
	end
	-- a teleporter only for a walk worth saving, its exit hidden from the fight where the room says
	-- (outside a quiet entrance, else inside out of the enemy's sight), else beside the sentry
	local exit
	if self.home ~= nil and Geometry.Distance2D (self.home, center) >= TELEPORT_MIN then
		exit = HiddenExit (room, spacing, admitAt) or HiddenInside (room, spacing, admit, center, Free)
			or Free (admit (Geometry.Offset2D (center, self.facing, 0, EXIT_BESIDE)))
	end
	if exit then Add (ENTRANCE, self.home, center, Back (self.home, center, BUILD_STANDOFF)) end
	for _, at in ipairs (sentries) do Add (SENTRY, at, self.facing, admit (Back (at, self.facing, BUILD_STANDOFF))) end
	if dispenser then Add (DISPENSER, dispenser, self.facing, admit (Back (dispenser, self.facing, BUILD_STANDOFF))) end
	-- its exit set down from beside it, toward the objective
	if exit then Add (EXIT, exit, self.facing, admit (Back (exit, center, -BUILD_STANDOFF)) or exit) end
	self.works, self.size = works, #members
	local function Clear (slot)
		for _, work in ipairs (works) do
			if Geometry.Distance2D (slot, work.at) < BUILD_CLEARANCE then return nil end
		end
		return admit (slot)
	end
	return GroupIdentity.Muster (center):Places (members, spacing, Clear)
end

function Hold:Claim (id, member)
	local builder = self.builders [id]
	if builder == nil then self.builders [id] = member return true end
	return builder == member
end

function Hold:Builder (id) return self.builders [id] end

-- What stands for a work, as its builder's body named it (nil: not up, or destroyed).
function Hold:SetBuilt (id, handle) self.built [id] = handle end

function Hold:Built (id) return self.built [id] ~= nil end

function Hold:Object (id) return self.built [id] end

-- A member gone (killed or left) gives up the works it claimed, for another to build.
local BaseLeave = Hold.Leave

function Hold:Leave (member)
	BaseLeave (self, member)
	for id, builder in pairs (self.builders) do
		if builder == member then self.builders [id] = nil end
	end
end

-- A fortification is held however many of its builders fall: they come back to their works, as
-- TF2's engineers come back to their nest. A danger near still clears it (Endanger).
function Hold:Rout () return false end

function Fortify (room, home)
	return Orders.New (Hold, { kind = "Fortify", point = room.center, room = room, exits = room.exits, home = home,
		facing = Facing (room), works = {}, builders = {}, built = {} })
end

LegsFortify = Action.Extend ("LegsFortify")

-- It contains nothing: building and holding is all it does.
function LegsFortify:InitialContainedAction () return nil end

-- A teleporter's other end, standing, is another's: its ends are one builder's (me:NSLegsOwns(handle)),
-- as TF2's are an engineer's.
local OTHER_END = { [ENTRANCE] = EXIT, [EXIT] = ENTRANCE }

local function OthersEnd (order, me, work)
	local other = OTHER_END [work.kind]
	if not other then return false end
	for _, end_ in ipairs (order:WorksOf (other)) do
		if order:Built (end_.id) and not me:NSLegsOwns (order:Object (end_.id)) then return true end
	end
	return false
end

-- The work me is building: its own claimed and not yet up (or destroyed since), else the first free
-- one it can build.
local function Job (order, me)
	for _, work in ipairs (order:Works ()) do
		if order:Built (work.id) and not me:NSLegsStands (order:Object (work.id)) then order:SetBuilt (work.id, nil) end
	end
	for _, work in ipairs (order:Works ()) do
		if not order:Built (work.id) and order:Builder (work.id) == me then return work end
	end
	for _, work in ipairs (order:Works ()) do
		if not order:Built (work.id) and order:Builder (work.id) == nil and me:NSLegsBuilds (work.kind)
			and (work.kind ~= ENTRANCE or Geometry.Distance2D (me:NSLegsAt (), work.at) <= ENTRANCE_REACH)
			and not OthersEnd (order, me, work) then
			order:Claim (work.id, me)
			return work
		end
	end
	return nil
end

function LegsFortify:Update (me)
	local result = Legs.OnOrders (self, me)
	if result.type ~= Action.CONTINUE then return result end
	local fall = Legs.Evacuating (self)
	if fall then return fall end
	local order = self.order
	local work = Job (order, me)
	-- its works up, its team's building needing it most: wrenched within reach, else run to
	local tend = not work and me:NSLegsTend ()
	if tend then
		local reached = me:NSLegsWrench ()
		me:NSLegsHeadFor (reached and me:NSLegsAt () or tend, reached and GIB.GAIT.REST or GIB.GAIT.RUN)
		return self:Continue ()
	end
	local place = work and work.stand or me:NSLegsPlace () or me:NSLegsAt ()
	local at = me:NSLegsAt ()
	local there = Geometry.Distance2D (at, place) <= GIB.STAGE_REACH
		or (work ~= nil and Geometry.Distance2D (at, work.at) <= BUILD_REACH)
	me:NSLegsHeadFor (place, there and GIB.GAIT.REST or GIB.GAIT.RUN)
	if work and there and me:Now () >= (self.retryAt or 0) then
		local handle = me:NSLegsBuild (work.kind, work.at, work.facing)
		if handle then
			order:SetBuilt (work.id, handle)
		else
			self.retryAt = me:Now () + BUILD_RETRY
		end
	end
	return self:Continue ()
end

-- Never under way as a mission is: its leader killed, nobody abandons it (command's Abandon).
Orders.Register (
	{
		kind = "Fortify",
		action = LegsFortify
	}
)
