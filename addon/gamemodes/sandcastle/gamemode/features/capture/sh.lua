-- The capture feature's game events, with TF2's names and fields
-- (modevents.res; cp a byte, the point's index in the master's order). The
-- controller fires them; the view words them for the rounds HUD.
local E = WETSAND.Events
local CP_BITS = 8

-- CTeamControlPoint::InternalSetOwner: a team took the point (not a reset
-- to nobody, nor the owner a round starts with). cappers: TF2's list of
-- capper indexes, which we do not track.
E.Define("teamplay_point_captured", {
	cp = E.UInt(CP_BITS),
	cpname = E.String(),
	team = E.Team(),
	cappers = E.Default(E.String(), ""),
})

-- CTeamControlPoint::CaptureBlocked: team defended the point. TF2 names the
-- blocker and victim players; ours names the defending team.
E.Define("teamplay_capture_blocked", {
	cp = E.UInt(CP_BITS),
	cpname = E.String(),
	team = E.Team(),
})
