-- The soldier port: what features.aiwar.orders may ask of the
-- soldier it drives. The features/aiwar controller implements it over a
-- DrGBase NextBot soldier (ws_drg_soldier) and tests/fake_soldier.lua
-- fakes it.
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
--   HasEnemy() -> I have an enemy in sight (the engine's COND_SEE_ENEMY)
--   RequestRoute(goal): start a route search from here to goal, dropping
--     any search still running
--   RouteResult() -> nil while the search runs, false when there is no
--     route (either end off the nav mesh), else the waypoints to walk, the
--     last being the goal, or the nearest reachable point when the goal
--     is cut off
--   CanWalkTo(p) -> nothing solid between me and p at walking height
--   MoveTo(p, gait): go to p at the gait (features.aiwar.orders' WALK,
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
--   Announce(concept): call out what I am doing (a games.nextsoldier.speech
--     concept), if my voice has a line for it
--   Hop(p) -> whether I will be carried to p: only where a player could
--     walk from here to p, so never through a wall, door or gate; I am
--     moved there over a moment, running, and MoveTo and Release wait
--     until I arrive
--   Repath(): plan my way to my MoveTo target afresh from where I stand
--     (my own path between waypoints, not the route)
--   Mark(kind, detail, to): tell whoever debugs me that my orders stepped
--     in on my movement (a foundation.npc.debug MARK_* kind), what happened,
--     and where I am sent (nil: nowhere)
module(...)

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
}
