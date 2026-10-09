-- foundation.capture.master: the team_control_point_master and its
-- mini-rounds (team_control_point_master.cpp, team_control_point_round.cpp)
-- over a PointSet: round choice, wins, stages, the base point, and the
-- seam between the capture feature's bindings, controller and models.
local T = dofile("tests/harness.lua")
local Capture = T.require("foundation.capture")
local Master = T.require("foundation.capture.master")
local Rounds = T.require("foundation.rounds")
local Teams = T.require("foundation.teams")

local NOBODY, RED, BLU = Teams.UNASSIGNED, Teams.RED, Teams.BLUE
local NO_FLAGS = 0
local POINTS_MAY_BE_CAPTURED = true

local function first(n) return 1 end
local function last(n) return n end

-- Points "p1".."pn" in index order; owners[i] = { owner, group }.
local function Points(owners)
	local points = {}
	for i, o in ipairs(owners) do
		points[i] = {
			id = "p" .. i,
			index = i,
			defaultOwner = o[1],
			startLocked = false,
			group = o[2] or 0,
			warnOnCap = Capture.CP_WARN.NORMAL,
			warnSound = "",
			printName = "",
			spawnflags = NO_FLAGS,
			previous = {},
			sounds = {},
			capSounds = {},
		}
	end
	return Capture.New({
		caplinear = true,
		points = points,
	})
end

local function Owners(n, owner)
	local list = {}
	for i = 1, n do list[i] = { owner } end
	return list
end

-- A master's config; rounds are { name, priority, restrict, points = { ids } }.
local function NewMaster(over)
	local config = {
		restrict = NOBODY,
		switchTeams = false,
		scoreStyle = Master.SCORE_PER_ROUND,
		playAllRounds = false,
		partialCapRate = 0,
		capLayout = "",
		disabled = false,
		rounds = {},
	}
	for k, v in pairs(over or {}) do config[k] = v end
	return Master.New(config)
end

local function Round(name, priority, restrict, points, printName)
	return {
		name = name,
		priority = priority,
		restrict = restrict,
		printName = printName or "",
		points = points,
	}
end

local NO_HISTORY = {
	previous = {},
	first = nil,
}

-- Each round owns one point; a round is played out when BLU owns its point
-- (restrict RED), so playable says who owns it.
local function Candidates(list, firstAfterRestart)
	local owners, rounds = {}, {}
	for i, r in ipairs(list) do
		owners[i] = { r[3] and RED or BLU }
		rounds[i] = Round(r[1], r[2], RED, { "p" .. i })
	end
	local master = NewMaster({ rounds = rounds })
	if firstAfterRestart == false then master:ChooseRound(Points(owners), NO_HISTORY, first) master:EndRound() end
	return master, Points(owners)
end

-- Wins (CheckWinConditions) ------------------------------------------------

T.test("the restricted team cannot win by capping", function()
	local set = Points(Owners(2, RED))
	T.eq(NewMaster({ restrict = RED }):Winner(set), nil)
end)

T.test("the other team wins by capping everything", function()
	local set = Points(Owners(2, BLU))
	T.eq(NewMaster({ restrict = RED }):Winner(set), BLU)
end)

T.test("restrict 1 means neither team wins by capping", function()
	local set = Points(Owners(2, BLU))
	T.eq(NewMaster({ restrict = Rounds.RESTRICT_NEITHER }):Winner(set), nil)
end)

T.test("a disabled master declares nobody", function()
	local master = NewMaster({ disabled = true })
	local set = Points(Owners(2, BLU))
	T.eq(master:Winner(set), nil)
	T.eq(master:Active(), false)
	master:Enable()
	T.eq(master:Winner(set), BLU)
	master:Disable()
	T.eq(master:Active(), false)
end)

-- cp_gorge: two RED points, restrict RED, no rounds.
T.test("cp_gorge: RED owning everything never wins; BLU owning both does", function()
	local set = Points(Owners(2, RED))
	local master = NewMaster({
		restrict = RED,
		switchTeams = true,
		scoreStyle = Master.SCORE_PER_CAPTURE,
		playAllRounds = true,
	})
	T.eq(master:Winner(set), nil, "RED's defaults")
	set:SetOwner("p1", BLU, Capture.CAUSE_CAPTURE, POINTS_MAY_BE_CAPTURED)
	T.eq(master:WouldNewOwnerWin(set, "p2", BLU), true, "the last point would win")
	T.eq(master:WouldNewOwnerWin(set, "p2", RED), false)
	T.eq(master:Winner(set), nil, "one of two")
	set:SetOwner("p2", BLU, Capture.CAUSE_CAPTURE, POINTS_MAY_BE_CAPTURED)
	T.eq(master:Winner(set), BLU)
	local forceMapReset, switchTeams = master:WinArgs(set)
	T.eq(forceMapReset, true)
	T.eq(switchTeams, true)
	T.eq(master:ScorePerCapture(), true)
	T.eq(master:PlayAllRounds(), true)
end)

-- Mini-rounds: cp_dustbowl's three stages -----------------------------------

local function Dustbowl()
	local set = Points(Owners(6, RED))
	local master = NewMaster({
		switchTeams = true,
		scoreStyle = Master.SCORE_PER_CAPTURE,
		playAllRounds = true,
		rounds = {
			Round("round_3", 25, RED, { "p5", "p6" }, "#Dustbowl_round_3"),
			Round("round_1", 100, RED, { "p1", "p2" }, "#Dustbowl_round_1"),
			Round("round_2", 50, RED, { "p3", "p4" }, "#Dustbowl_round_2"),
		},
	})
	return master, set
end

T.test("cp_dustbowl: stage 1 is chosen, in play, and won without a map reset", function()
	local master, set = Dustbowl()
	T.eq(master:PlayingMiniRounds(), true)
	T.eq(master:Current(), nil)
	T.eq(master:IsInRound("p5"), true, "no round yet: every point")
	local name, firstAfterRestart = master:RoundActivate(set, NO_HISTORY, first)
	T.eq(name, "round_1")
	T.eq(firstAfterRestart, true)
	T.eq(master:Current(), "round_1")
	T.eq(master:IsInRound("p1"), true)
	T.eq(master:IsInRound("p3"), false)
	T.eq(master:InRound().p2, true)
	T.eq(master:InRound().p3, nil)
	local stage, count, printName = master:Stage(set)
	T.eq(stage, 1)
	T.eq(count, 3)
	T.eq(printName, "#Dustbowl_round_1")
	T.eq(master:RoundActivate(set, NO_HISTORY, first), nil, "a round is already chosen")
	set:SetOwner("p1", BLU, Capture.CAUSE_CAPTURE, POINTS_MAY_BE_CAPTURED)
	T.eq(master:Winner(set), nil)
	set:SetOwner("p2", BLU, Capture.CAUSE_CAPTURE, POINTS_MAY_BE_CAPTURED)
	local winner, round = master:Winner(set)
	T.eq(winner, BLU)
	T.eq(round, "round_1")
	local forceMapReset, switchTeams = master:WinArgs(set)
	T.eq(forceMapReset, false, "two stages left")
	T.eq(switchTeams, false, "only the final win switches")
	T.eq(master:NumPlayable(set), 2)
	T.eq(master:RoundsRemaining(BLU, set), 2)
end)

T.test("cp_dustbowl: the next stage follows the ended one", function()
	local master, set = Dustbowl()
	master:RoundActivate(set, NO_HISTORY, first)
	set:SetOwner("p1", BLU, Capture.CAUSE_CAPTURE, POINTS_MAY_BE_CAPTURED)
	set:SetOwner("p2", BLU, Capture.CAUSE_CAPTURE, POINTS_MAY_BE_CAPTURED)
	T.eq(master:EndRound(), "round_1")
	T.eq(master:Current(), nil)
	T.eq(master:EndRound(), nil, "nothing left to end")
	local history = {
		previous = { "round_1" },
		first = "round_1",
	}
	local name, firstAfterRestart = master:RoundActivate(set, history, first)
	T.eq(name, "round_2")
	T.eq(firstAfterRestart, false)
	T.eq((master:Stage(set)), 2)
end)

T.test("cp_dustbowl: the last stage's win resets the map and switches teams", function()
	local master, set = Dustbowl()
	for _, id in ipairs({ "p1", "p2", "p3", "p4" }) do set:SetOwner(id, BLU, Capture.CAUSE_FORCE) end
	T.eq(master:RoundActivate(set, NO_HISTORY, first), "round_3")
	set:SetOwner("p5", BLU, Capture.CAUSE_CAPTURE, POINTS_MAY_BE_CAPTURED)
	T.eq(master:FinalPoint(set, "p6", { BLU }), true, "the map's final point")
	T.eq(master:FinalPoint(set, "p6", { RED }), false)
	T.eq(master:FinalPoint(set, "p1", { BLU }), false, "out of the round")
	set:SetOwner("p6", BLU, Capture.CAUSE_CAPTURE, POINTS_MAY_BE_CAPTURED)
	T.eq(master:Winner(set), BLU)
	local forceMapReset, switchTeams = master:WinArgs(set)
	T.eq(forceMapReset, true)
	T.eq(switchTeams, true)
end)

T.test("no final point before the last playable stage", function()
	local master, set = Dustbowl()
	master:RoundActivate(set, NO_HISTORY, first)
	set:SetOwner("p1", BLU, Capture.CAUSE_CAPTURE, POINTS_MAY_BE_CAPTURED)
	T.eq(master:FinalPoint(set, "p2", { BLU }), false)
end)

T.test("without rounds a final point is one whose capture would win", function()
	local set = Points({ { BLU }, { RED } })
	local master = NewMaster()
	T.eq(master:FinalPoint(set, "p2", { BLU }), true)
	T.eq(master:FinalPoint(set, "p2", {}), false, "no team may cap it")
end)

T.test("SetWinner 0 is a stalemate that resets the map only when nothing is playable", function()
	local master, set = Dustbowl()
	master:RoundActivate(set, NO_HISTORY, first)
	local args = master:SetWinnerArgs(NOBODY, set)
	T.eq(args.stalemate, true)
	T.eq(args.forceMapReset, false)
	for _, id in ipairs(set:Ids()) do set:SetOwner(id, BLU, Capture.CAUSE_FORCE) end
	args = master:SetWinnerArgs(NOBODY, set)
	T.eq(args.forceMapReset, true)
	args = master:SetWinnerArgs(RED, set)
	T.eq(args.stalemate, false)
	T.eq(args.switchTeams, true)
	local plain = NewMaster():SetWinnerArgs(NOBODY, Points(Owners(2, RED)))
	T.eq(plain.forceMapReset, true, "no rounds")
end)

T.test("sudden death's winner takes the round's points, or every point without rounds", function()
	local master, set = Dustbowl()
	master:RoundActivate(set, NO_HISTORY, first)
	T.eq(table.concat(master:ForcedCaps(set), " "), "p1 p2")
	T.eq(table.concat(NewMaster():ForcedCaps(Points(Owners(3, RED))), " "), "p1 p2 p3")
end)

-- G8: CTeamControlPointMaster::GetBaseControlPoint counts only the points
-- in the mini-round being played.
T.test("the base point with mini-rounds is the team's end of the round in play", function()
	local set = Points({ { BLU }, { NOBODY }, { RED }, { RED }, { RED } })
	local master = NewMaster({ rounds = { Round("mid", 1, Rounds.RESTRICT_NEITHER, { "p2", "p3" }) } })
	T.eq(master:BaseControlPoint(set, RED), 4, "no round yet: every point")
	master:RoundActivate(set, NO_HISTORY, first)
	T.eq(master:BaseControlPoint(set, RED), 2, "RED's end of the round")
	T.eq(master:BaseControlPoint(set, BLU), Capture.NO_POINT, "BLU owns neither end")
	T.eq(NewMaster():BaseControlPoint(set, BLU), 0, "without rounds")
end)

T.test("caplayout comes from the keyvalue and SetCapLayout", function()
	local master = NewMaster({ capLayout = "4, 0 1 2 3" })
	T.eq(master:CapLayout(), "4, 0 1 2 3")
	master:SetCapLayout("2, 0 1")
	T.eq(master:CapLayout(), "2, 0 1")
end)

T.test("rounds found again keep the round being played", function()
	local master, set = Dustbowl()
	master:RoundActivate(set, NO_HISTORY, first)
	master:SetRounds({ Round("round_1", 100, RED, { "p1", "p2" }), Round("round_2", 50, RED, { "p3", "p4" }) })
	T.eq(master:Current(), "round_1")
	T.eq(master:Stage(set), 1)
	master:SetRounds({ Round("round_2", 50, RED, { "p3", "p4" }) })
	T.eq(master:Current(), nil, "its round is gone")
end)

-- Round choice (GetControlPointRoundToPlay) -----------------------------------

T.test("the highest-priority playable round is chosen (pl_goldrush stage 1)", function()
	local master, set = Candidates({ { "round_c", 0, true }, { "round_a", 2, true }, { "round_b", 1, true } })
	T.eq(master:ChooseRound(set, NO_HISTORY, first), "round_a")
end)

-- Before any round is chosen (Sandbox mode keeps the rounds from
-- activating), the spawns are set up for the round that comes first; asking
-- chooses nothing.
T.test("the upcoming round is the first playable of the highest priority, and asking chooses none", function()
	local master, set = Candidates({ { "round_c", 0, true }, { "round_a", 2, true }, { "round_b", 1, true } })
	T.eq(master:Upcoming(set), "round_a", "stage 1")
	T.eq(master:Current(), nil, "nothing chosen")
	local won, wonSet = Candidates({ { "round_a", 2, false }, { "round_b", 1, true }, { "round_c", 0, true } })
	T.eq(won:Upcoming(wonSet), "round_b", "stage 1 won: stage 2")
	local done, doneSet = Candidates({ { "round_a", 2, false } })
	T.eq(done:Upcoming(doneSet), nil, "none playable")
end)

T.test("a won round is skipped for the next priority (pl_goldrush stage 2)", function()
	local master, set = Candidates({ { "round_a", 2, false }, { "round_b", 1, true }, { "round_c", 0, true } })
	T.eq(master:ChooseRound(set, NO_HISTORY, first), "round_b")
end)

T.test("no playable round chooses nothing", function()
	local master, set = Candidates({ { "round_a", 2, false } })
	T.eq(master:ChooseRound(set, NO_HISTORY, first), nil)
	T.eq(master:Current(), nil)
end)

T.test("the last played round is avoided among equals", function()
	local master, set = Candidates({ { "x", 1, true }, { "y", 1, true } }, false)
	local history = {
		previous = { "x" },
		first = nil,
	}
	T.eq(master:ChooseRound(set, history, first), "y")
	master:EndRound()
	T.eq(master:ChooseRound(set, history, last), "y")
end)

T.test("the first round after the last restart is avoided after a new restart", function()
	local master, set = Candidates({ { "x", 1, true }, { "y", 1, true }, { "z", 1, true } })
	local history = {
		previous = {},
		first = "x",
	}
	T.eq(master:ChooseRound(set, history, first), "y")
end)

T.test("previously played rounds are skipped while others remain", function()
	local master, set = Candidates({ { "x", 1, true }, { "y", 1, true }, { "z", 1, true } }, false)
	local history = {
		previous = { "z", "x" },
		first = nil,
	}
	-- last played (z) is removed first; x is previously played, so y remains
	T.eq(master:ChooseRound(set, history, first), "y")
end)

T.test("a single candidate is played even if it was played before", function()
	local master, set = Candidates({ { "x", 1, true } }, false)
	local history = {
		previous = { "x" },
		first = nil,
	}
	T.eq(master:ChooseRound(set, history, first), "x")
end)

T.test("the playable count counts playable rounds", function()
	local master, set = Candidates({ { "a", 1, true }, { "b", 1, false }, { "c", 0, true } })
	T.eq(master:NumPlayable(set), 2)
end)

T.test("a round someone has already won is not playable; its restricted team's is", function()
	local set = Points({ { BLU }, { BLU }, { RED }, { RED } })
	local master = NewMaster({ rounds = { Round("won", 1, RED, { "p1", "p2" }), Round("held", 1, RED, { "p3", "p4" }) } })
	T.eq(master:NumPlayable(set), 1)
end)

T.test("restrict 1 rounds are always playable", function()
	local set = Points({ { BLU }, { BLU } })
	local master = NewMaster({ rounds = { Round("any", 1, Rounds.RESTRICT_NEITHER, { "p1", "p2" }) } })
	T.eq(master:NumPlayable(set), 1)
end)

T.test("stage numbers follow priority order", function()
	local master, set = Candidates({ { "round_c", 0, true }, { "round_a", 2, true }, { "round_b", 1, true } })
	master:ChooseRound(set, NO_HISTORY, first)
	T.eq((master:Stage(set)), 1, "round_a")
	master:EndRound()
	set:SetOwner("p2", BLU, Capture.CAUSE_FORCE)
	master:ChooseRound(set, NO_HISTORY, first)
	T.eq((master:Stage(set)), 2, "round_b")
	master:EndRound()
	T.eq((master:Stage(set)), 0, "between rounds")
end)

-- Rounds remaining (CalcNumRoundsRemaining) --------------------------------------

T.test("rounds remaining for BLU on pl_goldrush before any stage", function()
	local set = Points(Owners(7, RED))
	local master = NewMaster({
		rounds = {
			Round("a", 2, RED, { "p1", "p2" }),
			Round("b", 1, RED, { "p3", "p4" }),
			Round("c", 0, RED, { "p5", "p6", "p7" }),
		},
	})
	T.eq(master:RoundsRemaining(BLU, set), 3)
	set:SetOwner("p1", BLU, Capture.CAUSE_FORCE)
	set:SetOwner("p2", BLU, Capture.CAUSE_FORCE)
	T.eq(master:RoundsRemaining(BLU, set), 2)
end)

T.test("rounds remaining stops when no round can make progress", function()
	local set = Points(Owners(2, RED))
	local master = NewMaster({ rounds = { Round("a", 1, RED, { "p1" }) } })
	T.eq(master:RoundsRemaining(BLU, set), 1)
	T.eq(NewMaster():RoundsRemaining(BLU, set), 0, "no rounds")
end)

-- Seams: bindings forward, the controller has the methods others call ----------

local ENTITIES = "addon/gamemodes/sandcastle/entities/entities/"
local CONTROLLER = T.ROOT .. "features/capture/sv.lua"

local function Read(path)
	local f = assert(io.open(path, "rb"))
	local text = f:read("*a")
	f:close()
	return text
end

T.test("the capture bindings require no foundation module", function()
	for _, name in ipairs({ "trigger_capture_area", "team_control_point_master", "team_control_point_round" }) do
		T.eq(Read(ENTITIES .. name .. ".lua"):find('require("foundation.', 1, true), nil, name)
	end
end)

T.test("the capture controller defines every method other features call", function()
	local text = Read(CONTROLLER)
	local methods = {
		"BindMaster", "BindRound", "BindArea", "AreaThink", "AreaInput", "MasterInput", "RoundInput",
		"Owner", "Index", "Rank", "Points", "IsInRound", "TeamMayCapture", "IsCapturing", "CappingTeam",
		"CurrentRound", "RoundPoints", "ForceOwner", "FinalPointInMap",
		"SetHudHidden", "SetPointTimer", "SetPointLocked", "SetPointUnlockTime",
	}
	for _, name in ipairs(methods) do
		T.eq(text:find("function Controller:" .. name .. "(", 1, true) ~= nil, true, name)
	end
end)

T.finish()
