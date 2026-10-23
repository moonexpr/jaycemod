-- The orders of an AI war soldier: an NPC variant (games.npc.nextbot) whose
-- Actions run over the soldier port (features.aiwar.soldier). The engine's
-- own AI does the fighting; the orders decide where a soldier should be and
-- walk it there over the nav mesh, since TF2 maps have no AI node graph for
-- the engine's pathfinder.
--
-- Each role is a strategy: Goal(field, member) -> a position or nil, how
-- close counts as there (arrive), how far from its goal it may fight
-- (leash), and whether it ignores enemies on the way (rushes: cart pushers
-- and blockers, who must stand on the cart to count). Optional: Zone(field,
-- member) -> center, radius or nil, an area to occupy (inside it the
-- soldier has arrived, and walks to a new spot in it every ZONE_SHUFFLE);
-- Urgent(field, member) -> bool, while true the soldier rushes, stops for
-- no enemy at its leash, starts no chase and will not retreat (TF2's
-- CTFBotCapturePoint); Line(field, member) -> line, from: a raider's enemy
-- line; gait: the gait of a spot trip (WALK by default); squads: its
-- members follow their leader, as offensive squads' do; LeavesLane(field,
-- member) -> bool: while true its squad's leader keeps off its lane;
-- Stage(field, member) -> name or nil: the stage of the job it is at, its action
-- named for it (a CTF courier's RetrieveFlag, then ReturnHome) and changed
-- as it changes; STAGES = stage -> settings of the role's that stage
-- overrides (a goal, arrive, leash, chases = false, ...).
--
-- A scenario's jobs form a doctrine (field.doctrine; PAYLOAD here, the
-- point doctrine in features.aiwar.scenario.control_points): { NAME,
-- ROLES = job -> role, WaitsForSetup(field, member) -> bool: it wanders
-- behind the gates in setup, ChaseAnchor(field, member) -> pos or nil:
-- chases keep within CHASE_LEASH of it, PatrolMark(field, member) -> mark,
-- taken when a patrol starts, PatrolHolds(mark, field, member) -> ok, why:
-- the patrol goes on while true, Threat(field, member) -> pos or nil: where
-- the enemy will come from, which a soldier standing idle watches,
-- Side(field, member) -> a key of SIDES ("attack" or "defend", or a
-- scenario's own, as CTF's jobs): the member's side, and
-- SIDES = side -> the name of its side action, and optionally SHORT_SIDES =
-- side -> the short name the debug layer's TDBN gives it }.
-- Nothing outside a doctrine reads carts.
--
-- The tree follows TF2's bots (docs/aiwar-command.md):
--
--   NextSoldier          ends when the soldier dies (CTFBotMainAction)
--     StrategyMonitor      applies the war's allocation: the member's job
--       TacticalMonitor    self-preservation (CTFBotTacticalMonitor): the
--                          humiliated SuspendFor Humiliated
--         SquadMonitor     leader, member or solo (games.ns.squad)
--           SquadLeader | SquadMember | Solo   a member takes its bound line
--                          from its leader, regroups on it in a fight, and
--                          fights the enemy its leader fights
--             ScenarioMonitor   runs the side (CTFBotScenarioMonitor)
--             PayloadAttacker | PayloadDefender   the member's side in the
--                          scenario (the doctrine's Side and SIDES), which
--                          runs its job and changes itself with the side
--               Push/Escort/Block/Defend/Raid/Support/Idle   the job:
--                          hold or fight near the goal (pushers and
--                          blockers keep to their spot as the cart moves),
--                          else SuspendFor; a job whose member's job
--                          changed ChangeTo's the new one
--                 Travel   run straight at the goal while nothing is in the
--                          way, following it as it moves; otherwise follow a
--                          Lua route, re-routing as the goal moves or when
--                          the soldier stops moving; getting unstuck is its
--                          own, as moving actions handle OnStuck in TF2
--
-- What a soldier should do is asked of the actions it runs, as NextBot's
-- contextual queries (the innermost answers first; ANSWER_UNDEFINED passes
-- the question on), never read off another action's role:
--   ShouldHurry(me)          the job: yes while Urgent (Travel stops for
--                            no one, the fight is fought on the way)
--   ShouldRetreat(me)        the job: no while Urgent (TacticalMonitor asks
--                            before a retreat, RetreatToCover each think)
--   ShouldPickUp(me, kit)    the job: no while Urgent (FindHealth asks)
--   ShouldAttack(me, them), SelectMoreDangerousThreat(me, a, b)   DrGBase
--                            asks: a healing medic holds fire, a squad
--                            member fights its leader's enemy
-- A detour (a trip, a retreat) asks the work it interrupted (AskInterrupted),
-- which NextBot's queries reach only as far as the buried action itself.
--
-- For the war report, a soldier's state shows its goal, route and waypoint
-- (goal, route, routeIndex) and how its last trip ended (trip); in a fight,
-- the goal is the tactical destination (flank point, bound spot, cover), with
-- the tactic, the member's element ("moving" or "holding") and the cover spot
-- it chose, if any (tactic, element, coverSpot).
local abs, ceil, cos, floor, max, min, pi, sin, sqrt = math.abs, math.ceil, math.cos, math.floor, math.max, math.min, math.pi, math.sin, math.sqrt
local ipairs, pairs = ipairs, pairs
local format = string.format
local N = require("games.npc.nextbot")
local Debug = require("foundation.npc.debug")
local AiWar = require("features.aiwar.model")
local Teams = require("games.gameplay.teams")
local Track = require("foundation.math.polyline")
local Tactics = require("games.ns.tactics")
local Geometry = require("foundation.math.geometry")
local Squad = require("games.ns.squad")
local Lanes = require("games.ns.lanes")
local Hunt = require("games.ns.hunt")
local Health = require("features.aiwar.health")
local Speech = require("games.ns.speech")
local Explore = require("games.ns.explore")
module(...)

KIND = "aiwar"

-- Goals
-- Just outside a cart's body, inside its capture area: PUSH_RING, or the
-- cart's own reach (field.carts' radius: its footprint's half diagonal and
-- a soldier's hull) when larger. Inside the body a soldier is killed by the
-- trigger_hurt maps put there for players stuck in the cart.
PUSH_RING = 56
PUSH_ARRIVE, PUSH_LEASH = 72, 110
-- Blockers charge the enemy's cart and stand across its nose, in its way
-- and inside its capture area: BLOCK_LEAD ahead of it, BLOCK_COLUMNS
-- abreast BLOCK_SPREAD apart, further rows BLOCK_DEPTH ahead.
BLOCK_LEAD, BLOCK_SPREAD, BLOCK_COLUMNS, BLOCK_DEPTH = 56, 40, 3, 40
-- Raiders go round the enemy's line to a point FLANK_OFFSET (tactics)
-- beside it, off the line from their own side; there, the line broken,
-- the attackers' raiders join the push and the defenders' fall on the
-- enemy's cart. A new line (posts moved RAID_SHIFT) sends them round again.
RAID_ARRIVE, RAID_LEASH, RAID_SHIFT = 150, 900, 256
-- Support stands SUPPORT_BEHIND behind its side's line (or its cart),
-- and fights from cover there.
SUPPORT_BEHIND, SUPPORT_ARRIVE, SUPPORT_LEASH = 320, 120, 1200
-- Raiders and support use their gadgets (the soldier port's UseGadget:
-- grenades, manhacks, turrets) on a contact within GADGET_RANGE, once
-- every GADGET_INTERVAL.
GADGET_RANGE, GADGET_INTERVAL = 1200, 12
ESCORT_LEAD = 300
ESCORT_ARRIVE, ESCORT_LEASH = 150, 700
DEFEND_LEAD, DEFEND_DEPTH, DEFEND_ROWS = 600, 250, 3
DEFEND_ARRIVE, DEFEND_LEASH = 150, 900
LATERAL, LATERAL_STEPS = 80, 2
-- In setup the defending side lines up past each gate the attackers must
-- come through (field.gates: { pos, dir } with dir the way attackers pass
-- it): defenders GATE_STANDOFF past it, blockers a row behind, spaced
-- GATE_SPACING along the line from its middle out.
GATE_STANDOFF, GATE_ROW, GATE_SPACING = 256, 96, 64
local GOLDEN_ANGLE = 2.39996323 -- radians: ring slots never line up

-- A pusher or blocker at its cart runs to its spot again once the cart
-- has carried the spot this far away.
STATION = 36

-- Travel
WAYPOINT_RADIUS = 48
LOOKAHEAD = 3 -- waypoints past the current one tested for a straight walk
REPATH_INTERVAL, REPATH_DISTANCE = 2, 150
-- Stuck: moved less than STUCK_PROGRESS in STUCK_TIME while running.
STUCK_TIME, STUCK_PROGRESS = 3, 24
MAX_REPATHS = 2
REPATH_AGAIN = 10 -- after a fresh path, stuck again within this: on to the other remedies
CHASE_BACKOFF = 3 -- after a straight run got stuck, routes only for this long
-- A goal is gone straight at only within CHASE_RANGE: a clear line (the
-- port's CanWalkTo) says nothing of the drops, pits and ledges on the way,
-- so anything farther follows a route over the nav mesh. A soldier whose
-- engine plans its own routes (the port's PlansRoutes: an AI node graph)
-- is given the goal itself, whatever its range, and keeps it: the port
-- walks it by hand where the engine's run fails.
CHASE_RANGE = 256
-- A stuck soldier first steps this far aside, for this long, in a direction
-- that turns with each attempt and differs between soldiers: most are held
-- by a corner, a door frame or someone in the way, not by the route.
SIDESTEP_DISTANCE, SIDESTEP_TIME = 96, 1.5
-- Last resort, when every step aside and new route has failed: a hop of
-- up to this far toward the waypoint, where a player could walk (a brush
-- only NPCs collide with, a lip their step cannot take).
HOP_DISTANCE = 160
-- A soldier stuck against a solid entity (a cart, a prop) walks to a point
-- beside it, for up to this long, then goes on along its route.
DETOUR_TIME = 3

-- In setup the attackers cannot push their cart (TF2 lets no point be
-- captured) and the gates are shut, so they wander the ground behind the
-- gates: to a spot (the soldier port's WanderSpot), which may be rooms
-- away, travelling there as to any goal, resting WANDER_REST there,
-- giving a spot up after WANDER_GIVE_UP; when setup ends they go to work.
-- At each spot a wanderer strikes a pose (the soldier port's Pose: sits,
-- lies down, dances) until it moves on.
WANDER_ARRIVE, WANDER_REST, WANDER_GIVE_UP = 48, 12, 30

-- The defenders' patrol: a defender or blocker at its spot, while the
-- checkpoint the enemy's cart heads for stays the same, walks its own
-- rounds: spots within PATROL_RADIUS of its post (the soldier port's
-- PatrolSpot), PATROL_REST at each, whether or not the cart creeps on.
-- When the objective moves on or the post shifts more than PATROL_SHIFT,
-- it goes back to its post; an enemy in sight ends a round, and the
-- engine's AI fights.
PATROL_RADIUS, PATROL_REST, PATROL_GIVE_UP = 384, 6, 20
PATROL_SHIFT = 64

-- Watching (TF2's CTFBot::UpdateLookingAroundForEnemies): a soldier with no
-- enemy in sight faces the threat (the soldier port's Watch): its fire
-- team's last contact, else gunfire it heard (OnHeard, features.aiwar.model.
-- hearing) for HEARD_MEMORY, else its doctrine's Threat, glancing GLANCES degrees
-- aside of it, one every GLANCE_TIME, in a cycle its slot offsets so that
-- neighbours do not turn as one.
GLANCE_TIME = 3
GLANCES = { 0, 35, 0, -35 }
HEARD_MEMORY = 5

-- Gaits (the soldier port's MoveTo): a casual walk for setup's wanderers,
-- a panicked run for the defenders racing to their line in setup, a run
-- otherwise.
WALK, RUN, PANIC = "walk", "run", "panic"
-- A cart's rushers run and only break off when hit (the port's engine
-- lets them be interrupted by damage alone).
RUSH = "rush"
RETRY_WAIT = 1 -- after a failed trip, before the next

local Distance = Geometry.Distance

-- Slot 0 on the line, then alternately left and right, out to LATERAL_STEPS.
function Lateral(k)
	if k == 0 then return 0 end
	local magnitude = min(ceil(k / 2), LATERAL_STEPS) * LATERAL
	return k % 2 == 1 and magnitude or -magnitude
end

function Ring(pos, slot, radius)
	local angle = slot * GOLDEN_ANGLE
	return { x = pos.x + cos(angle) * radius, y = pos.y + sin(angle) * radius, z = pos.z }
end

-- 0 in the middle, then alternately left and right, one spacing further
-- out each pair.
local function AlongLine(k)
	if k == 0 then return 0 end
	local magnitude = ceil(k / 2) * GATE_SPACING
	return k % 2 == 1 and magnitude or -magnitude
end

-- The member's spot in the setup line, or nil when there is no setup
-- line to stand in (not in setup, or no gate found).
function GateSpot(field, member, row)
	local gates = field.setup and field.gates and field.gates[Teams.EnemyOf(member.team)]
	if not gates or #gates == 0 then return nil end
	local gate = gates[member.slot % #gates + 1]
	local lateral = AlongLine(floor(member.slot / #gates))
	local depth = GATE_STANDOFF + row
	local dir, pos = gate.dir, gate.pos
	return { x = pos.x + dir.x * depth - dir.y * lateral, y = pos.y + dir.y * depth + dir.x * lateral, z = pos.z }
end

local function OwnCart(field, member) return field.carts[member.team] end

local function Reach(cart) return max(PUSH_RING, cart.radius or 0) end

-- The support sphere (flat: a circle, SPHERE_HEIGHT tall), SUPPORT_SPHERE
-- round a point ESCORT_SPHERE_LEAD ahead of the cart: escorts keep inside
-- it, and there are left to their own tactics and their engine's AI;
-- outside, one goes to the nearest point SPHERE_ENTER of the way in from the
-- centre, so the cart can roll a fair way before anyone moves again.
-- Pushers keep to their spots on the cart itself.
SUPPORT_SPHERE, ESCORT_SPHERE_LEAD = 900, 200
SPHERE_ENTER, SPHERE_HEIGHT = 0.6, 160

function SupportSphere(cart)
	return cart.track:Offset(cart.distance + ESCORT_SPHERE_LEAD, 0), SUPPORT_SPHERE
end

function InSphere(p, center, radius)
	local dx, dy = p.x - center.x, p.y - center.y
	return dx * dx + dy * dy <= radius * radius and abs((p.z or 0) - (center.z or 0)) <= SPHERE_HEIGHT
end

-- Where to enter a sphere from p: SPHERE_ENTER of its radius from the
-- centre, on p's side; p itself when p is already that far in.
function EntryPoint(center, radius, p)
	return Geometry.Toward(center, p, radius * SPHERE_ENTER)
end
local function EnemyCart(field, member) return field.carts[Teams.EnemyOf(member.team)] end

ROLES = {
	[AiWar.PUSH] = {
		name = "Push",
		sits = true,
		arrive = PUSH_ARRIVE,
		leash = PUSH_LEASH,
		rushes = true,
		Goal = function(field, member)
			local cart = OwnCart(field, member)
			return cart and Ring(cart.pos, member.slot, Reach(cart))
		end,
	},
	-- A blocker (a shotgunner: the controller arms it) patrols behind the
	-- defenders' line in setup; after, it charges the enemy's cart, whatever
	-- shoots at it, and stands in its way.
	[AiWar.BLOCK] = {
		name = "Block",
		chases = "eager",
		patrols = "setup",
		arrive = PUSH_ARRIVE,
		leash = PUSH_LEASH,
		rushes = true,
		Goal = function(field, member)
			local spot = GateSpot(field, member, GATE_ROW)
			if spot then return spot end
			local cart = EnemyCart(field, member)
			if not cart then return nil end
			local column, row = member.slot % BLOCK_COLUMNS, floor(member.slot / BLOCK_COLUMNS)
			local lateral = (column == 0 and 0) or (column % 2 == 1 and 1 or -1) * ceil(column / 2) * BLOCK_SPREAD
			return cart.track:Offset(cart.distance + max(BLOCK_LEAD, Reach(cart)) + row * BLOCK_DEPTH, lateral)
		end,
	},
	-- An escort keeps inside the support sphere around its cart, and there
	-- fights as its tactics and its engine's AI see fit (the port's
	-- FollowCart, HL2's follow behaviour, first when it has it).
	[AiWar.ESCORT] = {
		name = "Escort",
		chases = "opportunist",
		follows = true,
		tactic = "attack",
		arrive = ESCORT_ARRIVE,
		leash = ESCORT_LEASH,
		rushes = false,
		Sphere = function(field, member)
			local cart = OwnCart(field, member)
			if cart then return SupportSphere(cart) end
		end,
		Goal = function(field, member)
			local cart = OwnCart(field, member)
			if not cart then return nil end
			local center, radius = SupportSphere(cart)
			if not member.pos then return cart.track:Offset(cart.distance + ESCORT_LEAD, Lateral(member.slot)) end
			return EntryPoint(center, radius, member.pos)
		end,
	},
	-- EstablishLine: a post found for the defenders (field.posts, from
	-- games.ns.posts: high or low ground, hiding spots, watching
	-- the checkpoint the attackers head for), where it waits for them.
	[AiWar.DEFEND] = {
		name = "EstablishLine",
		chases = "opportunist",
		patrols = true,
		tactic = "defend",
		arrive = DEFEND_ARRIVE,
		leash = DEFEND_LEASH,
		rushes = false,
		Goal = function(field, member)
			local spot = GateSpot(field, member, 0)
			if spot then return spot end
			local posts = field.posts and field.posts[member.team]
			if posts and posts[member.slot + 1] then return posts[member.slot + 1] end
			local cart = EnemyCart(field, member)
			if not cart then return nil end
			local row, column = member.slot % DEFEND_ROWS, floor(member.slot / DEFEND_ROWS)
			return cart.track:Offset(cart.distance + DEFEND_LEAD + row * DEFEND_DEPTH, Lateral(column))
		end,
	},
}

-- Exploring (games.ns.explore), every scenario's job: a squad goes
-- for where it fights, else its lane's end, else its waypoint (field.explore:
-- the scenario's board), fighting what it meets; engaged, it leaves its lane.
-- Arena's explorers do it until the point opens; on any map an admin may
-- send soldiers exploring by hand.
EXPLORE_ROLE = {
	name = "Explore",
	chases = "opportunist",
	tactic = "attack",
	squads = true,
	arrive = ESCORT_ARRIVE,
	leash = ESCORT_LEASH,
	rushes = false,
	Goal = Explore.Goal,
	LeavesLane = Explore.LeavesLane,
}
ROLES[AiWar.EXPLORE] = EXPLORE_ROLE

-- The cart a raider or support soldier works, as no team is simply the
-- attacker or the defender: "defense" (against the enemy's cart) or
-- "offense" (for its own), or nil with no cart. With both carts it follows
-- its team's defense share (field.defense, features.aiwar.model's
-- DefenseShare), the soldiers' slots spread over it by the golden ratio:
-- at a share of 0.7 about seven in ten work the enemy's cart.
local GOLDEN = 0.6180339887

function Focus(field, member)
	local own, theirs = OwnCart(field, member), EnemyCart(field, member)
	if not own then return theirs and "defense" or nil end
	if not theirs then return "offense" end
	return ((member.slot + 1) * GOLDEN) % 1 < field.defense[member.team] and "defense" or "offense"
end

-- The enemy's line a raider goes for, and the point its own side comes
-- from: against the enemy's cart, its escorts' posts ahead of it (else the
-- cart), coming from the checkpoint it heads for; for its own, the enemy
-- defenders' posts (else the track ahead), coming from the cart.
function EnemyLine(field, member)
	local enemy = Teams.EnemyOf(member.team)
	local theirs, own = EnemyCart(field, member), OwnCart(field, member)
	local focus = Focus(field, member)
	if focus == "defense" then
		local from = theirs.track:PointAt(theirs.nextCheckpoint or theirs.track:Length())
		local posts = field.forwardPosts and field.forwardPosts[enemy]
		if posts and #posts > 0 then return posts[member.slot % #posts + 1], from end
		return theirs.pos, from
	end
	if focus == "offense" then
		local posts = field.posts and field.posts[enemy]
		if posts and #posts > 0 then return posts[member.slot % #posts + 1], own.pos end
		return own.track:Offset(own.distance + DEFEND_LEAD, 0), own.pos
	end
	return nil
end

-- `to` moved `offset` sideways, across the line from `from` to it (left
-- for a positive offset).
function Across(from, to, offset)
	local dx, dy = to.x - from.x, to.y - from.y
	local length = sqrt(dx * dx + dy * dy)
	if length == 0 or offset == 0 then return to end
	return { x = to.x - dy / length * offset, y = to.y + dx / length * offset, z = to.z }
end

-- A point `distance` from p, away from `from`.
function Behind(p, from, distance)
	local dx, dy = p.x - from.x, p.y - from.y
	local length = sqrt(dx * dx + dy * dy)
	if length == 0 then return p end
	return { x = p.x + dx / length * distance, y = p.y + dy / length * distance, z = p.z }
end

ROLES[AiWar.RAID] = {
	name = "Raid",
	chases = "opportunist",
	tactic = "raid",
	raids = true,
	arrive = RAID_ARRIVE,
	leash = RAID_LEASH,
	rushes = false,
	Line = EnemyLine,
	Goal = function(field, member)
		local spot = GateSpot(field, member, 0)
		if spot then return spot end
		local line, from = EnemyLine(field, member)
		if not line then return nil end
		return Tactics.FlankPoint(from, line, member.slot % 2 == 0 and 1 or -1)
	end,
	-- The line broken: on offense it joins the push, on defense it falls
	-- on the enemy's cart.
	Cleared = function(field, member)
		local focus = Focus(field, member)
		if focus == "offense" then
			local own = OwnCart(field, member)
			return Ring(own.pos, member.slot + 8, Reach(own))
		end
		local theirs = focus == "defense" and EnemyCart(field, member)
		return theirs and Ring(theirs.pos, member.slot + 8, Reach(theirs) * 3)
	end,
}

ROLES[AiWar.SUPPORT] = {
	name = "Support",
	tactic = "support",
	arrive = SUPPORT_ARRIVE,
	leash = SUPPORT_LEASH,
	rushes = false,
	Goal = function(field, member)
		local spot = GateSpot(field, member, GATE_ROW * 2)
		if spot then return spot end
		local own, theirs = OwnCart(field, member), EnemyCart(field, member)
		local focus = Focus(field, member)
		if focus == "defense" then
			local posts = field.posts and field.posts[member.team]
			if posts and #posts > 0 then return Behind(posts[member.slot % #posts + 1], theirs.pos, SUPPORT_BEHIND) end
			return theirs.track:Offset(theirs.distance + DEFEND_LEAD + DEFEND_DEPTH * DEFEND_ROWS, Lateral(member.slot))
		end
		if focus == "offense" then return own.track:Offset(own.distance - SUPPORT_BEHIND, Lateral(member.slot)) end
		return nil
	end,
}

-- Medics (TF2's CTFBotMedicHeal, in HL2's faces): a medic picks, among its
-- side's hurt soldiers and players (field.patients: team -> { handle, pos,
-- health (0 to 1), player, calling (it called for a medic: CallMedic) }),
-- the one that needs it most (players, callers and its own squadmates count
-- double, distance costs a little), keeps it until it is HEALED or lost
-- (gone, or beyond MEDIC_LOSE), and heals it with its beam (the port's
-- Heal) from MEDIC_STANDOFF away, holding fire while it does. With no one
-- to heal it stands where its side's support does.
HEAL_RANGE, MEDIC_STANDOFF, MEDIC_LOSE = 450, 160, 1500
-- a patient its medic healed within MEDIC_TREATING seconds is being treated
MEDIC_TREATING = 1
PATIENT_HURT, HEALED = 0.95, 0.98

local function Squadmate(member, handle)
	local fireTeam = member.fireTeam
	if not fireTeam then return false end
	for _, mate in pairs(fireTeam.members) do
		if mate.handle == handle then return true end
	end
	return false
end

function PickPatient(field, member, here, current)
	local patients = field.patients and field.patients[member.team] or {}
	local best, bestScore
	for _, patient in ipairs(patients) do
		if patient.handle ~= member.handle then
			local range = Distance(here, patient.pos)
			if current and patient.handle == current.handle and patient.health < HEALED and range <= MEDIC_LOSE then
				return patient
			end
			if patient.health < PATIENT_HURT and range <= MEDIC_LOSE then
				local first = patient.player or patient.calling or Squadmate(member, patient.handle)
				local score = (1 - patient.health) * (first and 2 or 1) - range / 3000
				if not bestScore or score > bestScore then best, bestScore = patient, score end
			end
		end
	end
	return best
end

ROLES[AiWar.MEDIC] = {
	name = "Medic",
	heals = true,
	arrive = SUPPORT_ARRIVE,
	leash = SUPPORT_LEASH,
	rushes = false,
	Goal = function(field, member) return ROLES[AiWar.SUPPORT].Goal(field, member) end,
}

-- The field's doctrine: the jobs of the war's scenario.
function DoctrineOf(field)
	return field.doctrine
end

-- The member's goal on the field, or nil (no role, or no goal for it now).
function Goal(field, member)
	local role = DoctrineOf(field).ROLES[member.role]
	return role and role.Goal(field, member)
end

-- The member's fire team's contact, reporting the enemy the member sees:
-- what one sees, its team knows (games.ns.tactics).
function TeamContact(state, me)
	local fireTeam = state.member.fireTeam
	if not fireTeam then return nil end
	if me:HasEnemy() then
		local enemy = me:EnemyPosition()
		if enemy then Tactics.Report(fireTeam, enemy, me:Now()) end
	end
	return Tactics.Contact(fireTeam, me:Now())
end

local function OrdersRun(field)
	return field ~= nil and field.phase.orders
end

-- An attacker (a team with a cart the other side lacks) in setup.
local function WaitingForSetup(field, member)
	return field.setup == true and field.carts[member.team] ~= nil and field.carts[Teams.EnemyOf(member.team)] == nil
end

-- Payload's doctrine (features.aiwar.scenario.payload): ROLES, with the
-- carts as what chases keep near (the enemy's, else its own) and what a
-- defender's patrol watches (the enemy's cart heading for the same
-- checkpoint).
PAYLOAD = {
	NAME = "payload",
	ROLES = ROLES,
	WaitsForSetup = WaitingForSetup,
	ChaseAnchor = function(field, member)
		local cart = EnemyCart(field, member) or OwnCart(field, member)
		return cart and cart.pos
	end,
	SIDES = { attack = "PayloadAttacker", defend = "PayloadDefender" },
	-- pushers and escorts attack, blockers and defenders defend; the rest
	-- follow their focus (Focus, below)
	Side = function(field, member)
		local job = member.role
		if job == AiWar.PUSH or job == AiWar.ESCORT then return "attack" end
		if job == AiWar.BLOCK or job == AiWar.DEFEND then return "defend" end
		return Focus(field, member) == "offense" and "attack" or "defend"
	end,
	PatrolMark = function(field, member)
		local cart = EnemyCart(field, member)
		return { checkpoint = cart and cart.nextCheckpoint }
	end,
	-- the enemy's cart, which its attackers come with; else the track ahead
	-- of its own, where the defenders wait
	Threat = function(field, member)
		local theirs = EnemyCart(field, member)
		if theirs then return theirs.pos end
		local own = OwnCart(field, member)
		return own and own.track:Offset(own.distance + DEFEND_LEAD, 0)
	end,
	PatrolHolds = function(mark, field, member)
		local cart = EnemyCart(field, member)
		if cart and cart.nextCheckpoint ~= mark.checkpoint then return false, "the objective moved on" end
		return true
	end,
}

-- Whether the member's job is urgent now (its role's Urgent). Only the job
-- reads it, to answer the queries (ShouldHurry, ShouldRetreat, ShouldPickUp);
-- every other action asks those.
local function IsUrgent(role, field, member)
	return role.Urgent ~= nil and OrdersRun(field) and role.Urgent(field, member) == true
end

-- A query asked of the work action interrupted (NextBot's queries reach a
-- buried action but not what it contains): each action buried under it,
-- what it runs first, innermost out. A trip asks its job; a retreat asks
-- the monitor it suspended, which runs the job.
local function AskInterrupted(action, me, name, ...)
	local under = action:GetActionBuriedUnderMe()
	while under do
		local answer = under:QueryBelow(me, name, ...)
		if answer == N.ANSWER_UNDEFINED and under[name] then answer = under[name](under, me, ...) end
		if answer ~= nil and answer ~= N.ANSWER_UNDEFINED then return answer end
		under = under:GetActionBuriedUnderMe()
	end
	return N.ANSWER_UNDEFINED
end

-------------------------------------------------------------------------------
-- Travel: follow a route to the role's goal, or (in setup) to a wander spot

local Travel = N.Action:Extend("Travel")

-- Whether role (a job's, or one at a stage: StageRole) is what the doctrine
-- gives member now: the same job's role, at the same stage when that stage
-- has settings of its own.
local function RunsUnder(role, field, member)
	local base = role.base or role
	if DoctrineOf(field).ROLES[member.role] ~= base then return false end
	local stage = base.Stage and base.Stage(field, member)
	local staged = stage and base.STAGES and base.STAGES[stage] and stage or nil
	return staged == role.stage
end

-- A wander or patrol spot is travelled to as a role's goal is, with these
-- terms.
local WANDER = { name = "Wander", arrive = WANDER_ARRIVE, leash = 0, rushes = false, giveUp = WANDER_GIVE_UP }
local PATROL = { name = "Patrol", arrive = WANDER_ARRIVE, leash = 0, rushes = false, giveUp = PATROL_GIVE_UP }

-- spot: a spot to go to instead of the role's goal, while keep(field, me)
-- -> true, or why not (by default: while the soldier waits for setup).
function Travel:Init(state, role, spot, keep)
	self.state = state
	self.role = role
	self.spot = spot
	self.keep = keep
	self.repaths = 0
	self.failed = false
	self.requested = false
	self.chaseBlockedUntil = 0
end

function Travel:OnStart(me)
	if self.spot then self.giveUpAt = me:Now() + (self.role.giveUp or WANDER_GIVE_UP) end
	self:SetRoute(nil)
	self:ResetProgress(me)
	return self:Continue()
end

function Travel:SetRoute(route)
	self.route = route
	self.index = 1
	self.state.route = route
	self.state.routeIndex = 1
end

function Travel:Plan(me, goal)
	self.goal = goal
	self.plannedAt = me:Now()
	self.requested = true
	self:SetRoute(nil)
	me:RequestRoute(goal)
end

function Travel:End(reason)
	self.state.trip = reason
	return self:Done(reason)
end

function Travel:Fail(reason)
	self.failed = true
	return self:End(reason)
end

-- Stuck is judged by the soldier's own movement, so a soldier running
-- after a goal that moves away as fast is not stuck.
function Travel:ResetProgress(me)
	self.anchor = me:Position()
	self.progressAt = me:Now()
end

function Travel:IsStuck(me)
	if Distance(me:Position(), self.anchor) > STUCK_PROGRESS then self:ResetProgress(me) end
	return me:Now() - self.progressAt > STUCK_TIME
end

-- A hop of up to HOP_DISTANCE toward the waypoint (or the goal) the
-- soldier is stuck on, if the soldier port allows it there.
function Travel:HopOn(me, goal)
	local target = self:StuckTarget(goal)
	local here = me:Position()
	local dx, dy, dz = target.x - here.x, target.y - here.y, target.z - here.z
	local length = sqrt(dx * dx + dy * dy + dz * dz)
	local t = length > HOP_DISTANCE and HOP_DISTANCE / length or 1
	local to = { x = here.x + dx * t, y = here.y + dy * t, z = here.z + dz * t }
	if not me:Hop(to) then return false end
	me:Mark(Debug.MARK_HOP, format("%d units toward its waypoint", floor(length * t + 0.5)), to)
	self.state.hops = (self.state.hops or 0) + 1
	self.repaths = 0
	self:ResetProgress(me)
	return true
end

-- What the soldier is stuck heading for: its waypoint, or the goal it
-- runs straight at.
function Travel:StuckTarget(goal)
	return self.route and self.route[self.index] or goal
end

-- Stuck: first, if what holds it is something only NPCs collide with, it
-- is let through and runs on; if it is a solid entity (a cart), it walks
-- round it; unless it did within REPATH_AGAIN, it plans its path afresh
-- from where it stands (pushed off its path, it runs at the path's next
-- point through whatever stands between); if the port lets it hop (over a crate across a narrow lane, or
-- up while climbing), it leaps toward its waypoint; otherwise a step aside
-- and a new route; after too many, a last hop, or the end of the trip.
function Travel:Unstick(me, goal)
	local target = self:StuckTarget(goal)
	if me:PassBlocker(target) then
		me:Mark(Debug.MARK_PASS, "something only NPCs collide with", nil)
		self.state.passed = (self.state.passed or 0) + 1
		self:ResetProgress(me)
		return self:Continue()
	end
	local detour = me:Detour(target)
	if detour then
		me:Mark(Debug.MARK_DETOUR, "round a solid entity", detour)
		self.detour, self.detourUntil = detour, me:Now() + DETOUR_TIME
		self:ResetProgress(me)
		me:MoveTo(detour, self.gait)
		return self:Continue()
	end
	local now = me:Now()
	if not self.repathedAt or now - self.repathedAt >= REPATH_AGAIN then
		self.repathedAt = now
		me:Repath()
		me:Mark(Debug.MARK_REPATH, "a fresh path from where it stands", nil)
		self:ResetProgress(me)
		return self:Continue()
	end
	if self:HopOn(me, goal) then return self:Continue() end
	self.repaths = self.repaths + 1
	if self.repaths > MAX_REPATHS then
		if self:HopOn(me, goal) then return self:Continue() end
		me:Mark(Debug.MARK_GAVE_UP, format("%d steps aside and no hop", MAX_REPATHS), nil)
		return self:Fail("stuck")
	end
	self:ResetProgress(me)
	self:Plan(me, goal)
	local angle = ((self.state.member.seq or 0) + self.repaths) * GOLDEN_ANGLE
	local here = me:Position()
	self.sidestep = { x = here.x + cos(angle) * SIDESTEP_DISTANCE, y = here.y + sin(angle) * SIDESTEP_DISTANCE, z = here.z }
	self.sidestepUntil = me:Now() + SIDESTEP_TIME
	me:Mark(Debug.MARK_SIDESTEP, format("try %d of %d, and a new route", self.repaths, MAX_REPATHS), self.sidestep)
	me:MoveTo(self.sidestep, self.gait)
	return self:Continue()
end

-- Past waypoints already reached, then to the farthest of the next few that
-- can be walked to in a straight line.
function Travel:Advance(me)
	local route, index = self.route, self.index
	while index < #route and me:RangeTo(route[index]) <= WAYPOINT_RADIUS do index = index + 1 end
	for k = min(#route, index + LOOKAHEAD), index + 1, -1 do
		if me:CanWalkTo(route[k]) then
			index = k
			break
		end
	end
	self.index = index
	self.state.routeIndex = index
end

-- A route came back: start walking it, or fail without one.
function Travel:TakeRoute(me)
	local result = me:RouteResult()
	if result == nil then return nil end
	if result == false then return self:Fail("no route") end
	self:SetRoute(result)
	return nil
end

-- Straight at the goal, wherever it has moved to. A run that goes nowhere
-- hands over to routes for a while.
-- The lane waypoint a squad leader of a lane job makes for, or nil (no
-- lane, not its leader, its role keeping it off the lane for now, or the
-- lane walked to its end: then straight on to the goal, and not back onto
-- that lane).
function Travel:LaneTarget(me)
	local state = self.state
	local member = state.member
	local fireTeam = member.fireTeam
	local lane = fireTeam and fireTeam.lane
	if not lane or not Lanes.JOBS[member.role] or Squad.Kind(member) ~= "leader" or state.laneDone == lane
		or (self.role.LeavesLane and self.role.LeavesLane(state.war:Field(), member)) then
		state.onLane = nil
		return nil
	end
	if state.lane ~= lane then state.lane, state.laneIndex = lane, 1 end
	local here = me:Position()
	state.laneIndex = Lanes.Next(lane, here, state.laneIndex)
	local target = Lanes.Target(lane, here, state.laneIndex)
	if not target then state.laneDone = lane end
	state.onLane = target ~= nil and fireTeam.laneIndex or nil
	return target
end

-- A trip over: off any lane.
function Travel:OnEnd(me)
	self.state.onLane = nil
end

function Travel:Chase(me, goal)
	if self:IsStuck(me) then
		self.chaseBlockedUntil = me:Now() + CHASE_BACKOFF
		return self:Unstick(me, goal)
	end
	me:MoveTo(goal, self.gait)
	return self:Continue()
end

function Travel:FollowRoute(me, goal)
	if not self.requested then self:Plan(me, goal) end
	if self.route == nil then
		local failed = self:TakeRoute(me)
		if failed then return failed end
		if self.route == nil then
			-- waiting on the search is not being stuck
			me:Release()
			self:ResetProgress(me)
			return self:Continue()
		end
	end
	-- a door shut or a brush switched on since: the route may lead into it
	if me:RouteStale() or (Distance(goal, self.goal) > REPATH_DISTANCE and me:Now() - self.plannedAt >= REPATH_INTERVAL) then
		self:Plan(me, goal)
		return self:Continue()
	end
	self:Advance(me)
	if self:IsStuck(me) then return self:Unstick(me, goal) end
	me:MoveTo(self.route[self.index], self.gait)
	return self:Continue()
end

-- The goal to travel to now, or nil and why the trip is over.
function Travel:Goal(me, field)
	local state = self.state
	if state.member.role == nil or not OrdersRun(field) then return nil, "orders changed" end
	if self.spot then
		if self.keep then
			local keep, why = self.keep(field, me)
			if not keep then return nil, why end
		elseif not DoctrineOf(field).WaitsForSetup(field, state.member) then
			return nil, "setup ended"
		end
		if me:Now() >= self.giveUpAt then return nil, "gave up" end
		return self.spot
	end
	if not RunsUnder(self.role, field, state.member) then return nil, "orders changed" end
	if DoctrineOf(field).WaitsForSetup(field, state.member) then return nil, "setup began" end
	local goal = self.role.Goal(field, state.member)
	-- a raider round the line: its side's cart (Objective:RaidGoal)
	if self.role.raids and state.cleared and not field.setup then goal = self.role.Cleared(field, state.member) or goal end
	if goal == nil then return nil, "no goal" end
	return goal
end

function Travel:Update(me)
	local state, role = self.state, self.role
	local field = state.war:Field()
	-- its job hurrying, the trip stops for no one (ShouldHurry)
	local urgent = not self.spot and AskInterrupted(self, me, "ShouldHurry") == N.ANSWER_YES
	if not self.spot and not urgent and role.tactic and TeamContact(state, me) then return self:End("contact") end
	if not self.spot and not urgent and role.chases and ChaseWanted(role, me, field, state.member) then return self:End("a weakened enemy") end
	local goal, over = self:Goal(me, field)
	self.gait = (self.spot and (role.gait or WALK)) or (field and field.setup and PANIC) or ((role.rushes or urgent) and RUSH) or RUN
	if goal == nil then
		if over == "gave up" then return self:Fail(over) end
		return self:End(over)
	end
	state.goal = goal
	local range = me:RangeTo(goal)
	if range <= role.arrive then return self:End("arrived") end
	if role.Sphere and not self.spot and not (field and field.setup) then
		local center, radius = role.Sphere(field, state.member)
		if center and InSphere(me:Position(), center, radius) then return self:End("in its sphere") end
	end
	if role.Zone and not self.spot then
		local center, radius = role.Zone(field, state.member)
		if center and InSphere(me:Position(), center, radius) then return self:End("in its zone") end
	end
	if not role.rushes and not urgent and me:HasEnemy() and range <= role.leash then return self:End("engaging") end
	if self.detour then
		if me:Now() < self.detourUntil and me:RangeTo(self.detour) > WAYPOINT_RADIUS then
			me:MoveTo(self.detour, self.gait)
			return self:Continue()
		end
		self.detour = nil
	end
	if self.sidestep then
		if me:Now() < self.sidestepUntil then
			me:MoveTo(self.sidestep, self.gait)
			return self:Continue()
		end
		-- a step aside that moved counts as progress by itself
		self.sidestep = nil
	end
	-- a squad leader on a lane walks it, waypoint by waypoint
	local laneTarget = not self.spot and self:LaneTarget(me)
	if laneTarget then return self:Chase(me, laneTarget) end
	-- an engine that plans its own routes keeps the goal: changing its target
	-- to our waypoints would only restart its runs
	if me:PlansRoutes() then return self:Chase(me, goal) end
	if me:Now() >= self.chaseBlockedUntil and range <= CHASE_RANGE and me:CanWalkTo(goal) then
		return self:Chase(me, goal)
	end
	return self:FollowRoute(me, goal)
end

-------------------------------------------------------------------------------
-- Chase: retreat's other half. A soldier whose enemy is weakened (under its
-- job's share of its health) and in reach goes after it to finish it:
-- blockers eagerly (they finish the job: a pusher off the cart to heal comes
-- back), the line's soldiers only when the kill is close and they are well
-- themselves. Pushers keep to the cart, medics to their patients, support
-- to its post: they never chase. A chase keeps within CHASE_LEASH of the
-- cart it is about (the enemy's, else its own): it neither starts nor goes
-- on with the chaser or its quarry beyond it. It ends when the enemy is dead
-- or lost from sight for CHASE_LOST, or its time is up; one that needs to
-- retreat does not chase, and the tactical monitor above sends a chaser that
-- gets hurt into retreat, whatever the chase.
CHASES = {
	eager = { health = 0.5, range = 1000, time = 10, fit = 0.35, gait = RUSH },
	opportunist = { health = 0.3, range = 500, time = 5, fit = 0.6, gait = RUN },
}
CHASE_LOST, CHASE_COOLDOWN, CHASE_LEASH = 1.5, 3, 1500

-- Whether p is within CHASE_LEASH of what the doctrine keeps chases near
-- (ChaseAnchor: payload's carts, a point's zone); anywhere without one.
local function Leashed(field, member, p)
	local anchor = field and DoctrineOf(field).ChaseAnchor(field, member)
	return not anchor or Distance(p, anchor) <= CHASE_LEASH
end

-- The role's chase profile when its soldier should chase its enemy now.
function ChaseWanted(role, me, field, member)
	local profile = CHASES[role.chases]
	if not profile or not me:HasEnemy() then return nil end
	local share, pos = me:EnemyHealth(), me:EnemyPosition()
	if not share or not pos or share >= profile.health or me:RangeTo(pos) > profile.range then return nil end
	if me:Health() / max(me:MaxHealth(), 1) < max(profile.fit, RETREAT_HEALTH) then return nil end
	if not (Leashed(field, member, pos) and Leashed(field, member, me:Position())) then return nil end
	return profile
end

local Chase = N.Action:Extend("Chase")
Chase.chase = true

function Chase:Init(state, target, profile)
	self.state, self.target, self.profile = state, target, profile
end

function Chase:OnStart(me)
	local now = me:Now()
	self.untilAt, self.seenAt = now + self.profile.time, now
	self.state.chases = (self.state.chases or 0) + 1
	return self:Continue()
end

function Chase:Update(me)
	local state, now = self.state, me:Now()
	local sees = me:HasEnemy() and me:Enemy() == self.target
	if sees then
		if not me:EnemyHealth() then return self:Done("killed") end
		self.seenAt, self.lastPos = now, me:EnemyPosition()
	end
	if now - self.seenAt > CHASE_LOST then return self:Done("lost") end
	if now >= self.untilAt then return self:Done("gave up") end
	local field = state.war:Field()
	if not Leashed(field, state.member, me:Position()) or (self.lastPos and not Leashed(field, state.member, self.lastPos)) then
		return self:Done("too far from the cart")
	end
	state.tactic = "chasing a weakened enemy"
	state.goal = self.lastPos
	if self.lastPos then me:MoveTo(self.lastPos, self.profile.gait) end
	return self:Continue()
end

function Chase:ShouldHurry(me) return N.ANSWER_YES end

-- It keeps shooting at the one it chases.
function Chase:SelectMoreDangerousThreat(me, a, b)
	if a == self.target or b == self.target then return self.target end
	return N.ANSWER_UNDEFINED
end

-------------------------------------------------------------------------------
-- Objectives: one Action per role of each doctrine

local Objective = N.Action:Extend("Objective")
local OBJECTIVE_OF = {} -- doctrine -> job -> its Objective class
-- No role (or one its doctrine lacks): the engine's AI has the soldier.
local Idle = N.Action:Extend("Idle")

-- A role at a stage: its own settings with the stage's (STAGES[stage])
-- over them; false clears one (chases = false: it chases nobody). The
-- merged role keeps the job's role (base) and its stage, which a trip
-- checks it still runs under (RunsUnder).
local function StageRole(role, stage)
	local override = stage and role.STAGES and role.STAGES[stage]
	if not override then return role end
	local merged = {}
	for k, v in pairs(role) do merged[k] = v end
	for k, v in pairs(override) do merged[k] = v end
	merged.base, merged.stage = role, stage
	return merged
end

-- The member's job's class under the field's doctrine, made on first use:
-- one per stage for a role with stages, named for it.
local function ObjectiveClass(state)
	local job = state.member.role
	local field = state.war:Field()
	local doctrine = DoctrineOf(field)
	local role = job and doctrine.ROLES[job]
	if not role then return Idle end
	local stage = role.Stage and role.Stage(field, state.member)
	local key = stage and (job .. "/" .. stage) or job
	local classes = OBJECTIVE_OF[doctrine] or {}
	OBJECTIVE_OF[doctrine] = classes
	if not classes[key] then
		local class = Objective:Extend(stage or role.name)
		class.roleName = job
		class.role = StageRole(role, stage)
		class.doctrine = doctrine
		class.stage = stage
		classes[key] = class
	end
	return classes[key]
end

local function ObjectiveFor(state)
	return ObjectiveClass(state):New(state)
end

function Objective:Init(state)
	self.state = state
	self.retryAt = 0
end

-- Stops following the cart, if it was.
local function StopFollowing(state, me)
	if not state.following then return end
	state.following = false
	me:Unfollow()
end

-- Setup's wandering: a spot, a trip there, a rest, another spot.
function Objective:Wander(me)
	local state, now = self.state, me:Now()
	StopFollowing(state, me)
	state.wandering = true
	if now < (self.restUntil or 0) then
		me:Release()
		state.pose = me:Pose()
		return self:Continue()
	end
	local spot = me:WanderSpot()
	if not spot then
		self.restUntil = now + WANDER_REST
		me:Release()
		return self:Continue()
	end
	state.goal = spot
	me:Unpose()
	state.pose = nil
	return self:SuspendFor(Travel:New(state, WANDER, spot), "wandering")
end

-- The patrol's anchor: the post, the doctrine and its mark of the
-- objective the patrol was taken for (PatrolMark).
local function Anchor(field, member, goal)
	local doctrine = DoctrineOf(field)
	return {
		goal = goal,
		doctrine = doctrine,
		mark = doctrine.PatrolMark(field, member),
	}
end

local function AnchorHolds(anchor, field, member, goal)
	if Distance(goal, anchor.goal) > PATROL_SHIFT then return false, "the post moved" end
	if DoctrineOf(field) ~= anchor.doctrine then return false, "orders changed" end
	return anchor.doctrine.PatrolHolds(anchor.mark, field, member)
end

-- A round of the patrol: a rest, then a walk to another spot near the post.
-- In setup the rest is in its battle stance (Pose), as a wanderer's is.
function Objective:Patrol(me, field, goal)
	local state, now = self.state, me:Now()
	state.patrolling = true
	if me:HasEnemy() or now < (self.restUntil or 0) then
		me:Release()
		if field.setup then state.pose = me:Pose() end
		return self:Continue()
	end
	local spot = me:PatrolSpot(self.anchor.goal, PATROL_RADIUS)
	if not spot then
		self.restUntil = now + PATROL_REST
		me:Release()
		return self:Continue()
	end
	me:Unpose()
	state.pose = nil
	local anchor, member = self.anchor, state.member
	local function Keep(currentField, soldier)
		if soldier:HasEnemy() then return false, "enemy in sight" end
		local post = self.role.Goal(currentField, member)
		if not post then return false, "no post" end
		return AnchorHolds(anchor, currentField, member, post)
	end
	return self:SuspendFor(Travel:New(state, PATROL, spot, Keep), "patrolling")
end

-- A squad member's tactic while it follows its leader (Objective:FollowLeader).
local FOLLOWING = "following its leader"

function Objective:Update(me)
	local state = self.state
	local field = state.war:Field()
	if state.member.role ~= self.roleName then return self:ChangeTo(ObjectiveFor(state), "new role") end
	if DoctrineOf(field) ~= self.doctrine then return self:ChangeTo(ObjectiveFor(state), "new doctrine") end
	if self.role.Stage then
		local stage = self.role.Stage(field, state.member)
		if stage ~= self.stage then return self:ChangeTo(ObjectiveFor(state), "now " .. (stage or self.role.name)) end
	end
	if OrdersRun(field) and self.doctrine.WaitsForSetup(field, state.member) then return self:Wander(me) end
	local urgent = self:ShouldHurry(me) == N.ANSWER_YES
	if state.wandering then
		state.wandering = false
		self.restUntil = nil
	end
	-- stances are setup's: a patrol's rest keeps its own until it walks on
	if state.pose and not field.setup then
		me:Unpose()
		state.pose = nil
	end
	if self.role.heals and OrdersRun(field) then
		local healing = self:Heal(me, field)
		if healing then return healing end
	end
	-- a weakened enemy in reach: after it (Chase)
	if self.role.chases and not urgent and OrdersRun(field) and not field.setup and me:Now() >= (self.chaseReadyAt or 0) then
		local profile = ChaseWanted(self.role, me, field, state.member)
		if profile then return self:SuspendFor(Chase:New(state, me:Enemy(), profile), "finishing a weakened enemy") end
	end
	local cart = self.role.follows and OrdersRun(field) and OwnCart(field, state.member)
	if cart and me:FollowCart() then
		state.following = true
		state.goal = cart.pos
		me:Release()
		return self:Continue()
	end
	StopFollowing(state, me)
	local goal = OrdersRun(field) and self.role.Goal(field, state.member)
	if not goal then
		me:Release()
		return self:Continue()
	end
	if self.role.raids and not field.setup then goal = self:RaidGoal(me, field, goal) end
	local range = me:RangeTo(goal)
	if self.role.tactic and not field.setup then
		-- an urgent job fights on the way (CTFBotDeliverFlag): no regrouping,
		-- bounding or holding with its squad; it travels on, its engine AI
		-- shooting as it goes
		local contact = not urgent and TeamContact(state, me)
		if contact then return self:Fight(me, goal, contact) end
		self:EndFight()
	end
	-- a squad moves as one: its members follow their leader to the
	-- objective; once either is there, or rushing it, each works it as its
	-- job says, from its own place
	-- (shown only while it follows: the debug overlay reads the tactic)
	if state.tactic == FOLLOWING then state.tactic = nil end
	if not field.setup and not urgent and not self.anchor then
		local following = self:FollowLeader(me, field)
		if following then return following end
	end
	-- inside its sphere, an escort squad's leader roams it
	if self.role.Sphere and not field.setup then
		local center, radius = self.role.Sphere(field, state.member)
		state.inSphere = center ~= nil and InSphere(me:Position(), center, radius)
		if state.inSphere then return self:Roam(me, center, radius, ROAM_REST, RUN) end
	end
	-- inside its zone, it shuffles from spot to spot in it (TF2's capturers
	-- re-path on the point every 0.5 to 1 s)
	if self.role.Zone then
		local center, radius = self.role.Zone(field, state.member)
		state.inZone = center ~= nil and InSphere(me:Position(), center, radius)
		if state.inZone then return self:Roam(me, center, radius, ZONE_SHUFFLE, urgent and RUSH or RUN) end
	end
	local patrols = self.role.patrols == true or (self.role.patrols == "setup" and field.setup)
	if not patrols and self.anchor then
		state.patrolling = false
		self.anchor, self.restUntil = nil, nil
	end
	if patrols then
		if self.anchor and AnchorHolds(self.anchor, field, state.member, goal) and range <= PATROL_RADIUS + self.role.arrive then
			return self:Patrol(me, field, goal)
		end
		state.patrolling = false
		if self.anchor then
			self.anchor = nil
			self.restUntil = nil
		end
		if range <= self.role.arrive then
			-- at the post: its patrol starts after a first rest
			self.anchor = Anchor(field, state.member, goal)
			self.restUntil = me:Now() + PATROL_REST
			state.goal = goal
			return self:Patrol(me, field, goal)
		end
	end
	state.goal = goal
	-- a pusher at its cart sits on it, where a seat is free (the port's Sit),
	-- and rides it until it must get off
	if self.role.sits then
		if me:IsSeated() then
			state.tactic = "riding the cart"
			return self:Continue()
		end
		if range <= self.role.arrive and me:Sit() then return self:Continue() end
	end
	-- at the cart: keep to the spot as the cart carries it off
	if self.role.rushes and range <= self.role.arrive then
		if range > STATION and me:CanWalkTo(goal) then me:MoveTo(goal, RUSH) else me:Release() end
		return self:Continue()
	end
	-- a raider squad's leader at its goal roams round it
	if self.role.raids and not field.setup and range <= self.role.arrive then return self:Roam(me, goal, RAID_ROAM, ROAM_REST, RUN) end
	-- an urgent job stops for no one on its way
	local fighting = not urgent and me:HasEnemy() and range <= self.role.leash
	if range <= self.role.arrive or fighting or me:Now() < self.retryAt then
		me:Release()
		return self:Continue()
	end
	return self:SuspendFor(Travel:New(state, self.role), "to the objective")
end

-- A raider's goal: round the enemy's line, then, once there, on to its
-- side's cart (Cleared) until the enemy's line moves.
function Objective:RaidGoal(me, field, goal)
	local line = self.role.Line(field, self.state.member)
	if not self.raidLine or not line or Distance(line, self.raidLine) > RAID_SHIFT then
		self.raidLine, self.cleared = line, false
	end
	if not self.cleared and me:RangeTo(goal) <= self.role.arrive then self.cleared = true end
	self.state.cleared = self.cleared
	if self.cleared then return self.role.Cleared(field, self.state.member) or goal end
	return goal
end

-- A raider or support soldier throws, deploys or sends its gadget at the
-- contact, when it has one.
function Objective:Gadget(me, contact, now)
	if now < (self.gadgetAt or 0) or me:RangeTo(contact.pos) > GADGET_RANGE then return end
	local used = me:UseGadget(contact.pos)
	if used then
		self.gadgetAt = now + GADGET_INTERVAL
		self.state.gadget = used
	end
end

-- A medic's patient, if it has one: to MEDIC_STANDOFF from it, the beam on
-- within HEAL_RANGE. Nil when there is no one to heal.
function Objective:Heal(me, field)
	local state = self.state
	local patient = PickPatient(field, state.member, me:Position(), state.healing)
	if not patient then
		if state.healing then
			me:Heal(nil)
			state.healing = nil
		end
		return nil
	end
	state.healing = patient
	local treated = state.war:Member(patient.handle)
	if treated then treated.medicAt = me:Now() end
	local range = me:RangeTo(patient.pos)
	local spot = Geometry.Toward(patient.pos, me:Position(), MEDIC_STANDOFF)
	state.goal, state.tactic = spot, "healing"
	me:Heal(range <= HEAL_RANGE and patient.handle or nil)
	if range > MEDIC_STANDOFF + SPOT_ARRIVE then me:MoveTo(spot, RUN) else me:Hold() end
	return self:Continue()
end

-- A medic holds its fire while it heals, as TF2's cannot fire and heal.
function Objective:ShouldAttack(me, them)
	if self.role.heals and self.state.healing then return N.ANSWER_NO end
	return N.ANSWER_UNDEFINED
end

-- An urgent job (its role's Urgent) neither retreats nor dawdles.
function Objective:ShouldRetreat(me)
	if IsUrgent(self.role, self.state.war:Field(), self.state.member) then return N.ANSWER_NO end
	return N.ANSWER_UNDEFINED
end

function Objective:ShouldHurry(me)
	if IsUrgent(self.role, self.state.war:Field(), self.state.member) then return N.ANSWER_YES end
	return N.ANSWER_UNDEFINED
end

-- An urgent job goes for no health kit (TF2's bomb carrier never does).
function Objective:ShouldPickUp(me, item)
	if IsUrgent(self.role, self.state.war:Field(), self.state.member) then return N.ANSWER_NO end
	return N.ANSWER_UNDEFINED
end

-- A fight, by the role's tactic (games.ns.tactics).
BOUND_RADIUS, COVER_RADIUS, SPOT_ARRIVE = 200, 320, 48
FLANK_TIME, FLANK_ARRIVE = 15, 160
-- A squad member farther than REGROUP_RANGE from its leader in a fight runs
-- to it first, to SQUAD_SPACING per place behind it; its bound spots are
-- spread across the leader's line, SQUAD_SPACING apart by place. A cover
-- spot a soldier takes is claimed for COVER_CLAIM seconds (renewed while
-- it holds it), so no two soldiers pick the same one.
REGROUP_RANGE, SQUAD_SPACING, COVER_CLAIM = 700, 96, 20

-- The member's squad leader, other than itself, with a known position.
-- One attached to another's squad (the war's Attach) goes with its host.
local function LeaderOf(member)
	local fireTeam = member.fireTeam
	local leader = member.host or (fireTeam and Squad.Leader(fireTeam))
	if leader == nil or leader == member or leader.pos == nil then return nil end
	return leader
end

-- Every squad moves as one, roaming its objective and fighting there
-- together (docs/aiwar-command.md §3): a member follows its
-- leader FOLLOW_SPACING per place behind it, loosely (within FOLLOW_SLACK
-- it is left to fight as it will); a leader at the objective takes a new
-- spot in it (the port's PatrolSpot) each time it has rested ROAM_REST
-- at the last, or the objective moved away from it. A job occupying a zone
-- (a role's Zone) rests only ZONE_SHUFFLE, as TF2's capturers re-path on
-- the point every 0.5 to 1 s.
FOLLOW_SPACING, FOLLOW_SLACK = 72, 96
ROAM_REST, RAID_ROAM = 8, 350
ZONE_SHUFFLE = 1

-- Whether a squadmate at pos is where its job is worked: at its goal, or
-- inside its role's sphere or zone.
function Objective:AtObjective(pos, member, field)
	local goal = self.role.Goal(field, member)
	if goal and Distance(pos, goal) <= self.role.arrive then return true end
	local function Inside(Area)
		if not Area then return false end
		local center, radius = Area(field, member)
		return center ~= nil and InSphere(pos, center, radius)
	end
	return Inside(self.role.Sphere) or Inside(self.role.Zone)
end

-- nil once there is no leader to follow, or either of them is at the
-- objective: from there each works it from its own place.
function Objective:FollowLeader(me, field)
	local state, member = self.state, self.state.member
	local leader = LeaderOf(member)
	if not leader then return nil end
	if self:AtObjective(me:Position(), member, field) or self:AtObjective(leader.pos, leader, field) then return nil end
	local spot = Geometry.Toward(leader.pos, me:Position(), FOLLOW_SPACING * ((member.place or 0) + 1))
	state.tactic, state.goal = FOLLOWING, spot
	if me:RangeTo(spot) > FOLLOW_SLACK then me:MoveTo(spot, RUN) else me:Release() end
	return self:Continue()
end

-- rest: how long at each spot; gait: how it walks between them.
function Objective:Roam(me, center, radius, rest, gait)
	local state, now = self.state, me:Now()
	local spot = self.roamSpot
	local rested = self.roamRestUntil and now >= self.roamRestUntil
	if not spot or rested or Distance(spot, center) > radius then
		spot = me:PatrolSpot(center, radius) or center
		self.roamSpot, self.roamRestUntil = spot, nil
	end
	state.tactic, state.goal = "roaming the objective", spot
	if me:RangeTo(spot) > SPOT_ARRIVE then
		me:MoveTo(spot, gait)
	else
		self.roamRestUntil = self.roamRestUntil or now + rest
		me:Release()
	end
	return self:Continue()
end


-- A cover spot near center no one else holds, claimed for the member.
function Objective:ClaimCover(me, center, radius, threat, exclude)
	local state, now = self.state, me:Now()
	local claims, member = state.war.claims, state.member
	local spot = me:CoverSpot(center, radius, threat, exclude, function(p)
		return not claims:FreeFor(Squad.Key("cover", p), member, now)
	end)
	if self.claimed then claims:Release(self.claimed, member) end
	self.claimed = spot and Squad.Key("cover", spot) or nil
	if self.claimed then claims:Take(self.claimed, member, now, COVER_CLAIM) end
	return spot
end

-- Renews the member's cover claim while it holds the spot.
function Objective:KeepClaim(me)
	if self.claimed then self.state.war.claims:Take(self.claimed, self.state.member, me:Now(), COVER_CLAIM) end
end

-- A member far from its leader in a fight: to the leader first.
function Objective:Regroup(me)
	local member = self.state.member
	local leader = LeaderOf(member)
	if not leader or me:RangeTo(leader.pos) <= REGROUP_RANGE then return nil end
	local spot = Geometry.Toward(leader.pos, me:Position(), SQUAD_SPACING * (member.place or 1))
	local state = self.state
	state.tactic, state.element = "regrouping on its leader", "moving"
	state.goal, state.coverSpot = spot, nil
	me:MoveTo(spot, RUN)
	return self:Continue()
end

function Objective:Fight(me, goal, contact)
	local state, now = self.state, me:Now()
	local fireTeam = state.member.fireTeam
	state.fighting = true
	state.patrolling = false
	self.anchor = nil
	local tactic = self.role.tactic
	if tactic == "raid" or tactic == "support" then self:Gadget(me, contact, now) end
	local regroup = self:Regroup(me)
	if regroup then return regroup end
	if tactic == "attack" then return self:Attack(me, goal, contact, fireTeam, now) end
	-- raiders always go round first, then bound onto the line itself
	if tactic == "raid" then return self:Attack(me, self.role.Line(state.war:Field(), state.member) or goal, contact, fireTeam, now, true) end
	if tactic == "support" then return self:Defend(me, goal, contact, fireTeam, now, true) end
	return self:Defend(me, goal, contact, fireTeam, now)
end

-- Bounding overwatch toward the goal, after a flank for a flanking team.
function Objective:Attack(me, goal, contact, fireTeam, now, flanks)
	local state = self.state
	if (flanks or Tactics.Flanks(fireTeam)) and not fireTeam.flankDone then
		if not fireTeam.flank then
			fireTeam.flank = Tactics.FlankPoint(me:Position(), contact.pos, Tactics.FlankSide(fireTeam))
			fireTeam.flankUntil = now + FLANK_TIME
		end
		if now < fireTeam.flankUntil and me:RangeTo(fireTeam.flank) > FLANK_ARRIVE then
			state.tactic, state.element = "flanking", "moving"
			state.goal, state.coverSpot = fireTeam.flank, nil
			me:MoveTo(fireTeam.flank, RUN)
			return self:Continue()
		end
		fireTeam.flankDone = true
	end
	local members = state.war:FireTeamMembers(fireTeam)
	Tactics.Bound(fireTeam, now)
	Tactics.UpdateBound(fireTeam, members, now)
	local bound = fireTeam.bound
	if Tactics.Element(state.member) ~= bound.moving then
		state.tactic, state.element = "overwatch", "holding"
		state.goal, state.coverSpot = me:Position(), nil
		me:Hold()
		return self:Continue()
	end
	if self.boundFor ~= bound then
		-- the squad bounds on one line: ahead of its leader, spread by place
		local leader = LeaderOf(state.member)
		local from = leader and leader.pos or me:Position()
		local ahead = Geometry.Toward(from, goal, Tactics.BOUND_DISTANCE)
		if leader then ahead = Across(from, ahead, Lateral(state.member.place or 0) / LATERAL * SQUAD_SPACING) end
		self.boundCover = self:ClaimCover(me, ahead, BOUND_RADIUS, contact.pos)
		self.boundSpot = self.boundCover or ahead
		self.boundFor = bound
	end
	self:KeepClaim(me)
	state.goal, state.coverSpot = self.boundSpot, self.boundCover
	if me:RangeTo(self.boundSpot) <= SPOT_ARRIVE then
		Tactics.Arrived(fireTeam, state.member)
		state.tactic, state.element = "bounded; covering", "holding"
		me:Hold()
	else
		state.tactic, state.element = "bounding", "moving"
		me:MoveTo(self.boundSpot, RUN)
	end
	return self:Continue()
end

-- Holding the line from cover near the post, falling back when it breaks.
-- Support (stands) holds its cover and never falls back.
function Objective:Defend(me, post, contact, fireTeam, now, stands)
	local state = self.state
	local members = state.war:FireTeamMembers(fireTeam)
	if not stands and Tactics.ShouldFallBack(fireTeam, #members, Distance(contact.pos, post), now) then Tactics.FallBack(fireTeam, now) end
	local steps = fireTeam.fallback or 0
	if not self.cover or self.coverSteps ~= steps or me:HurtSince(self.coverAt) then
		local anchor = Tactics.FallbackPoint(post, contact.pos, steps)
		local spot = self:ClaimCover(me, anchor, COVER_RADIUS, contact.pos, self.cover)
		self.cover, self.coverFound = spot or anchor, spot ~= nil
		self.coverAt, self.coverSteps = now, steps
	end
	self:KeepClaim(me)
	state.tactic = steps > 0 and ("falling back, step " .. steps) or "holding cover"
	state.goal, state.coverSpot = self.cover, self.coverFound and self.cover or nil
	if me:RangeTo(self.cover) > SPOT_ARRIVE then
		state.element = "moving"
		me:MoveTo(self.cover, RUN)
	else
		state.element = "holding"
		me:Hold()
	end
	return self:Continue()
end

-- Contact lost: the team stands down and regroups.
function Objective:EndFight()
	local state = self.state
	if not state.fighting then return end
	state.fighting, state.tactic, state.element, state.coverSpot = false, nil, nil, nil
	self.boundSpot, self.boundFor, self.boundCover, self.cover, self.coverFound = nil, nil, nil, nil, nil
	if self.claimed then
		state.war.claims:Release(self.claimed, state.member)
		self.claimed = nil
	end
	local fireTeam = state.member.fireTeam
	if fireTeam then
		Tactics.Stand(fireTeam)
		fireTeam.flankDone = nil
		Tactics.Regroup(fireTeam)
	end
end

function Objective:OnResume(me, interrupting)
	-- after a chase, a moment before the next
	if interrupting.chase then self.chaseReadyAt = me:Now() + CHASE_COOLDOWN end
	if interrupting.spot then
		-- rest where it got to; a spot given up is traded for another at once
		local rest = interrupting.role == PATROL and PATROL_REST or WANDER_REST
		self.restUntil = interrupting.failed and 0 or me:Now() + rest
	elseif interrupting.failed then
		self.retryAt = me:Now() + RETRY_WAIT
	end
	return self:Continue()
end

-- Idle (no role, or one its doctrine lacks): the engine's AI has the
-- soldier until it is given one.
function Idle:Init(state)
	self.state = state
end

function Idle:Update(me)
	if ObjectiveClass(self.state) ~= Idle then return self:ChangeTo(ObjectiveFor(self.state), "given a role") end
	StopFollowing(self.state, me)
	me:Release()
	return self:Continue()
end

-------------------------------------------------------------------------------
-- The monitors (docs/aiwar-command.md §1)

-- A monitor holds the state and contains one action.
local function Monitor(name, contained)
	local class = N.Action:Extend(name)
	function class:Init(state) self.state = state end
	function class:InitialContainedAction(me) return contained(self.state) end
	return class
end

-- A monitor that only passes through to what it contains, which the debug
-- layer's TDBN leaves out (games.npc.nextbot's Action.passthrough).
local function PassthroughMonitor(name, contained)
	local class = Monitor(name, contained)
	class.passthrough = true
	return class
end

-- The side actions (PayloadAttacker, PayloadDefender, ...): each runs the
-- member's job, and changes itself when the member's side changes.
local SIDE_OF = {} -- doctrine -> side -> its side action class

local function SideFor(state)
	local field = state.war:Field()
	local doctrine = DoctrineOf(field)
	local side = doctrine.Side(field, state.member)
	local classes = SIDE_OF[doctrine] or {}
	SIDE_OF[doctrine] = classes
	if not classes[side] then
		local class = Monitor(doctrine.SIDES[side], ObjectiveFor)
		class.side, class.doctrine = side, doctrine
		class.shortName = doctrine.SHORT_SIDES and doctrine.SHORT_SIDES[side]
		function class:Update(me)
			local now = state.war:Field()
			if DoctrineOf(now) ~= self.doctrine or self.doctrine.Side(now, self.state.member) ~= self.side then
				return self:ChangeTo(SideFor(self.state), "side changed")
			end
			return self:Continue()
		end
		classes[side] = class
	end
	return classes[side]:New(state)
end

-- ScenarioMonitor: runs the member's side.
local ScenarioMonitor = PassthroughMonitor("ScenarioMonitor", SideFor)

-- The squad roles: each runs the job; which one runs follows the member's
-- place in its squad (games.ns.squad's Kind), changing itself when
-- that changes (a leader died, a hero joined, a new job's squad).
local SquadRoles = {}

local function SquadRole(kind, name)
	local class = Monitor(name, function(state) return ScenarioMonitor:New(state) end)
	class.kind = kind
	function class:Update(me)
		local now = Squad.Kind(self.state.member)
		if now ~= self.kind then return self:ChangeTo(SquadRoles[now]:New(self.state), "now " .. now) end
		return self:Continue()
	end
	SquadRoles[kind] = class
	return class
end

-- SquadLeader: does its job; its squad takes its line, place and enemy from it.
SquadRole("leader", "SquadLeader")

-- SquadMember (TF2's CTFBotEscortSquadLeader): does its job, and fights the
-- enemy its leader fights when that is one of the two DrGBase compares.
local SquadMember = SquadRole("member", "SquadMember")

function SquadMember:SelectMoreDangerousThreat(me, a, b)
	local fireTeam = self.state.member.fireTeam
	local leader = fireTeam and Squad.Leader(fireTeam)
	local focus = leader and leader ~= self.state.member and leader.enemy
	if focus ~= nil and (a == focus or b == focus) then return focus end
	return N.ANSWER_UNDEFINED
end

-- Solo: in no squad (no job yet).
SquadRole("solo", "Solo")

-- SquadMonitor: leader, member or solo.
local SquadMonitor = PassthroughMonitor("SquadMonitor", function(state)
	return SquadRoles[Squad.Kind(state.member)]:New(state)
end)

-- Post-round carnage (features.aiwar.model's PHASES.humiliation,
-- games.ns.hunt; TF2's CTFBotTacticalMonitor "Get the losers!").
-- The winners SeekAndDestroy: at a loser in sight, reporting it on the
-- war's hunt board and holding to fire once within HUNT_CLOSE; with none,
-- on a trip to the nearest fresh sighting, else to the losers' spawns. The
-- losers are Humiliated: they run from what they see and otherwise hide at
-- their own spawn. Both end with the round. In sudden death both sides
-- SeekAndDestroy, every live enemy on their boards (PHASES' sightAll).
HUNT_CLOSE = 300

-- The hunt's and the hiding's trips, travelled as a role's goal is.
local HUNT = {
	name = "Hunt",
	arrive = Hunt.HUNT_ARRIVE,
	leash = 0,
	rushes = false,
	giveUp = Hunt.HUNT_GIVE_UP,
	gait = RUN,
}
local HIDE = {
	name = "Hide",
	arrive = Hunt.HIDE_ARRIVE,
	leash = 0,
	rushes = false,
	giveUp = WANDER_GIVE_UP,
	gait = RUN,
}

-- Whether the member hunts its enemies now: its side won the round, or
-- it is sudden death, when both sides do.
function Hunting(field, member)
	return field ~= nil and field.phase.hunt and (field.phase.everyoneHunts or field.winner == member.team)
end

-- Humiliated: its side lost the round. Orders are dropped, it holds its
-- fire and hurries, until the next round rearms it (TF2's losers retreat:
-- CTFBotTacticalMonitor). From a winner in sight it flees to cover within
-- FLEE_COVER away from it (else RETREAT_DISTANCE straight away), picking
-- again once the winner has moved FLEE_REPICK or the spot is reached; with
-- none in sight it runs to its nearest spawn and hides there.
local Humiliated = N.Action:Extend("Humiliated")

function Humiliated:Init(state)
	self.state = state
	self.retryAt = 0
end

function Humiliated:OnStart(me)
	StopFollowing(self.state, me)
	me:Stand()
	me:Release()
	return self:Continue()
end

local function KeepHiding(field, soldier)
	if not soldier:IsDisarmed() then return false, "rearmed" end
	if soldier:HasEnemy() then return false, "found" end
	return true
end

function Humiliated:Update(me)
	if not me:IsDisarmed() then return self:Done("rearmed") end
	local state, now = self.state, me:Now()
	local threat = me:HasEnemy() and me:EnemyPosition()
	if threat then return self:Flee(me, threat) end
	self.flee, self.fleeFrom = nil, nil
	local field = state.war:Field()
	local hideout = OrdersRun(field) and Hunt.Hideout(field, state.member, me:Position()) or nil
	if not hideout or me:RangeTo(hideout) <= Hunt.HIDE_ARRIVE or now < self.retryAt then
		state.tactic, state.goal = "hiding", hideout
		me:Hold()
		return self:Continue()
	end
	state.tactic, state.goal = "running to hide", hideout
	return self:SuspendFor(Travel:New(state, HIDE, hideout, KeepHiding), "running to hide")
end

function Humiliated:Flee(me, threat)
	local state = self.state
	if not self.flee or Distance(threat, self.fleeFrom) > Hunt.FLEE_REPICK or me:RangeTo(self.flee) <= SPOT_ARRIVE then
		self.flee = me:CoverSpot(me:Position(), Hunt.FLEE_COVER, threat) or Behind(me:Position(), threat, RETREAT_DISTANCE)
		self.fleeFrom = threat
	end
	state.tactic, state.goal = "fleeing", self.flee
	me:MoveTo(self.flee, RUN)
	return self:Continue()
end

function Humiliated:OnResume(me, interrupting)
	if interrupting.failed then self.retryAt = me:Now() + RETRY_WAIT end
	return self:Continue()
end

function Humiliated:ShouldAttack(me, them) return N.ANSWER_NO end
function Humiliated:ShouldHurry(me) return N.ANSWER_YES end

-- SeekAndDestroy (CTFBotSeekAndDestroy): its side won the round.
local SeekAndDestroy = N.Action:Extend("SeekAndDestroy")

function SeekAndDestroy:Init(state)
	self.state = state
	self.retryAt = 0
end

function SeekAndDestroy:OnStart(me)
	StopFollowing(self.state, me)
	me:Stand()
	return self:Continue()
end

-- A hunt trip goes on while the hunt does and no loser is in sight.
local function KeepHunting(member)
	return function(field, soldier)
		if not Hunting(field, member) then return false, "the round is over" end
		if soldier:HasEnemy() then return false, "a loser in sight" end
		return true
	end
end

function SeekAndDestroy:Update(me)
	local state, now = self.state, me:Now()
	local field, member, war = state.war:Field(), state.member, state.war
	if not Hunting(field, member) then return self:Done("the round is over") end
	local enemy = me:HasEnemy() and me:EnemyPosition()
	if enemy then
		war.hunt:Report(member.team, me:Enemy(), enemy, now)
		state.tactic, state.goal = "chasing down the losers", enemy
		if me:RangeTo(enemy) <= HUNT_CLOSE then me:Hold() else me:MoveTo(enemy, RUN) end
		return self:Continue()
	end
	local goal = Hunt.HuntGoal(field, member, war.hunt:Sightings(member.team, now), me:Position())
	state.tactic, state.goal = "seeking the losers", goal
	if not goal or me:RangeTo(goal) <= Hunt.HUNT_ARRIVE or now < self.retryAt then
		me:Hold()
		return self:Continue()
	end
	return self:SuspendFor(Travel:New(state, HUNT, goal, KeepHunting(member)), "hunting")
end

function SeekAndDestroy:OnResume(me, interrupting)
	if interrupting.failed then self.retryAt = me:Now() + RETRY_WAIT end
	return self:Continue()
end

function SeekAndDestroy:ShouldRetreat(me) return N.ANSWER_NO end
function SeekAndDestroy:ShouldHurry(me) return N.ANSWER_YES end

-- TacticalMonitor: what keeps the soldier alive comes before its squad and
-- its job.
-- RetreatToCover (CTFBotRetreatToCover): a soldier hurt badly (under
-- RETREAT_HEALTH of its most) or hard (RETREAT_BURST of its most in the
-- last RETREAT_WINDOW seconds) gets off the cart and runs to cover from its
-- threat (else RETREAT_DISTANCE away from it), and stays there until healed
-- back to RETREAT_RECOVER (its medics come to the most hurt) or RETREAT_TIME
-- passes; then back to its squad and job, and no retreat for
-- RETREAT_COOLDOWN.
RETREAT_HEALTH, RETREAT_BURST, RETREAT_WINDOW = 0.35, 0.4, 3
RETREAT_RECOVER, RETREAT_TIME, RETREAT_COOLDOWN = 0.7, 12, 8
RETREAT_DISTANCE, RETREAT_COVER = 400, 480

local function HealthShare(me)
	return me:Health() / max(me:MaxHealth(), 1)
end

local RetreatToCover = N.Action:Extend("RetreatToCover")
local FindHealth = N.Action:Extend("FindHealth")
local CallMedic = N.Action:Extend("CallMedic")

function RetreatToCover:Init(state) self.state = state end

function RetreatToCover:OnStart(me)
	local state, now = self.state, me:Now()
	state.lastEnemyAt = now
	me:Stand()
	StopFollowing(state, me)
	self.untilAt = now + RETREAT_TIME
	local contact = state.member.fireTeam and Tactics.Contact(state.member.fireTeam, now)
	local threat = me:EnemyPosition() or (contact and contact.pos)
	if threat then
		self.spot = me:CoverSpot(me:Position(), RETREAT_COVER, threat) or Behind(me:Position(), threat, RETREAT_DISTANCE)
	end
	state.retreats = (state.retreats or 0) + 1
	me:Announce(Speech.CONCEPT_RETREAT_TO_COVER)
	return self:Continue()
end

-- Where its threat is: the enemy it has, else its fire team's contact.
local function ThreatPosition(state, me)
	local contact = state.member.fireTeam and Tactics.Contact(state.member.fireTeam, me:Now())
	return me:EnemyPosition() or (contact and contact.pos)
end

-- A medic treats it (Objective:Heal marks its patient's member).
local function Treated(member, now)
	return member.medicAt ~= nil and now - member.medicAt <= MEDIC_TREATING
end

-- FindHealth's kit, when it should leave cover for one now
-- (features.aiwar.health): none while a medic treats it.
local function KitWorthIt(state, me)
	local now = me:Now()
	if Treated(state.member, now) then return nil end
	local urgency = Health.Urgency(HealthShare(me), me:Burning())
	local threat = ThreatPosition(state, me)
	local safety = Health.Safety(threat and me:RangeTo(threat), now - (state.lastEnemyAt or now))
	if not Health.Leaves(urgency, safety) then return nil end
	return Health.PickKit(me:HealthKits(), me:Position(), Health.SearchRange(urgency))
end

function RetreatToCover:Update(me)
	local state, now = self.state, me:Now()
	-- the round won or lost: the monitor above hunts or hides
	if me:IsDisarmed() or Hunting(state.war:Field(), state.member) then return self:Done("the round is over") end
	-- a retreat taken before its job would refuse one (the bomb picked up)
	if AskInterrupted(self, me, "ShouldRetreat") == N.ANSWER_NO then return self:Done("its job will not retreat") end
	if HealthShare(me) >= RETREAT_RECOVER or now >= self.untilAt then
		state.retreatReadyAt = now + RETREAT_COOLDOWN
		state.hurtLog = {}
		return self:Done("recovered")
	end
	if me:HasEnemy() then state.lastEnemyAt = now end
	local kit = KitWorthIt(state, me)
	if kit then return self:ChangeTo(FindHealth:New(state, kit), "health nearby, safe enough to go") end
	state.tactic = "retreating to cover"
	state.goal = self.spot
	if self.spot and me:RangeTo(self.spot) > SPOT_ARRIVE then me:MoveTo(self.spot, RUN) else me:Hold() end
	return self:Continue()
end

function RetreatToCover:ShouldHurry(me) return N.ANSWER_YES end

-- FindHealth (CTFBotGetHealth): out of cover for the kit, running, until
-- healed to Health.OK, the kit is gone (taken by someone, or respawning),
-- or FIND_HEALTH_TIME passes; then back to its squad and job, no retreat
-- for RETREAT_COOLDOWN.
FIND_HEALTH_TIME = 15

function FindHealth:Init(state, kit)
	self.state, self.kit = state, kit
end

function FindHealth:OnStart(me)
	self.untilAt = me:Now() + FIND_HEALTH_TIME
	me:Announce(Speech.CONCEPT_GET_HEALTH)
	return self:Continue()
end

local function StillThere(kits, kit)
	for _, k in ipairs(kits) do
		if k.handle == kit.handle then return true end
	end
	return false
end

function FindHealth:Update(me)
	local state, now = self.state, me:Now()
	if me:IsDisarmed() or Hunting(state.war:Field(), state.member) then return self:Done("the round is over") end
	local declined = AskInterrupted(self, me, "ShouldPickUp", self.kit) == N.ANSWER_NO
	local why = (declined and "its job will not stop for health") or (HealthShare(me) >= Health.OK and "healed") or (not StillThere(me:HealthKits(), self.kit) and "the kit is gone")
		or (now >= self.untilAt and "gave up")
	if why then
		state.retreatReadyAt = now + RETREAT_COOLDOWN
		state.hurtLog = {}
		return self:Done(why)
	end
	state.tactic, state.goal = "fetching health", self.kit.pos
	me:MoveTo(self.kit.pos, RUN)
	return self:Continue()
end

function FindHealth:ShouldHurry(me) return N.ANSWER_YES end

-- CallMedic (TF2's "MEDIC!"): under CALL_MEDIC_HEALTH of its most it calls
-- for a medic (the port's CallMedic: its side's medics answer callers
-- first, its teammates see TF2's bubble over it), once a
-- CALL_MEDIC_COOLDOWN, and goes on with what it was doing.
CALL_MEDIC_HEALTH, CALL_MEDIC_COOLDOWN = 0.75, 10

function CallMedic:Init(state) self.state = state end

function CallMedic:OnStart(me)
	me:CallMedic()
	self.state.medicCallReadyAt = me:Now() + CALL_MEDIC_COOLDOWN
	return self:Done("called for a medic")
end

-- TacticalMonitor: what keeps the soldier alive comes before its squad and
-- its job: humiliation, then the hunt of the losers, then retreat, which
-- what it runs may refuse (ShouldRetreat NO).
local TacticalMonitor = PassthroughMonitor("TacticalMonitor", function(state) return SquadMonitor:New(state) end)

-- The damage it took, kept for RETREAT_WINDOW (OnInjured, from DrGBase).
function TacticalMonitor:OnInjured(me, attacker, amount)
	local log = self.state.hurtLog or {}
	log[#log + 1] = { at = me:Now(), amount = amount or 0 }
	self.state.hurtLog = log
	return self:TryContinue()
end

local function RecentDamage(state, now)
	local total, kept = 0, {}
	for _, hurt in ipairs(state.hurtLog or {}) do
		if now - hurt.at <= RETREAT_WINDOW then
			total = total + hurt.amount
			kept[#kept + 1] = hurt
		end
	end
	state.hurtLog = kept
	return total
end

function TacticalMonitor:Update(me)
	local state, now = self.state, me:Now()
	if me:IsDisarmed() then return self:SuspendFor(Humiliated:New(state), "humiliated") end
	if Hunting(state.war:Field(), state.member) then return self:SuspendFor(SeekAndDestroy:New(state), "get the losers") end
	if now >= (state.retreatReadyAt or 0) then
		local badly = HealthShare(me) < RETREAT_HEALTH
		local hard = RecentDamage(state, now) >= RETREAT_BURST * me:MaxHealth()
		if (badly or hard) and self:QueryBelow(me, "ShouldRetreat") ~= N.ANSWER_NO then
			return self:SuspendFor(RetreatToCover:New(state), badly and "badly hurt" or "hurt hard")
		end
	end
	if HealthShare(me) < CALL_MEDIC_HEALTH and now >= (state.medicCallReadyAt or 0) and not Treated(state.member, now) then
		return self:SuspendFor(CallMedic:New(state), "hurt: calling for a medic")
	end
	return self:Continue()
end

-- `to` turned `degrees` about `from`, level (left for a positive turn).
local function Turn(from, to, degrees)
	if degrees == 0 then return to end
	local a = degrees * pi / 180
	local dx, dy = to.x - from.x, to.y - from.y
	return { x = from.x + dx * cos(a) - dy * sin(a), y = from.y + dx * sin(a) + dy * cos(a), z = to.z }
end

-- Where the member watches now (Watching, above), or nil with no threat known.
function WatchPoint(state, me)
	local member, now = state.member, me:Now()
	local contact = member.fireTeam and Tactics.Contact(member.fireTeam, now)
	if contact then return contact.pos end
	local heard = state.heard
	if heard and now - heard.time <= HEARD_MEMORY then return heard.pos end
	local field = state.war:Field()
	local threat = field and DoctrineOf(field).Threat(field, member)
	if not threat then return nil end
	return Turn(me:Position(), threat, GLANCES[(floor(now / GLANCE_TIME) + member.slot) % #GLANCES + 1])
end

-- StrategyMonitor: applies the war's allocation for this soldier. It
-- decides nothing: the War (later the Commander) decides, and each job
-- checks the member's job itself (ChangeTo on "new role").
local StrategyMonitor = PassthroughMonitor("StrategyMonitor", function(state) return TacticalMonitor:New(state) end)

-- It also keeps the member's record current with what its squad reads of
-- it: where it is and the enemy it fights (games.ns.squad); and
-- tells the soldier where to watch.
function StrategyMonitor:Update(me)
	local member = self.state.member
	self.state.job = member.role
	-- only a pusher rides its cart
	if member.role ~= AiWar.PUSH and me:IsSeated() then me:Stand() end
	member.pos = me:Position()
	member.enemy = me:HasEnemy() and me:Enemy() or nil
	me:Watch(WatchPoint(self.state, me))
	return self:Continue()
end

-- Gunfire heard at pos (the controller's hearing): watched for HEARD_MEMORY.
function StrategyMonitor:OnHeard(me, pos)
	self.state.heard = { pos = pos, time = me:Now() }
	return self:TryContinue()
end

-------------------------------------------------------------------------------
-- The variant

local NextSoldier = PassthroughMonitor("NextSoldier", function(state) return StrategyMonitor:New(state) end)

function NextSoldier:Update(me)
	if not me:IsAlive() then return self:Done("dead") end
	return self:Continue()
end

-- The job part of a full action name (what follows ScenarioMonitor/ and
-- the side), the squad role it runs under, and the side action; nil when it
-- runs none (suspended above).
function JobOf(fullName)
	local role, side, job = fullName:match("^NextSoldier/StrategyMonitor/TacticalMonitor/SquadMonitor/(%a+)/ScenarioMonitor/(%a+)/(.+)$")
	return job, role, side
end

-- config = { war (features.aiwar.model War), member (its roster entry) }
function NewState(config, me)
	return { war = config.war, member = config.member }
end

function InitialAction(state)
	return NextSoldier:New(state)
end
