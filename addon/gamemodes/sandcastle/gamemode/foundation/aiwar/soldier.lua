-- The soldier port: what foundation.aiwar.orders may ask of the HL2 engine
-- NPC it drives. The features/aiwar controller implements it over an NPC
-- (NPC:SetLastPosition and SCHED_FORCED_GO_RUN, the npc controller's Lua
-- route search) and tests/fake_soldier.lua fakes it.
--
-- Positions are plain { x, y, z } tables.
--   Now() -> the time
--   IsAlive()
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
--   MoveTo(p): run to p, ignoring enemies on the way (a forced move); the
--     same p again keeps the move going
--   Release(): end any forced move, handing me back to the engine's own AI,
--     which fights, takes cover or idles
--   PassBlocker(p) -> whether something between me and p that only NPCs
--     collide with (not players) was found and I may now pass through it
--   Detour(p) -> a point beside the solid entity (not map geometry) that
--     stands between me and p and would stop a player too (a cart, a
--     prop), which I can walk to; or nil
--   WanderSpot() -> a spot near me I can walk to in a straight line, picked
--     at random, or nil
--   Hop(p) -> whether I will be carried to p: only where a player could
--     walk from here to p, so never through a wall, door or gate; I am
--     moved there over a moment, running, and MoveTo and Release wait
--     until I arrive
module(...)

METHODS = {
	"Now",
	"IsAlive",
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
	"Hop",
}
