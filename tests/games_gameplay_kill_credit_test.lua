local T = dofile("tests/harness.lua")
local Teams = gameplay.teams
local Credit = gameplay.kill_credit

T.test("windows and the respawn modifier are defined", function()
	T.defined(Credit.HISTORY, "history")
	T.defined(Credit.ENVIRONMENT_WINDOW, "environment window")
	T.defined(Credit.ASSIST_WINDOW, "assist window")
	T.defined(Credit.CREDITED_RESPAWN, "credited respawn")
end)

-- CTFPlayer::OnTakeDamage: only damagers on another team are remembered,
-- so a rocket jump or a teammate's splash never takes a kill.
T.test("an enemy's hit is remembered; one's own and a teammate's are not", function()
	T.eq(Credit.Remembered(Teams.RED, Teams.BLUE, false), true, "enemy")
	T.eq(Credit.Remembered(Teams.RED, Teams.RED, false), false, "teammate")
	T.eq(Credit.Remembered(Teams.RED, Teams.RED, true), false, "self")
	T.eq(Credit.Remembered(Teams.UNASSIGNED, Teams.UNASSIGNED, false), false, "no teams")
end)

T.test("no one hurt the victim: no one is credited", function()
	local damagers = Credit.Damagers()
	T.eq(damagers:Recent(10, Credit.ENVIRONMENT_WINDOW), nil, "empty")
end)

T.test("the latest damager within the window is credited", function()
	local damagers = Credit.Damagers()
	damagers:Record("a", 1)
	damagers:Record("b", 2)
	T.eq(damagers:Recent(2, Credit.ENVIRONMENT_WINDOW), "b", "latest")
	T.eq(damagers:Recent(2 + Credit.ENVIRONMENT_WINDOW, Credit.ENVIRONMENT_WINDOW), "b", "at the window's edge")
	T.eq(damagers:Recent(2 + Credit.ENVIRONMENT_WINDOW + 0.01, Credit.ENVIRONMENT_WINDOW), nil, "past it")
end)

T.test("a damager hitting again moves to the front, held once", function()
	local damagers = Credit.Damagers()
	damagers:Record("a", 1)
	damagers:Record("b", 2)
	damagers:Record("a", 3)
	T.eq(damagers:Recent(3, Credit.ENVIRONMENT_WINDOW), "a", "a again")
	T.eq(damagers:Recent(3, Credit.ENVIRONMENT_WINDOW, "a"), "b", "then b")
end)

-- CTFGameRules::GetAssister: the latest damager in the assist window other
-- than the one credited.
T.test("an assister is the latest other damager within the assist window", function()
	local damagers = Credit.Damagers()
	damagers:Record("a", 1)
	damagers:Record("b", 2)
	T.eq(damagers:Recent(2, Credit.ASSIST_WINDOW, "b"), "a", "a assists b")
	T.eq(damagers:Recent(1 + Credit.ASSIST_WINDOW + 0.01, Credit.ASSIST_WINDOW, "b"), nil, "a too long ago")
	T.eq(damagers:Recent(2, Credit.ASSIST_WINDOW, "a"), "b", "b assists a")
end)

T.test("only the latest HISTORY damagers are held", function()
	local damagers = Credit.Damagers()
	for i = 1, Credit.HISTORY + 1 do damagers:Record(i, i) end
	local held = damagers:Held()
	T.eq(#held, Credit.HISTORY, "full")
	T.eq(held[1], Credit.HISTORY + 1, "the newest first")
	T.eq(held[#held], 2, "the oldest dropped")
end)

-- CTFGameRules::CalcPlayerScore: TF_SCORE_KILL_ASSISTS_PER_POINT, whole
-- points only.
T.test("a player's points are their kills and a point for every two assists", function()
	T.eq(Credit.Points(3, 0), 3, "kills alone")
	T.eq(Credit.Points(3, 1), 3, "half a point is none")
	T.eq(Credit.Points(3, 2), 4, "two assists")
	T.eq(Credit.Points(0, 5), 2, "assists alone")
end)

T.finish()
