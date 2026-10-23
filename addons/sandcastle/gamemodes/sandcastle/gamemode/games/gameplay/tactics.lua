-- The interface a tactics engine fills: how a fire team in a fight shares
-- what it sees, moves under fire, flanks and falls back. A soldier's orders
-- ask the engine; the engine holds the doctrine. An engine is a module
-- whose functions take the fire team (a squad: { team, role, index (among
-- the squads of its role), members (by place), leader }) and keep their
-- state on it:
--
-- Contact
--   Report(fireTeam, pos, now)          a member saw an enemy at pos
--   ReportDeath(fireTeam, pos, now)     a member fell at pos
--   Contact(fireTeam, now) -> { pos, time } or nil once forgotten
-- Moving under fire
--   Element(member) -> which half of the team the member moves with
--   Bound(fireTeam, now) -> the team's bound, begun on first call:
--     { moving (the element moving), since, arrived = place -> true }
--   Arrived(fireTeam, member)           a moving member reached its spot
--   UpdateBound(fireTeam, members, now) -> whether the elements swapped
--   Stand(fireTeam)                     the fight is over: no bound, no flank
-- Flanking
--   Flanks(fireTeam) -> whether the team flanks
--   FlankSide(fireTeam) -> 1 (left) or -1 (right)
--   FlankPoint(from, enemy, side) -> where to swing out to beside the enemy
-- Falling back
--   ShouldFallBack(fireTeam, alive, enemyToPost, now) -> whether to give ground now
--   FallBack(fireTeam, now)             give a step of ground
--   Regroup(fireTeam)                   contact lost: back to the post
--   FallbackPoint(post, threat, steps) -> the post, steps further from the threat
--
-- Check(engine) hands back an engine that has every function, else refuses
-- it, naming what it lacks.
local Port = core.port
module(...)

ENGINE = Port.New("tactics engine", {
	"Report",
	"ReportDeath",
	"Contact",
	"Element",
	"Bound",
	"Arrived",
	"UpdateBound",
	"Stand",
	"Flanks",
	"FlankSide",
	"FlankPoint",
	"ShouldFallBack",
	"FallBack",
	"Regroup",
	"FallbackPoint",
})

function Check(engine)
	return ENGINE:Check(engine)
end
