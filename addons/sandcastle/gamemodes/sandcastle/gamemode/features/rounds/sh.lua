-- The rounds feature's game events. The controller fires them; the view
-- draws them.
local E = WS.Events
local SECONDS_BITS = 32

-- CTeamRoundTimer::AddTimerSeconds: seconds added to (or taken from) the
-- timer of a team (UNASSIGNED: the round's own). TF2 names the timer's
-- entity; ours names its team.
E.Define("game_teamplay_timer_time_added", {
	team = E.Team(),
	seconds_added = E.Int(SECONDS_BITS),
})

-- A mini-round starts on the kept map: each client clears the last stage's
-- ragdolls and decals, as a cleanup would.
E.Define("game_round_gore_cleared", {})
