-- NextSoldier's behaviour: the contract every behaviour of a soldier keeps,
-- whom it fights, and what it decides (its parts: intention, monitor,
-- registry).
local Port = core.port
local StateChart = generator.state_chart
local error, ipairs, pairs, setmetatable, sort, type = error, ipairs, pairs, setmetatable, table.sort, type
module("nextsoldier.behavior")

-- The soldier port: what a NextSoldier soldier's behaviours (the states of
-- nextsoldier.behavior, features.aiwar.ns_behaviors' among them) may ask of the
-- soldier they drive. The features/aiwar controller implements it over a
-- NextBot soldier (npc_nextsoldier) and over a bot player, and
-- tests/fake_soldier.lua fakes it. Some of it is still the war's, not the
-- soldier's (Sit, Stand, IsSeated and FollowCart for the cart, IsDisarmed,
-- UseGadget, Heal, CallMedic, Announce), to move out with the orders.
--
-- METHODS lists the names; PORT is them as a core.port.
--
-- Positions are plain { x, y, z } tables.
--   Now() -> the time
--   IsAlive()
--   IsDisarmed() -> my side lost the round and I may not attack (TF2's
--     humiliation)
--   Health(), MaxHealth() -> my health and its most
--   Sit() -> whether I now sit on my side's cart (I am beside it and a seat
--     is free; asking again keeps me there); Stand(): get off it, beside it;
--     IsSeated() -> whether I sit on it
--   Position() -> my origin
--   RangeTo(p) -> the distance from my origin to p
--   DoorToOpen() -> the point to look at while approaching an unlocked door,
--     else nil
--   HasEnemy() -> I have an enemy in sight (the engine's COND_SEE_ENEMY)
--   RequestRoute(goal): start a route search from here to goal, dropping
--     any search still running
--   RouteResult() -> nil while the search runs, false when there is no
--     route (either end off the nav mesh), else the waypoints to walk, the
--     last being the goal, or the nearest reachable point when the goal
--     is cut off
--   CanWalkTo(p) -> nothing solid between me and p at walking height
--   MoveTo(p, gait): go to p at the gait (features.aiwar.ns_behaviors' WALK,
--     RUN, PANIC or RUSH; default RUN), letting my own AI fight on the way
--     (at RUSH only once I am hit); a new p retargets the move
--   Release(): end any move, handing me back to the engine's own AI,
--     which fights, takes cover or idles
--   Pose() -> take a battle stance where I stand (the orders ask in setup,
--     at a rest), keeping it until Unpose or MoveTo; the stance's name, or
--     nil if I have none to take; asking again keeps the same stance
--   Unpose(): end any pose
--   PassBlocker(p) -> whether something between me and p that only NPCs
--     collide with (not players) was found and I may now pass through it
--   Detour(p) -> a point beside the solid entity (not map geometry) that
--     stands between me and p and would stop a player too (a cart, a
--     prop), which I can walk to; or nil
--   WanderSpot() -> a spot picked at random on the ground behind my side's
--     setup gates (else near me, in a straight line), or nil
--   PatrolSpot(center, radius) -> a spot picked at random on the nav mesh
--     within radius of center, or nil
--   PlansRoutes() -> whether MoveTo's engine finds its own way to any p (over
--     the map's AI node graph), so a far goal needs no route of ours
--   FollowCart() -> whether my engine now follows my side's cart as HL2's
--     rebels follow Gordon (keeping formation near it, fighting as it
--     goes); asking again keeps it following
--   Unfollow(): stop following the cart
--   EnemyPosition() -> where the enemy I have is, or nil
--   Enemy() -> the enemy I have (an opaque handle, as DrGBase's queries
--     pass them), or nil
--   EnemyHealth() -> my enemy's health as a share of its most, or nil (none,
--     or dead)
--   CoverSpot(center, radius, threat, exclude, taken) -> a spot within
--     radius of center that the threat (a position) cannot see, nearest
--     center first, not within reach of exclude, and not one taken(spot)
--     says another holds; or nil
--   HurtSince(t) -> whether I have been hurt after time t
--   Hold(): stay where I am, fighting from here
--   Heal(handle): heal that teammate (a patient's handle) with my beam
--     while it is in reach and in sight; nil stops
--   UseGadget(p) -> throw, deploy or send my role's gadget at p (a
--     grenade, a manhack, a turret), if I have one ready and in reach: its
--     name, or nil
--   RouteStale() -> whether the route I was given was planned before a
--     door shut or a brush was switched on, and may lead into it
--   Watch(p): while I stand with no enemy in sight, face p, where the
--     threat is (nil: face as I will); moving or fighting comes first
--   HealthKits() -> the health kits I may take now: { pos, handle }
--   Burning() -> whether I am on fire
--   CallMedic(): call for a medic: my side's medics answer me first a
--     while, and my teammates see that I called
--   Announce(concept): call out what I am doing (a nextsoldier.body.responserules
--     concept), if my voice has a line for it
--   LookAt(p, seconds[, priority]): look at p a while, unless I fight
--     (my head, a NextBot's; my eyes, a bot player's), whatever Watch says;
--     priority keeps a bot player's eyes there over its combat aim
--   Gesture(occasion): play a nextsoldier.body.gestures occasion (a squad
--     leader's signals among them), if my model has it and it is not
--     cooling down
--   Hop(p) -> whether I will be carried to p: only where a player could
--     walk from here to p, so never through a wall, door or gate; I am
--     moved there over a moment, running, and MoveTo and Release wait
--     until I arrive
--   Repath(): plan my way to my MoveTo target afresh from where I stand
--     (my own path between waypoints, not the route)
--   Mark(kind, detail, to): tell whoever debugs me that my orders stepped
--     in on my movement (a features.nbdebug.model MARK_* kind), what happened,
--     and where I am sent (nil: nowhere)
METHODS = {
	"Now",
	"IsAlive",
	"IsDisarmed",
	"Health",
	"MaxHealth",
	"Sit",
	"Stand",
	"IsSeated",
	"Position",
	"RangeTo",
	"DoorToOpen",
	"HasEnemy",
	"RequestRoute",
	"RouteResult",
	"CanWalkTo",
	"MoveTo",
	"Release",
	"PassBlocker",
	"Detour",
	"WanderSpot",
	"EnemyPosition",
	"Enemy",
	"EnemyHealth",
	"CoverSpot",
	"HurtSince",
	"Hold",
	"FollowCart",
	"Unfollow",
	"PlansRoutes",
	"PatrolSpot",
	"Pose",
	"Unpose",
	"RouteStale",
	"Hop",
	"Repath",
	"Mark",
	"UseGadget",
	"Heal",
	"Watch",
	"HealthKits",
	"Burning",
	"CallMedic",
	"Announce",
	"LookAt",
	"Gesture",
}

PORT = Port.New("NextSoldier soldier", METHODS)

-- NextSoldier's chart: the contract every behaviour of a soldier is a state
-- of (generator.state_chart's Chart, NextBot's Action/Behavior engine with its
-- stacks). It declares, before any behaviour exists:
--   the port    nextsoldier.behavior's: all a behaviour may ask of its soldier
--   EVENTS      what the soldier and the war tell its behaviours: what the
--               soldier suffers and senses (OnInjured, OnSight, OnLostSight,
--               OnContact, OnContactLost, OnNavAreaChanged), a shot heard
--               (OnHeard) and a death seen (OnOtherKilled)
--   QUERIES     what the soldier asks them, as TF2's bots' contextual
--               queries: ShouldAttack, ShouldHurry, ShouldRetreat,
--               ShouldPickUp, SelectMoreDangerousThreat
-- A behaviour is CHART:State(name), further extended with :Extend(name); one
-- defining an On* that is neither one of these events nor a lifecycle hook
-- (OnStart, OnEnd, OnSuspend, OnResume) is refused as it is written.
-- CHART:New(soldier, first) runs a soldier's chart from its first behaviour.
EVENTS = { "OnInjured", "OnSight", "OnLostSight", "OnContact", "OnContactLost", "OnNavAreaChanged", "OnHeard",
	"OnOtherKilled" }

QUERIES = { "ShouldAttack", "ShouldHurry", "ShouldRetreat", "ShouldPickUp", "SelectMoreDangerousThreat" }
-- Those answered yes or no (SelectMoreDangerousThreat picks between two threats).
YES_NO_QUERIES = { "ShouldAttack", "ShouldHurry", "ShouldRetreat", "ShouldPickUp" }

-- A brain with no chart behind it (a soldier's NSBrain): it answers the
-- yes-or-no queries as it is set, no until then, and hears events as nothing.
-- The path follower tool's checkboxes set it.
local ResponderClass = {}
ResponderClass.__index = ResponderClass

local function AsksYesOrNo(name)
	for _, query in ipairs(YES_NO_QUERIES) do
		if query == name then return true end
	end
	return false
end

function Responder()
	return setmetatable({ answers = {} }, ResponderClass)
end

function ResponderClass:Set(name, yes)
	if not AsksYesOrNo(name) then error("no soldier asks " .. name, 2) end
	self.answers[name] = yes
end

function ResponderClass:Answers(name)
	return self.answers[name] == true
end

function ResponderClass:Query(name)
	if not AsksYesOrNo(name) then return StateChart.ANSWER_UNDEFINED end
	return self:Answers(name) and StateChart.ANSWER_YES or StateChart.ANSWER_NO
end

function ResponderClass:Event() end

CHART = StateChart.Chart({
	name = "NextSoldier",
	port = PORT,
	events = EVENTS,
	queries = QUERIES,
	initial = function(first) return first end,
})

-- Whom a soldier fights: its dispositions toward entities and factions,
-- answered when asked, as TF2's INextBot::IsEnemy and IsFriend are, never
-- pushed to every entity on the map as they change (DrGBase's way, about
-- 34 ms a change in the war). Dispositions are the caller's values (GMod's
-- D_HT, D_LI, D_FR, D_NU); priorities are numbers, 0 when none is given.
--
-- Relations{ default, ally } -> relations: default, the disposition toward
--   anyone nothing else names; ally, toward one sharing a faction with it
-- relations:SetEntity(other, disposition[, priority]) (nil disposition: clear)
-- relations:SetFaction(faction, disposition[, priority]) (likewise)
-- relations:Join(faction), Leave(faction), InFaction(faction), Factions()
--   (sorted)
-- relations:Disposition(other, factionsOf) -> disposition, priority: its own
--   entity disposition when set; else, of its factions (factionsOf(other)
--   -> a list, asked only then), the highest priority faction disposition,
--   a tie to the faction first by name; else the ally disposition when it
--   shares one of them; else the default.
local Dispositions = {}
Dispositions.__index = Dispositions

function Relations(spec)
	if type(spec) ~= "table" or spec.default == nil then error("relations need a default disposition", 2) end
	if spec.ally == nil then error("relations need an ally disposition", 2) end
	return setmetatable({
		default = spec.default,
		ally = spec.ally,
		entities = setmetatable({}, { __mode = "k" }),
		factions = {},
		joined = {},
	}, Dispositions)
end

local function Entry(disposition, priority)
	if disposition == nil then return nil end
	return { disposition = disposition, priority = priority or 0 }
end

function Dispositions:SetEntity(other, disposition, priority)
	self.entities[other] = Entry(disposition, priority)
end

function Dispositions:SetFaction(faction, disposition, priority)
	self.factions[faction] = Entry(disposition, priority)
end

function Dispositions:Join(faction) self.joined[faction] = true end
function Dispositions:Leave(faction) self.joined[faction] = nil end
function Dispositions:InFaction(faction) return self.joined[faction] == true end

function Dispositions:Factions()
	local list = {}
	for faction in pairs(self.joined) do list[#list + 1] = faction end
	sort(list)
	return list
end

function Dispositions:Disposition(other, factionsOf)
	local own = self.entities[other]
	if own then return own.disposition, own.priority end
	local best, bestName, shared
	for _, faction in ipairs(factionsOf(other)) do
		local entry = self.factions[faction]
		if entry and (best == nil or entry.priority > best.priority
			or (entry.priority == best.priority and faction < bestName)) then
			best, bestName = entry, faction
		end
		if self.joined[faction] then shared = true end
	end
	if best then return best.disposition, best.priority end
	if shared then return self.ally, 0 end
	return self.default, 0
end
