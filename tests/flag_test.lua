-- The flag feature's model (features.flag.model): item_teamflag's carry,
-- drop and return rules (CCaptureFlag, entity_capture_flag.cpp), the
-- capture zone's rule (CCaptureZone, func_capture_zone.cpp), the CTF tally
-- against tf_flag_caplimit, the CTF mode and what TF2's flag panel shows
-- (CTFFlagStatus, tf_hud_flagstatus.cpp).
local T = dofile("tests/harness.lua")
local Flag = T.require("features.flag.model")
local Rounds = T.require("games.gameplay.rounds")
local State = T.require("games.gameplay.rounds.state")
local Teams = T.require("games.gameplay.teams")

local NOBODY, RED, BLUE = Teams.UNASSIGNED, Teams.RED, Teams.BLUE
local CARRIER, OTHER = "carrier", "other"
local NOW = 100
local CTF = {
	ownersCarry = false,
	mayBeCapped = true,
}
local MVM = {
	ownersCarry = true,
	mayBeCapped = true,
}

local function Kinds(events)
	local kinds = {}
	for i, e in ipairs(events) do kinds[i] = e.kind end
	return table.concat(kinds, ",")
end

-- Who carries ----------------------------------------------------------------------

T.test("in CTF a team's flag is carried by its enemies, a neutral one by anyone", function()
	T.eq(Flag.MayCarry(RED, BLUE, false), true, "BLU takes RED's")
	T.eq(Flag.MayCarry(RED, RED, false), false, "RED keeps off its own")
	T.eq(Flag.MayCarry(NOBODY, RED, false), true, "a neutral flag, RED")
	T.eq(Flag.MayCarry(NOBODY, BLUE, false), true, "a neutral flag, BLU")
	T.eq(Flag.MayCarry(RED, NOBODY, false), false, "nobody's carrier")
end)

T.test("in MvM the bomb is carried by its own team only", function()
	T.eq(Flag.MayCarry(BLUE, BLUE, true), true, "BLU's robots carry BLU's bomb")
	T.eq(Flag.MayCarry(BLUE, RED, true), false, "RED cannot")
	T.eq(Flag.MayCarry(NOBODY, RED, true), true, "a neutral bomb, anyone")
end)

T.test("flags may be capped but in the pre-round and after a win (FlagsMayBeCapped)", function()
	T.eq(Flag.MayBeCapped(State.RND_RUNNING), true, "running")
	T.eq(Flag.MayBeCapped(State.STALEMATE), true, "sudden death")
	T.eq(Flag.MayBeCapped(State.PREROUND), false, "pre-round")
	T.eq(Flag.MayBeCapped(State.TEAM_WIN), false, "won")
end)

T.test("a zone caps for its own team's carriers, or any team's when it has none", function()
	T.eq(Flag.MayCapture(RED, RED), true, "RED's zone, RED's carrier")
	T.eq(Flag.MayCapture(RED, BLUE), false, "RED's zone, BLU's carrier")
	T.eq(Flag.MayCapture(NOBODY, BLUE), true, "a neutral zone")
end)

-- A flag's life ---------------------------------------------------------------------

T.test("a flag starts at home, enabled unless StartDisabled", function()
	local flag = Flag.New({ team = RED })
	T.eq(flag:State(), Flag.HOME, "home")
	T.eq(flag:Enabled(), true, "enabled")
	T.eq(flag:Carrier(), nil, "no carrier")
	T.eq(Flag.New({ team = RED, disabled = true }):Enabled(), false, "StartDisabled")
	T.defined(Flag.RETURN_TIME_DEFAULT, "the return time's default")
	T.eq(Flag.New({ team = RED }):ReturnTime(), Flag.RETURN_TIME_DEFAULT, "ReturnTime's default")
end)

T.test("an enemy picks the flag up; its own team, a disabled flag or a cap-free state refuse", function()
	local flag = Flag.New({ team = RED })
	T.eq(Kinds(flag:PickUp(OTHER, RED, CTF)), "", "its own team")
	T.eq(Kinds(flag:PickUp(OTHER, BLUE, { ownersCarry = false, mayBeCapped = false })), "", "in the pre-round")
	local off = Flag.New({ team = RED, disabled = true })
	T.eq(Kinds(off:PickUp(CARRIER, BLUE, CTF)), "", "disabled")
	local events = flag:PickUp(CARRIER, BLUE, CTF)
	T.eq(Kinds(events), Flag.PICKUP, "picked up")
	T.eq(events[1].team, BLUE, "by BLU")
	T.eq(flag:State(), Flag.CARRIED, "carried")
	T.eq(flag:Carrier(), CARRIER, "the carrier")
	T.eq(flag:CarrierTeam(), BLUE, "the carrier's team")
	T.eq(Kinds(flag:PickUp(OTHER, BLUE, CTF)), "", "a carried flag is not taken again")
end)

T.test("a dropped flag waits ReturnTime, then returns home", function()
	local flag = Flag.New({
		team = RED,
		returnTime = Flag.RETURN_TIME_DEFAULT,
	})
	flag:PickUp(CARRIER, BLUE, CTF)
	local events = flag:Drop(NOW)
	T.eq(Kinds(events), Flag.DROP, "dropped")
	T.eq(events[1].team, BLUE, "BLU dropped it")
	T.eq(flag:State(), Flag.DROPPED, "on the ground")
	T.eq(flag:Carrier(), nil, "nobody carries it")
	T.eq(flag:ReturnAt(), NOW + Flag.RETURN_TIME_DEFAULT, "its return")
	T.eq(Kinds(flag:Think(NOW + Flag.RETURN_TIME_DEFAULT - 1)), "", "not yet")
	local back = flag:Think(NOW + Flag.RETURN_TIME_DEFAULT)
	T.eq(Kinds(back), Flag.RETURN, "returned")
	T.eq(back[1].team, RED, "to its team")
	T.eq(flag:State(), Flag.HOME, "home")
	T.eq(Kinds(flag:Drop(NOW)), "", "a flag at home does not drop")
end)

T.test("an enemy takes a dropped flag up again; its own team leaves it", function()
	local flag = Flag.New({ team = RED })
	flag:PickUp(CARRIER, BLUE, CTF)
	flag:Drop(NOW)
	T.eq(Kinds(flag:PickUp(OTHER, RED, CTF)), "", "RED does not touch-return it")
	T.eq(Kinds(flag:PickUp(OTHER, BLUE, CTF)), Flag.PICKUP, "BLU takes it again")
	T.eq(Kinds(flag:Think(NOW + Flag.RETURN_TIME_DEFAULT)), "", "a carried flag does not return")
end)

T.test("a carrier in its own team's zone captures, and the flag goes home", function()
	local flag = Flag.New({ team = RED })
	flag:PickUp(CARRIER, BLUE, CTF)
	T.eq(Kinds(flag:Capture(RED)), "", "the enemy's zone")
	local events = flag:Capture(BLUE)
	T.eq(Kinds(events), Flag.CAPTURE, "captured")
	T.eq(events[1].team, BLUE, "for BLU")
	T.eq(flag:State(), Flag.HOME, "home again")
	T.eq(Kinds(flag:Capture(BLUE)), "", "nothing left to capture")
end)

T.test("MvM: BLU picks up its bomb and delivers it to its own zone", function()
	local bomb = Flag.New({ team = BLUE })
	T.eq(Kinds(bomb:PickUp(OTHER, RED, MVM)), "", "RED cannot")
	T.eq(Kinds(bomb:PickUp(CARRIER, BLUE, MVM)), Flag.PICKUP, "a robot takes it")
	T.eq(Kinds(bomb:Capture(BLUE)), Flag.CAPTURE, "delivered")
end)

-- CCaptureFlag::Drop: a flag dropped in a func_respawnflag zone (bigrock's
-- death pit) is reset at once, as its OnReturn says (the map's relays).
T.test("a flag dropped in a reset zone returns home at once", function()
	local flag = Flag.New({ team = BLUE, returnTime = 60000 })
	flag:PickUp(CARRIER, BLUE, MVM)
	local events = flag:Drop(NOW, true)
	T.eq(Kinds(events), Flag.DROP .. "," .. Flag.RETURN, "dropped, then returned")
	T.eq(events[1].team, BLUE, "BLU dropped it")
	T.eq(events[2].team, BLUE, "home to its team")
	T.eq(flag:State(), Flag.HOME, "home")
	flag:PickUp(CARRIER, BLUE, MVM)
	T.eq(Kinds(flag:Drop(NOW, false)), Flag.DROP, "outside one it lies where it fell")
end)

T.test("ForceDrop drops a carried flag; ForceReset returns it, ForceResetSilent quietly", function()
	local flag = Flag.New({ team = RED })
	flag:PickUp(CARRIER, BLUE, CTF)
	T.eq(Kinds(flag:Reset(false)), Flag.RETURN, "reset")
	T.eq(flag:State(), Flag.HOME, "home")
	flag:PickUp(CARRIER, BLUE, CTF)
	T.eq(Kinds(flag:Reset(true)), "", "silently")
	T.eq(flag:State(), Flag.HOME, "home, silently")
	T.eq(Kinds(flag:Reset(false)), "", "a flag at home has nothing to return")
end)

T.test("disabling a flag sends it home silently; enabling lets it be taken", function()
	local flag = Flag.New({ team = RED })
	flag:PickUp(CARRIER, BLUE, CTF)
	T.eq(Kinds(flag:SetEnabled(false)), "", "silent")
	T.eq(flag:State(), Flag.HOME, "home")
	T.eq(flag:Enabled(), false, "disabled")
	flag:SetEnabled(true)
	T.eq(Kinds(flag:PickUp(CARRIER, BLUE, CTF)), Flag.PICKUP, "enabled")
end)

-- The announcer ---------------------------------------------------------------------

T.test("each team hears its Team line when it acts and the Enemy line otherwise", function()
	local lines = Flag.Lines({
		kind = Flag.PICKUP,
		team = BLUE,
	})
	T.eq(#lines, 2, "both teams")
	local heard = {}
	for _, l in ipairs(lines) do heard[l.team] = l.sound end
	T.eq(heard[BLUE], "CaptureFlag.TeamStolen", "the takers")
	T.eq(heard[RED], "CaptureFlag.EnemyStolen", "the robbed")
	heard = {}
	for _, l in ipairs(Flag.Lines({ kind = Flag.RETURN, team = RED })) do heard[l.team] = l.sound end
	T.eq(heard[RED], "CaptureFlag.TeamReturned", "the flag's team, on its return")
	T.eq(heard[BLUE], "CaptureFlag.EnemyReturned", "the other")
end)

-- CCaptureFlag::ResetMessage for MvM's bomb (TF_FLAGTYPE_ATTACK_DEFEND):
-- its own team hears AttackDefend.TeamReturned, the defenders MvM's
-- EnemyReturned; nothing else of the bomb is announced.
T.test("MvM's bomb going home is told to both teams; its other events are not", function()
	local heard = {}
	for _, l in ipairs(Flag.InvadeLines({ kind = Flag.RETURN, team = BLUE })) do heard[l.team] = l.sound end
	T.eq(heard[BLUE], "AttackDefend.TeamReturned", "the robots")
	T.eq(heard[RED], "MVM.AttackDefend.EnemyReturned", "the defenders")
	T.eq(#Flag.InvadeLines({ kind = Flag.DROP, team = BLUE }), 0, "a drop: nothing")
	T.eq(#Flag.InvadeLines({ kind = Flag.PICKUP, team = BLUE }), 0, "a pickup: nothing")
end)

-- The CTF tally ---------------------------------------------------------------------

T.test("a team reaching tf_flag_caplimit captures wins", function()
	T.defined(Flag.CAPLIMIT_DEFAULT, "tf_flag_caplimit's default")
	local tally = Flag.NewTally()
	for _ = 1, Flag.CAPLIMIT_DEFAULT - 1 do T.eq(tally:Capture(BLUE, Flag.CAPLIMIT_DEFAULT), false, "short") end
	T.eq(tally:Captures(BLUE), Flag.CAPLIMIT_DEFAULT - 1, "counted")
	T.eq(tally:Captures(RED), 0, "RED's own count")
	T.eq(tally:Capture(BLUE, Flag.CAPLIMIT_DEFAULT), true, "the limit")
	tally:Reset()
	T.eq(tally:Captures(BLUE), 0, "a new round")
	T.eq(tally:Capture(RED, 0), false, "no limit, no win")
end)

T.test("the CTF mode: flags decide the rounds, above control points and under payload", function()
	T.eq(Flag.Mode.NAME, "ctf", "named")
	T.eq(Flag.Mode.OBJECTIVE, true, "no round limits")
	T.eq(Flag.Mode.FLAG_CAPS_SCORE, true, "caps score")
	T.eq(Flag.Mode.FLAG_OWNERS_CARRY, false, "enemies carry")
	T.eq(Flag.Mode.PRIORITY > T.require("foundation.rounds.control_points").Mode.PRIORITY, true, "over CP")
	T.eq(Flag.Mode.PRIORITY < T.require("foundation.rounds.payload").Mode.PRIORITY, true, "under payload")
	T.eq(Rounds.Mode.FLAG_CAPS_SCORE, false, "other modes' caps do not score")
	T.eq(Rounds.Mode.FLAG_OWNERS_CARRY, false, "nor do owners carry")
end)

-- The flag panel --------------------------------------------------------------------

T.test("the status icon is home, dropped or moving; MvM's bomb image dropped or carried", function()
	T.eq(Flag.StatusIcon(Flag.HOME), "hud/objectives_flagpanel_ico_flag_home", "home")
	T.eq(Flag.StatusIcon(Flag.DROPPED), "hud/objectives_flagpanel_ico_flag_dropped", "dropped")
	T.eq(Flag.StatusIcon(Flag.CARRIED), "hud/objectives_flagpanel_ico_flag_moving", "carried")
	T.eq(Flag.BombImage(Flag.HOME), "hud/bomb_dropped", "a bomb at home")
	T.eq(Flag.BombImage(Flag.DROPPED), "hud/bomb_dropped", "a dropped bomb")
	T.eq(Flag.BombImage(Flag.CARRIED), "hud/bomb_carried", "a carried bomb")
end)

T.test("the compass is the flag's team colour, pointing once the flag leaves home", function()
	T.eq(Flag.Compass(RED, Flag.HOME), "hud/objectives_flagpanel_compass_red_noarrow", "RED's at home")
	T.eq(Flag.Compass(BLUE, Flag.CARRIED), "hud/objectives_flagpanel_compass_blue", "BLU's taken")
	T.eq(Flag.Compass(NOBODY, Flag.DROPPED), "hud/objectives_flagpanel_compass_grey", "neutral")
end)

T.test("a carrier sees the carried image in the flag's colour", function()
	T.eq(Flag.CarriedImage(RED, BLUE), "hud/objectives_flagpanel_carried_red", "RED's flag")
	T.eq(Flag.CarriedImage(BLUE, RED), "hud/objectives_flagpanel_carried_blue", "BLU's flag")
	T.eq(Flag.CarriedImage(NOBODY, RED), "hud/objectives_flagpanel_carried_red", "a neutral flag, in the carrier's")
end)

local function Shown(team, state, enabled)
	return {
		team = team,
		state = state,
		enabled = enabled ~= false,
	}
end

T.test("CTF's panel shows BLU's flag on the left and RED's on the right, a neutral one where free", function()
	local red, blue = Shown(RED, Flag.HOME), Shown(BLUE, Flag.CARRIED)
	local slots = Flag.Slots({ red, blue }, false)
	T.eq(slots[Flag.SLOT_BLUE], blue, "BLU's")
	T.eq(slots[Flag.SLOT_RED], red, "RED's")
	local neutral = Shown(NOBODY, Flag.HOME)
	T.eq(Flag.Slots({ neutral }, false)[Flag.SLOT_BLUE], neutral, "a neutral flag, left")
	T.eq(Flag.Slots({ Shown(RED, Flag.HOME, false) }, false)[Flag.SLOT_RED], nil, "a disabled flag is hidden")
end)

T.test("MvM's panel shows one bomb on the left, a carried one first", function()
	local waiting, carried = Shown(BLUE, Flag.HOME), Shown(BLUE, Flag.CARRIED)
	local slots = Flag.Slots({ waiting, carried }, true)
	T.eq(slots[Flag.SLOT_BLUE], carried, "the carried bomb")
	T.eq(slots[Flag.SLOT_RED], nil, "no second panel")
	T.eq(Flag.Slots({ Shown(BLUE, Flag.HOME, false), waiting }, true)[Flag.SLOT_BLUE], waiting, "an enabled bomb")
end)

-- CTF's time limit: the team with more captures wins, by them; even
-- captures leave it to the scores (a tie of both: sudden death).
T.test("at the time limit the team with more captures wins", function()
	local W = Rounds.WINREASON
	local winner, reason = Flag.Mode:TimelimitWin({
		scores = { [Teams.RED] = 2, [Teams.BLUE] = 0 },
		captures = { [Teams.RED] = 1, [Teams.BLUE] = 3 },
	})
	T.eq(winner, Teams.BLUE, "most captures")
	T.eq(reason, W.MOST_CAPTURES, "won by them")
	winner, reason = Flag.Mode:TimelimitWin({
		scores = { [Teams.RED] = 2, [Teams.BLUE] = 0 },
		captures = { [Teams.RED] = 1, [Teams.BLUE] = 1 },
	})
	T.eq(winner, Teams.RED, "even captures: the scores")
	T.eq(reason, W.TIMELIMIT, "by points")
end)

-- CFuncRespawnRoom::RespawnRoomTouch: a carrier running into its own team's
-- respawn room drops the flag; another team's room, or one of no team, no.
T.test("a carrier in its own team's respawn room drops the flag", function()
	T.eq(Flag.DropsIn(Teams.RED, Teams.RED), true, "its own")
	T.eq(Flag.DropsIn(Teams.BLUE, Teams.RED), false, "the enemy's")
	T.eq(Flag.DropsIn(Teams.UNASSIGNED, Teams.RED), false, "no team's")
end)

T.finish()
