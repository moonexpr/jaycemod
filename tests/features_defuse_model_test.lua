-- features.defuse.model: CS:S's bomb defusal as a value. RED carries the bomb
-- to a site and plants it; planted, it explodes when its timer runs out
-- unless BLU defuses it first. The round's outcome follows from the bomb and
-- who is left alive.
local T = dofile("tests/harness.lua")
local Defuse = T.require("features.defuse.model")
local Rounds = gameplay.rounds
local Teams = gameplay.teams

local RED, BLUE = Teams.RED, Teams.BLUE
local W = Rounds.WINREASON

T.test("a round begins with the bomb not yet planted", function()
	local round = Defuse.New()
	T.eq(round:State(), Defuse.CARRIED, "carried")
	T.eq(round:Site(), nil, "at no site")
	T.eq(round:Due(1e9), false, "never due")
end)

T.test("planted at a site, it explodes after its timer", function()
	local round = Defuse.New():Plant("A", 100, 45)
	T.eq(round:State(), Defuse.PLANTED, "planted")
	T.eq(round:Site(), "A", "at A")
	T.eq(round:Remaining(110), 35, "35 s left")
	T.eq(round:Due(144.9), false, "not yet")
	T.eq(round:Due(145), true, "due")
	T.eq(round:Explode(145):State(), Defuse.EXPLODED, "exploded")
end)

T.test("the rules refuse what does not follow", function()
	local carried, planted = Defuse.New(), Defuse.New():Plant("A", 0, 45)
	T.eq(pcall(function() carried:Defuse() end), false, "nothing to defuse")
	T.eq(pcall(function() carried:Explode(1000) end), false, "nothing to explode")
	T.eq(pcall(function() planted:Plant("B", 1, 45) end), false, "planted once")
	T.eq(pcall(function() planted:Explode(10) end), false, "not before its time")
	T.eq(pcall(function() Defuse.New():Plant("A", 0, 0) end), false, "a timer of none refused")
	local defused = planted:Defuse()
	T.eq(defused:State(), Defuse.DEFUSED, "defused")
	T.eq(pcall(function() defused:Explode(1000) end), false, "a defused bomb never explodes")
end)

local function Alive(red, blue) return { [RED] = red, [BLUE] = blue } end

T.test("before the plant: either side wins by killing the other, BLU when time runs out", function()
	local round = Defuse.New()
	T.eq(round:Outcome(Alive(2, 2), false), nil, "both alive: on")
	local winner, reason = round:Outcome(Alive(0, 2), false)
	T.eq(winner == BLUE and reason == W.OPPONENTS_DEAD, true, "RED dead: BLU")
	winner, reason = round:Outcome(Alive(2, 0), false)
	T.eq(winner == RED and reason == W.OPPONENTS_DEAD, true, "BLU dead: RED")
	winner, reason = round:Outcome(Alive(2, 2), true)
	T.eq(winner == BLUE and reason == W.TARGET_SAVED, true, "time out: the targets saved")
end)

T.test("after the plant: BLU must defuse, RED wins by the blast or by killing BLU", function()
	local round = Defuse.New():Plant("A", 0, 45)
	T.eq(round:Outcome(Alive(0, 2), false), nil, "RED dead: BLU must still defuse")
	T.eq(round:Outcome(Alive(2, 2), true), nil, "time out: the bomb decides")
	T.eq(round:Outcome(Alive(0, 0), false), nil, "both dead: the bomb decides")
	local winner, reason = round:Outcome(Alive(2, 0), false)
	T.eq(winner == RED and reason == W.OPPONENTS_DEAD, true, "BLU dead: RED")
	winner, reason = round:Defuse():Outcome(Alive(0, 0), false)
	T.eq(winner == BLUE and reason == W.BOMB_DEFUSED, true, "defused: BLU")
	winner, reason = round:Explode(45):Outcome(Alive(0, 3), false)
	T.eq(winner == RED and reason == W.TARGET_BOMBED, true, "exploded: RED")
end)

T.test("who a team left alone wins against, for the rounds' elimination check", function()
	local carried, planted = Defuse.New(), Defuse.New():Plant("A", 0, 45)
	T.eq(carried:EliminationWins(RED), true, "RED alone before the plant")
	T.eq(carried:EliminationWins(BLUE), true, "BLU alone before the plant")
	T.eq(planted:EliminationWins(RED), true, "RED alone after: BLU cannot defuse")
	T.eq(planted:EliminationWins(BLUE), false, "BLU alone after: it must defuse")
	T.eq(planted:EliminationWins(nil), false, "none alone after: the bomb decides")
	T.eq(carried:EliminationWins(nil), true, "none alone before: a draw, as ever")
end)

T.finish()
