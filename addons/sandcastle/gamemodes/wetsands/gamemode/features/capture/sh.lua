-- The capture feature's game events, with TF2's names and fields
-- (modevents.res; cp a byte, the point's index in the master's order). The
-- controller fires them; the view puts them in the kill feed. Who did it is
-- named as GMod's death notices name them: a player by their name, an NPC
-- (the AI war's soldiers) "#<class>".
local E = WS.Events
local CP_BITS = 8
local CAPPERS_BITS = 6 -- up to 63 names

-- CTeamControlPoint::InternalSetOwner: a team took the point (not a reset
-- to nobody, nor the owner a round starts with). cappers: who stood on it
-- for the capture (none for one no one made: an input, an admin's).
E.Define("game_teamplay_point_captured", {
	cp = E.UInt(CP_BITS),
	cpname = E.String(),
	team = E.Team(),
	cappers = E.List(E.String(), CAPPERS_BITS),
})

-- CTeamControlPoint::CaptureBlocked: team defended the point, blocker
-- first among its defenders on it.
E.Define("game_teamplay_capture_blocked", {
	cp = E.UInt(CP_BITS),
	cpname = E.String(),
	team = E.Team(),
	blocker = E.String(),
})
