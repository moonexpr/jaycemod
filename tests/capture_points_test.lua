-- games.gameplay.capture: the PointSet (team_control_point.cpp, the master's
-- point list, CTFGameRules::TeamMayCapturePoint and the HUD's capture
-- panel), driven through real maps' keyvalues.
local T = dofile("tests/harness.lua")
local Capture = T.require("games.gameplay.capture")
local Teams = T.require("games.gameplay.teams")

local NOBODY, RED, BLU = Teams.UNASSIGNED, Teams.RED, Teams.BLUE
local NO_FLAGS = 0

-- A point spec from a map's keyvalues, as the capture controller reads them:
-- targetname, point_index, point_default_owner, then any other keys in kv.
-- previous: { [team] = { names } }.
local function Point(name, index, owner, kv)
	kv = kv or {}
	return {
		id = name,
		index = index,
		defaultOwner = owner,
		startLocked = kv.point_start_locked or false,
		group = kv.point_group or 0,
		warnOnCap = kv.point_warn_on_cap or Capture.CP_WARN.NORMAL,
		warnSound = "ControlPoint.CaptureWarn",
		printName = kv.point_printname or "",
		spawnflags = kv.spawnflags or NO_FLAGS,
		previous = kv.previous or {},
		sounds = kv.sounds or {},
		capSounds = kv.capSounds or {},
		icons = kv.icons or {},
	}
end

local function Set(points, caplinear)
	if caplinear == nil then caplinear = true end
	return Capture.New({
		caplinear = caplinear,
		points = points,
	})
end

local function Kinds(events)
	local out = {}
	for _, e in ipairs(events) do out[#out + 1] = e.kind .. ":" .. tostring(e.id) end
	return table.concat(out, ",")
end

local POINTS_MAY_BE_CAPTURED = true

-- cp_granary: five points by point_index, BLU's two, the neutral mid,
-- RED's two, no previous points, so capture is linear from each base.
local function Granary(caplinear)
	return Set({
		Point("cap_blue_2", 2, BLU, { point_printname = "Granary_cap_blue_cp2" }),
		Point("cap_red_1", 5, RED, { point_printname = "Granary_cap_red_cp1" }),
		Point("cap_blue_1", 1, BLU, { point_printname = "Granary_cap_blue_cp1" }),
		Point("cap_red_2", 4, RED, { point_printname = "Granary_cap_red_cp2" }),
		Point("cap_middle", 3, NOBODY, { point_printname = "Granary_cap_cp3" }),
	}, caplinear)
end

-- The team's base point without mini-rounds (the master's
-- GetBaseControlPoint over every point).
local function Linear(set, team)
	local points = {}
	for i, id in ipairs(set:Ids()) do
		points[i] = {
			index = set:Rank(id),
			defaultOwner = set:DefaultOwner(id),
		}
	end
	return {
		playingMiniRounds = false,
		inRound = nil,
		base = Capture.BaseControlPoint(team, points),
	}
end

T.test("cp_granary: points are ranked by point_index and keep their owners", function()
	local set = Granary()
	T.eq(table.concat(set:Ids(), " "), "cap_blue_1 cap_blue_2 cap_middle cap_red_2 cap_red_1")
	T.eq(set:Rank("cap_middle"), 2, "the mid's rank")
	T.eq(set:Index("cap_middle"), 3, "the mid's point_index")
	T.eq(set:Owner("cap_blue_2"), BLU)
	T.eq(set:Owner("cap_middle"), NOBODY)
	T.eq(set:PrintName("cap_red_1"), "Granary_cap_red_cp1")
end)

T.test("cp_granary: RED takes the mid, then BLU's second, then BLU's last, never skipping", function()
	local set = Granary()
	T.eq(set:TeamMayCapture("cap_middle", RED, Linear(set, RED)), true, "the mid")
	T.eq(set:TeamMayCapture("cap_blue_2", RED, Linear(set, RED)), false, "BLU's second before the mid")
	T.eq(set:TeamMayCapture("cap_blue_1", RED, Linear(set, RED)), false, "BLU's last before the mid")
	set:SetOwner("cap_middle", RED, Capture.CAUSE_CAPTURE, POINTS_MAY_BE_CAPTURED)
	T.eq(set:TeamMayCapture("cap_blue_2", RED, Linear(set, RED)), true, "BLU's second after the mid")
	T.eq(set:TeamMayCapture("cap_blue_1", RED, Linear(set, RED)), false, "BLU's last, skipping the second")
	set:SetOwner("cap_blue_2", RED, Capture.CAUSE_CAPTURE, POINTS_MAY_BE_CAPTURED)
	T.eq(set:TeamMayCapture("cap_blue_1", RED, Linear(set, RED)), true, "BLU's last after the second")
	T.eq(set:TeamMayCapture("cap_middle", RED, Linear(set, RED)), false, "a point RED owns")
	T.eq(set:TeamMayCapture("cap_middle", BLU, Linear(set, BLU)), false, "BLU's farthest point is its last")
	T.eq(set:TeamMayCapture("cap_blue_2", BLU, Linear(set, BLU)), true, "BLU retakes its second first")
end)

T.test("cp_granary: with tf_caplinear 0 any point not owned may be capped", function()
	local set = Granary(false)
	T.eq(set:TeamMayCapture("cap_blue_1", RED, Linear(set, RED)), true)
	T.eq(set:TeamMayCapture("cap_red_1", BLU, Linear(set, BLU)), true)
	set:SetCaplinear(true)
	T.eq(set:TeamMayCapture("cap_blue_1", RED, Linear(set, RED)), false, "the convar turned back on")
end)

T.test("cp_granary: BLU standing on RED's second while RED holds the mid is told capture is linear", function()
	local set = Granary()
	set:SetOwner("cap_middle", RED, Capture.CAUSE_CAPTURE, POINTS_MAY_BE_CAPTURED)
	local q = Linear(set, BLU)
	q.pointsMayBeCaptured = true
	q.blocked = false
	q.capping = NOBODY
	q.cappers = 1
	q.required = 0
	q.pauseOnBlock = true
	q.canCap = {
		[RED] = true,
		[BLU] = true,
	}
	T.eq(set:CannotCapReason("cap_red_2", BLU, q), Capture.REASON_LINEAR)
	T.eq(Capture.REASON_TOKEN[Capture.REASON_LINEAR], "#Team_Capture_Linear")
end)

-- cp_dustbowl stage 1: every point is RED's; each stage's first point needs
-- itself for BLU, the second needs the first.
local function Dustbowl()
	local function Stage(first, second, firstIndex)
		local previous = { [BLU] = { first } }
		return Point(first, firstIndex, RED, { previous = previous }), Point(second, firstIndex + 1, RED, { previous = previous })
	end
	local a1, b1 = Stage("cap_red_1", "cap_red_2", 1)
	local a2, b2 = Stage("cap_red_3", "cap_red_4", 3)
	local a3, b3 = Stage("cap_red_5", "cap_red_6", 5)
	return Set({ a1, b1, a2, b2, a3, b3 })
end

local ROUND_1 = {
	cap_red_1 = true,
	cap_red_2 = true,
}

local function MiniRound(base)
	return {
		playingMiniRounds = true,
		inRound = ROUND_1,
		base = base,
	}
end

T.test("cp_dustbowl stage 1: BLU caps A, then B; other stages' points are out of the round", function()
	local set = Dustbowl()
	T.eq(set:TeamMayCapture("cap_red_1", BLU, MiniRound(Capture.NO_POINT)), true, "A needs itself")
	T.eq(set:TeamMayCapture("cap_red_2", BLU, MiniRound(Capture.NO_POINT)), false, "B before A")
	set:SetOwner("cap_red_1", BLU, Capture.CAUSE_CAPTURE, POINTS_MAY_BE_CAPTURED)
	T.eq(set:TeamMayCapture("cap_red_2", BLU, MiniRound(Capture.NO_POINT)), true, "B after A")
	T.eq(set:TeamMayCapture("cap_red_3", BLU, MiniRound(Capture.NO_POINT)), false, "stage 2's first point")
	T.eq(set:TeamMayCapture("cap_red_2", RED, MiniRound(Capture.NO_POINT)), false, "RED owns B")
	T.eq(set:TeamMayCapture("cap_red_1", RED, MiniRound(Capture.NO_POINT)), true, "RED may take A back")
end)

-- cp_steel: per-team previous points gate A -> B -> C -> D; E needs itself.
local function Steel()
	local function P(name, index, blu, red)
		local previous = {
			[BLU] = { blu },
			[RED] = { red },
		}
		return Point(name, index, RED, { previous = previous })
	end
	return Set({
		P("cap_d_flag", 4, "cap_c_flag", "cap_d_flag"),
		P("cap_b_flag", 2, "cap_a_flag", "cap_b_flag"),
		P("final_cap_flag", 5, "final_cap_flag", "final_cap_flag"),
		P("cap_c_flag", 3, "cap_b_flag", "cap_c_flag"),
		P("cap_a_flag", 1, "cap_a_flag", "cap_a_flag"),
	})
end

T.test("cp_steel: BLU takes A, B, C and D in order, and E at any time", function()
	local set = Steel()
	local q = Linear(set, BLU)
	T.eq(set:TeamMayCapture("final_cap_flag", BLU, q), true, "E needs itself")
	T.eq(set:TeamMayCapture("cap_b_flag", BLU, q), false, "B before A")
	for _, pair in ipairs({ { "cap_a_flag", "cap_b_flag" }, { "cap_b_flag", "cap_c_flag" }, { "cap_c_flag", "cap_d_flag" } }) do
		T.eq(set:TeamMayCapture(pair[2], BLU, q), false, pair[2] .. " before " .. pair[1])
		set:SetOwner(pair[1], BLU, Capture.CAUSE_CAPTURE, POINTS_MAY_BE_CAPTURED)
		T.eq(set:TeamMayCapture(pair[2], BLU, q), true, pair[2] .. " after " .. pair[1])
	end
end)

T.test("cp_steel: a relay's SetOwner is not a sounding capture, a player's is", function()
	local set = Steel()
	local events = set:SetOwner("cap_a_flag", BLU, Capture.CAUSE_INPUT, POINTS_MAY_BE_CAPTURED)
	T.eq(#events, 1)
	T.eq(events[1].kind, "owner")
	T.eq(events[1].old, RED)
	T.eq(events[1].team, BLU)
	T.eq(events[1].sounding, false, "a relay")
	T.eq(events[1].scoring, true, "an input still scores")
	events = set:SetOwner("cap_b_flag", BLU, Capture.CAUSE_PLAYER_INPUT, POINTS_MAY_BE_CAPTURED)
	T.eq(events[1].sounding, true, "a player")
	T.eq(#set:SetOwner("cap_b_flag", BLU, Capture.CAUSE_INPUT, POINTS_MAY_BE_CAPTURED), 0, "the owner already")
	T.eq(#set:SetOwner("cap_c_flag", BLU, Capture.CAUSE_INPUT, false), 0, "not while points may not be captured")
	T.eq(set:Owner("cap_c_flag"), RED)
end)

T.test("a capture sounds and scores; a forced owner does neither and ignores the round", function()
	local set = Steel()
	local capture = set:SetOwner("cap_a_flag", BLU, Capture.CAUSE_CAPTURE, POINTS_MAY_BE_CAPTURED)
	T.eq(capture[1].sounding, true)
	T.eq(capture[1].scoring, true)
	T.eq(#set:SetOwner("cap_b_flag", BLU, Capture.CAUSE_CAPTURE, false), 0, "a capture after the round's end")
	local forced = set:SetOwner("cap_b_flag", BLU, Capture.CAUSE_FORCE, false)
	T.eq(forced[1].sounding, false)
	T.eq(forced[1].scoring, false)
	T.eq(set:Owner("cap_b_flag"), BLU)
	local reset = set:SetOwner("cap_b_flag", NOBODY, Capture.CAUSE_CAPTURE, POINTS_MAY_BE_CAPTURED)
	T.eq(reset[1].scoring, false, "a reset to nobody scores for nobody")
end)

-- KOTH: the point locked at round start and unlocked after a delay
-- (CKothLogic::InputRoundActivate, CTeamControlPoint::UnlockThink).
local function Hill(startLocked)
	return Set({ Point("cp_koth", 0, NOBODY, { point_start_locked = startLocked }) })
end

local ROUND_RUNNING, NOT_RUNNING = true, false

T.test("KOTH: a locked point with an unlock time opens only while the round runs", function()
	local set = Hill(false)
	T.eq(#set:SetLocked("cp_koth", true), 0, "locking tells nobody")
	T.eq(set:Locked("cp_koth"), true)
	local events = set:SetUnlockTime("cp_koth", 30, 10)
	T.eq(Kinds(events), "unlock_time:cp_koth")
	T.eq(events[1].at, 40)
	T.eq(set:UnlockAt("cp_koth"), 40, "the HUD's countdown")
	T.eq(#set:Tick(50, NOT_RUNNING), 0, "pre-round never unlocks")
	T.eq(#set:Tick(39.9, ROUND_RUNNING), 0, "before the time")
	T.eq(Kinds(set:Tick(40.1, ROUND_RUNNING)), "unlocked:cp_koth")
	T.eq(set:Locked("cp_koth"), false)
	T.eq(set:UnlockAt("cp_koth"), nil)
	T.eq(#set:Tick(41, ROUND_RUNNING), 0, "unlocked once")
end)

T.test("KOTH: unlocking by hand clears the unlock time", function()
	local set = Hill(true)
	set:SetUnlockTime("cp_koth", 30, 0)
	T.eq(Kinds(set:SetLocked("cp_koth", false)), "unlocked:cp_koth")
	T.eq(set:UnlockAt("cp_koth"), nil)
	T.eq(#set:Tick(31, ROUND_RUNNING), 0, "no second unlock")
	T.eq(Kinds(set:SetUnlockTime("cp_koth", 0, 5)), "unlocked:cp_koth", "an unlock time of 0 unlocks now")
end)

T.test("a locked point may not be capped unless it needs itself", function()
	local set = Hill(true)
	local q = Linear(set, RED)
	T.eq(set:TeamMayCapture("cp_koth", RED, q), false)
	set:SetLocked("cp_koth", false)
	T.eq(set:TeamMayCapture("cp_koth", RED, q), true)
end)

T.test("round activation: owners announced, never-locked points unlocked, locked ones stay", function()
	local set = Set({
		Point("a", 0, BLU),
		Point("b", 1, NOBODY, { point_start_locked = true }),
		Point("c", 2, RED),
	})
	local events = set:RoundActivate()
	T.eq(Kinds(events), "round_start_owned:a,unlocked:a,round_start_owned:c,unlocked:c")
	T.eq(events[1].team, BLU)
	T.eq(events[3].team, RED)
	T.eq(set:Locked("b"), true)
	T.eq(Kinds(set:RoundActivate({ "c" })), "round_start_owned:c,unlocked:c", "a map's RoundActivate to one point")
end)

T.test("a rebuilt set carries the owners and locks its points had", function()
	local spec = Point("a", 0, RED)
	spec.owner = BLU
	spec.locked = true
	spec.unlockAt = 12
	local set = Set({ spec })
	T.eq(set:Owner("a"), BLU)
	T.eq(set:DefaultOwner("a"), RED)
	T.eq(set:Locked("a"), true)
	T.eq(Kinds(set:Tick(13, ROUND_RUNNING)), "unlocked:a")
end)

-- Groups (TeamOwnsAllPoints) ------------------------------------------------

local function Grouped(owners)
	local points = {}
	for i, o in ipairs(owners) do
		points[i] = Point("p" .. i, i, o[1], { point_group = o[2] })
	end
	return Set(points)
end

T.test("one team owning every point of a group wins it", function()
	local set = Grouped({ { BLU, 0 }, { BLU, 0 } })
	T.eq(set:TeamOwnsAll(set:Ids()), BLU)
end)

T.test("mixed owners in the only group is nobody", function()
	local set = Grouped({ { BLU, 0 }, { RED, 0 } })
	T.eq(set:TeamOwnsAll(set:Ids()), NOBODY)
end)

T.test("neutral points are nobody", function()
	local set = Grouped({ { NOBODY, 0 }, { NOBODY, 0 } })
	T.eq(set:TeamOwnsAll(set:Ids()), NOBODY)
end)

-- plr_pipeline: blue_cap_A is alone in group 1, red_cap_A in group 0.
T.test("a group owned outright wins even when another group is contested", function()
	local set = Grouped({ { NOBODY, 0 }, { BLU, 1 } })
	T.eq(set:TeamOwnsAll(set:Ids()), BLU)
end)

T.test("groups are reported in group order", function()
	local set = Grouped({ { BLU, 1 }, { RED, 0 } })
	T.eq(set:TeamOwnsAll(set:Ids()), RED)
end)

T.test("an empty point list is nobody", function()
	T.eq(Grouped({}):TeamOwnsAll({}), NOBODY)
end)

T.test("an override owner decides whether a capture would win", function()
	local set = Grouped({ { BLU, 0 }, { RED, 0 } })
	T.eq(set:TeamOwnsAll(set:Ids(), "p2", BLU), BLU)
	T.eq(set:TeamOwnsAll({ "p2" }), RED, "a subset")
end)

-- The capture panel (CControlPointProgressBar::UpdateBarText) ----------------

-- Overrides as key, value pairs: With("capping", RED, "blocked", true).
local function With(...)
	local over, args = {}, { ... }
	for i = 1, #args, 2 do over[args[i]] = args[i + 1] end
	return over
end

-- A value for each team (an area's team_cancap, its players).
local function ByTeam(red, blu)
	return {
		[RED] = red,
		[BLU] = blu,
	}
end

local function PanelQuery(over)
	local q = {
		pointsMayBeCaptured = true,
		blocked = false,
		capping = NOBODY,
		cappers = 1,
		required = 0,
		pauseOnBlock = true,
		canCap = {
			[RED] = true,
			[BLU] = true,
		},
		playingMiniRounds = false,
		inRound = nil,
		base = 0,
	}
	for k, v in pairs(over or {}) do q[k] = v end
	return q
end

-- b is neutral between BLU's a and RED's c.
local function Line()
	return Set({
		Point("a", 0, BLU),
		Point("b", 1, NOBODY),
		Point("c", 2, RED),
	})
end

T.test("the capture panel's reasons, in TF2's order", function()
	local set = Line()
	local R = function(id, team, over) return set:CannotCapReason(id, team, PanelQuery(over)) end
	T.eq(R("b", BLU, With("capping", BLU)), Capture.REASON_NONE, "capping: the bar, no text")
	T.eq(R("b", BLU, With("pointsMayBeCaptured", false)), Capture.REASON_NOT_NOW, "setup")
	set:SetLocked("b", true)
	T.eq(R("b", BLU), Capture.REASON_NOT_NOW, "locked")
	set:SetLocked("b", false)
	T.eq(R("b", BLU, With("capping", RED, "blocked", true)), Capture.REASON_BLOCKING, "BLU blocking RED")
	T.eq(R("b", BLU, With("capping", RED)), Capture.REASON_REVERTING, "RED taking the neutral point")
	T.eq(R("b", BLU, With("capping", RED, "pauseOnBlock", false)), Capture.REASON_WAITING, "a block breaks: no blocking line")
	T.eq(R("a", BLU), Capture.REASON_OWN_POINT, "BLU's own point")
	T.eq(R("a", BLU, With("canCap", ByTeam(false, true))), Capture.REASON_OWNED, "RED can never take it")
	T.eq(R("c", BLU), Capture.REASON_LINEAR, "RED's point past the neutral one")
	T.eq(R("b", BLU, With("capping", BLU, "blocked", true)), Capture.REASON_BLOCKED, "BLU's capture blocked")
	T.eq(R("b", BLU, With("capping", BLU, "blocked", true, "cappers", 1, "required", 2)), Capture.REASON_WAITING, "blocked, and short of cappers")
	T.eq(R("b", BLU, With("canCap", ByTeam(true, false))), Capture.REASON_CANNOT, "the area refuses BLU")
	T.eq(R("b", BLU, With("cappers", 1, "required", 2)), Capture.REASON_WAITING, "one of two")
end)

T.test("every reason has its localization token", function()
	local tokens = {
		[Capture.REASON_NOT_NOW] = "#Team_Capture_NotNow",
		[Capture.REASON_BLOCKING] = "#Team_Blocking_Capture",
		[Capture.REASON_REVERTING] = "#Team_Reverting_Capture",
		[Capture.REASON_OWNED] = "#Team_Capture_Owned",
		[Capture.REASON_OWN_POINT] = "#Team_Capture_OwnPoint",
		[Capture.REASON_LINEAR] = "#Team_Capture_Linear",
		[Capture.REASON_BLOCKED] = "#Team_Capture_Blocked",
		[Capture.REASON_CANNOT] = "#Team_Cannot_Capture",
		[Capture.REASON_WAITING] = "#Team_Waiting_for_teammate",
	}
	for reason, token in pairs(tokens) do T.eq(Capture.REASON_TOKEN[reason], token, "reason " .. reason) end
	T.eq(Capture.REASON_TOKEN[Capture.REASON_NONE], nil, "no text while capping")
end)

-- The HUD's point state ------------------------------------------------------

local function Area(over)
	local a = {
		capping = NOBODY,
		teamInZone = NOBODY,
		touching = {
			[RED] = 0,
			[BLU] = 0,
		},
		blocked = false,
		progress = 0,
		numRequired = {
			[RED] = 1,
			[BLU] = 2,
		},
		canCap = {
			[RED] = true,
			[BLU] = true,
		},
		scales = false,
	}
	for k, v in pairs(over or {}) do a[k] = v end
	return a
end

local function HudQuery(area)
	return {
		area = area,
		playingMiniRounds = false,
		inRound = nil,
		bases = {
			[RED] = 2,
			[BLU] = 0,
		},
		hidden = false,
		timerEnd = 0,
	}
end

T.test("the HUD shows the capping team's cappers against its required count", function()
	local set = Line()
	local hud = set:HudPoint("b", HudQuery(Area(With("capping", BLU, "teamInZone", BLU, "touching", ByTeam(0, 1), "progress", 0.25))))
	T.eq(hud.owner, NOBODY)
	T.eq(hud.capping, BLU)
	T.near(hud.progress, 0.25)
	T.eq(hud.cappers, 1)
	T.eq(hud.required, 2, "BLU's team_numcap")
	T.eq(hud.blocked, false)
	T.eq(hud.redCanCap, true)
	T.eq(hud.blueCanCap, true)
	T.eq(hud.inRound, true)
	T.eq(hud.locked, false)
	T.eq(hud.unlockTime, 0)
end)

T.test("idle, the HUD counts the team in the zone; under mp_capstyle 1 none is required", function()
	local set = Line()
	local idle = set:HudPoint("b", HudQuery(Area(With("teamInZone", RED, "touching", ByTeam(3, 0)))))
	T.eq(idle.cappers, 3)
	T.eq(idle.required, 1, "RED's team_numcap")
	local scaled = set:HudPoint("b", HudQuery(Area(With("teamInZone", RED, "touching", ByTeam(3, 0), "scales", true))))
	T.eq(scaled.required, 0)
	local empty = set:HudPoint("b", HudQuery(Area()))
	T.eq(empty.cappers, 0)
	T.eq(empty.required, 0)
end)

-- team_control_point's team_icon_0/2/3: the HUD draws the owner's.
T.test("the HUD shows the owner's icon: the map's team_icon, else TF2's", function()
	local set = Set({
		Point("a", 0, BLU, { icons = { [BLU] = "sprites/obj_icons/icon_obj_1_blu" } }),
		Point("b", 1, NOBODY),
		Point("c", 2, RED),
	})
	T.eq(set:HudPoint("a", HudQuery(nil)).icon, "sprites/obj_icons/icon_obj_1_blu", "the map's")
	T.eq(set:HudPoint("b", HudQuery(nil)).icon, Capture.ICON_DEFAULT[NOBODY], "TF2's neutral")
	T.eq(set:HudPoint("c", HudQuery(nil)).icon, Capture.ICON_DEFAULT[RED], "TF2's RED")
	T.eq(Capture.ICON_DEFAULT[BLU], "sprites/obj_icons/icon_obj_blu", "the FGD's default")
end)

T.test("the HUD's can-cap marks need the area's permission and the capture order", function()
	local set = Line()
	local hud = set:HudPoint("c", HudQuery(Area(With("canCap", ByTeam(true, true)))))
	T.eq(hud.blueCanCap, false, "past the neutral point")
	T.eq(hud.redCanCap, false, "RED's own point")
	hud = set:HudPoint("b", HudQuery(Area(With("canCap", ByTeam(false, true)))))
	T.eq(hud.redCanCap, false, "the area refuses RED")
	T.eq(hud.blueCanCap, true)
	local noArea = set:HudPoint("b", HudQuery(nil))
	T.eq(noArea.redCanCap, false, "no area, nobody caps")
	T.eq(noArea.capping, NOBODY)
end)

T.test("the HUD dims points out of the mini-round and shows a pending unlock", function()
	local set = Line()
	set:SetLocked("b", true)
	set:SetUnlockTime("b", 30, 5)
	local q = HudQuery(Area())
	q.playingMiniRounds = true
	q.inRound = { a = true }
	local hud = set:HudPoint("b", q)
	T.eq(hud.inRound, false)
	T.eq(hud.locked, true)
	T.eq(hud.unlockTime, 35)
	T.eq(hud.name, "")
end)

-- Layout (the master's caplayout) ---------------------------------------------

local function Rows(rows)
	local out = {}
	for i, row in ipairs(rows) do out[i] = table.concat(row, " ") end
	return table.concat(out, ",")
end

T.test("caplayout rows: cp_steel's and cp_gravelpit's", function()
	T.eq(Rows(Capture.Layout("4, 0 1 2 3", 5)), "4,0 1 2 3")
	T.eq(Rows(Capture.Layout("2, 0 1", 3)), "2,0 1")
end)

T.test("no caplayout is one row in rank order; unknown points are skipped", function()
	T.eq(Rows(Capture.Layout("", 3)), "0 1 2")
	T.eq(Rows(Capture.Layout("9 0, 1", 2)), "0,1")
end)

-- Capture order, as CTFGameRules::TeamMayCapturePoint computes it ------------

T.test("point ranks are 0-based in index order", function()
	local ranks = Capture.Ranks({ 4, 1, 3, 2 })
	T.eq(ranks[1], 3)
	T.eq(ranks[2], 0)
	T.eq(ranks[3], 2)
	T.eq(ranks[4], 1)
end)

T.test("the base point is the team's end of the chain", function()
	local points = {
		{
			index = 0,
			defaultOwner = BLU,
		},
		{
			index = 1,
			defaultOwner = NOBODY,
		},
		{
			index = 2,
			defaultOwner = RED,
		},
	}
	T.eq(Capture.BaseControlPoint(BLU, points), 0)
	T.eq(Capture.BaseControlPoint(RED, points), 2)
	T.eq(Capture.BaseControlPoint(NOBODY, { points[3] }), Capture.NO_POINT)
	local redBoth = {
		points[3],
		{
			index = 3,
			defaultOwner = RED,
		},
	}
	T.eq(Capture.BaseControlPoint(RED, redBoth), 3, "both ends: the highest")
end)

T.test("the farthest owned point walks from the base", function()
	local owners = {
		[0] = BLU,
		[1] = BLU,
		[2] = NOBODY,
		[3] = RED,
	}
	T.eq(Capture.FarthestOwnedControlPoint(BLU, owners, 4, 0), 1)
	T.eq(Capture.FarthestOwnedControlPoint(RED, owners, 4, 3), 3)
	T.eq(Capture.FarthestOwnedControlPoint(RED, owners, 4, Capture.NO_POINT), Capture.NO_POINT)
end)

local function Q(over)
	local q = {
		caplinear = true,
		index = 1,
		team = BLU,
		locked = false,
		previous = { Capture.NO_POINT, Capture.NO_POINT, Capture.NO_POINT },
		playingMiniRounds = false,
		owners = {
			[0] = BLU,
			[1] = NOBODY,
			[2] = RED,
		},
		count = 3,
		base = 0,
	}
	for k, v in pairs(over or {}) do q[k] = v end
	return q
end

T.test("a point next to the team's farthest point may be capped", function()
	T.eq(Capture.TeamMayCapturePoint(Q()), true)
	T.eq(Capture.TeamMayCapturePoint(Q({ index = 2 })), false)
end)

T.test("a locked point may not be capped", function()
	T.eq(Capture.TeamMayCapturePoint(Q({ locked = true })), false)
end)

T.test("a point that requires itself is always cappable, locked or not", function()
	T.eq(Capture.TeamMayCapturePoint(Q(With("locked", true, "previous", { 1, Capture.NO_POINT, Capture.NO_POINT }))), true)
end)

T.test("named previous points must all be owned", function()
	T.eq(Capture.TeamMayCapturePoint(Q(With("index", 2, "previous", { 0, Capture.NO_POINT, Capture.NO_POINT }))), true)
	T.eq(Capture.TeamMayCapturePoint(Q(With("index", 2, "previous", { 0, 1, Capture.NO_POINT }))), false)
end)

T.test("with mini-rounds and no previous points any point is cappable", function()
	T.eq(Capture.TeamMayCapturePoint(Q(With("index", 2, "playingMiniRounds", true))), true)
end)

T.test("tf_caplinear 0 allows everything", function()
	T.eq(Capture.TeamMayCapturePoint(Q(With("caplinear", false, "locked", true))), true)
end)

-- Who hears what ------------------------------------------------------------

local function Heard(lines)
	local out = {}
	for _, l in ipairs(lines) do out[#out + 1] = l.hearer .. ":" .. l.team .. ":" .. l.sound end
	return table.concat(out, ",")
end

T.test("a point's capture sounds default to the holograms; a map's keyvalues replace them", function()
	local set = Set({
		Point("plain", 0, NOBODY),
		Point("custom", 1, NOBODY, With("sounds", With("start", "Map.Start", "interrupted", "Map.Held"))),
	})
	local plain = set:Sounds("plain")
	T.eq(plain.start .. " " .. plain.stop .. " " .. plain.progress .. " " .. plain.interrupted,
		Capture.SOUND_START .. " " .. Capture.SOUND_END .. " " .. Capture.SOUND_PROGRESS .. " " .. Capture.SOUND_INTERRUPTED)
	local custom = set:Sounds("custom")
	T.eq(custom.start, "Map.Start")
	T.eq(custom.interrupted, "Map.Held")
	T.eq(custom.stop, Capture.SOUND_END, "unset keys keep the default")
end)

T.test("a capture by players plays the new owner's team_capsound to everyone; a relay's does not", function()
	local set = Set({ Point("a", 0, RED, { capSounds = { [BLU] = "Map.BluCapped" } }) })
	local capture = set:SetOwner("a", BLU, Capture.CAUSE_CAPTURE, POINTS_MAY_BE_CAPTURED)
	T.eq(Heard(capture[1].lines), Capture.HEAR_EVERYONE .. ":" .. BLU .. ":Map.BluCapped")
	local relay = set:SetOwner("a", RED, Capture.CAUSE_INPUT, POINTS_MAY_BE_CAPTURED)
	T.eq(Heard(relay[1].lines), "", "no sound for a relay")
	local noSound = set:SetOwner("a", BLU, Capture.CAUSE_PLAYER_INPUT, POINTS_MAY_BE_CAPTURED)
	T.eq(Heard(noSound[1].lines), Capture.HEAR_EVERYONE .. ":" .. BLU .. ":Map.BluCapped", "a player's input sounds")
	set:SetOwner("a", RED, Capture.CAUSE_FORCE)
	local redCap = set:SetOwner("a", RED, Capture.CAUSE_CAPTURE, POINTS_MAY_BE_CAPTURED)
	T.eq(Heard(redCap[1].lines), "", "no team_capsound_2 set")
end)

T.test("a capture starting warns the other players that the point is contested", function()
	local set = Set({
		Point("owned", 0, RED),
		Point("neutral", 1, NOBODY),
		Point("quiet", 2, RED, { point_warn_on_cap = Capture.CP_WARN.NO_ANNOUNCEMENTS }),
	})
	T.eq(Heard(set:CaptureStarted("owned", BLU, 0)), Capture.HEAR_OTHERS .. ":" .. BLU .. ":" .. Capture.CONTESTED)
	T.eq(Heard(set:CaptureStarted("neutral", RED, 0)), Capture.HEAR_OTHERS .. ":" .. RED .. ":" .. Capture.CONTESTED_NEUTRAL)
	T.eq(Heard(set:CaptureStarted("quiet", BLU, 0)), "", "point_warn_on_cap 2")
	T.eq(Heard(set:CaptureStarted("owned", NOBODY, 0)), "", "nobody capping")
end)

T.test("a final point's warning sounds at most every five seconds", function()
	local set = Set({ Point("last", 0, RED, { point_warn_on_cap = Capture.CP_WARN.FINALCAP }) })
	local warn = Capture.HEAR_OTHERS .. ":" .. BLU .. ":ControlPoint.CaptureWarn"
	T.eq(Heard(set:CaptureStarted("last", BLU, 10)), warn)
	T.eq(Heard(set:CaptureStarted("last", BLU, 14)), "", "four seconds later")
	T.eq(Heard(set:CaptureStarted("last", BLU, 15.5)), warn, "after five")
end)

-- The capture bell (TF2's scored chime, Hud.EndRoundScored): every point a
-- team takes rings it for everyone, spectators too, whether players took
-- it or a relay (a payload cart) did, the winning point included.
T.test("every capture rings the bell for everyone; a forced owner or a reset does not", function()
	local set = Steel()
	T.eq(set:SetOwner("cap_a_flag", BLU, Capture.CAUSE_CAPTURE, POINTS_MAY_BE_CAPTURED)[1].bell, Capture.CAPTURE_BELL, "players' capture")
	T.eq(set:SetOwner("cap_b_flag", BLU, Capture.CAUSE_INPUT, POINTS_MAY_BE_CAPTURED)[1].bell, Capture.CAPTURE_BELL, "a relay's (a cart's)")
	T.eq(set:SetOwner("cap_c_flag", BLU, Capture.CAUSE_FORCE, false)[1].bell, nil, "forced")
	T.eq(set:SetOwner("cap_c_flag", NOBODY, Capture.CAUSE_CAPTURE, POINTS_MAY_BE_CAPTURED)[1].bell, nil, "reset to nobody")
	T.eq(Capture.CAPTURE_BELL, "Hud.EndRoundScored", "TF2's chime")
end)

T.test("only RED and BLU capture", function()
	local set = Line()
	T.eq(set:TeamMayCapture("b", NOBODY, Linear(set, NOBODY)), false)
	T.eq(set:TeamMayCapture("b", Teams.SPECTATOR, Linear(set, BLU)), false)
end)

-- A point id the set never held (an entity recreated by a map cleanup the
-- set missed) is our bug: the error names the point, not "index a nil".
T.test("a point the set does not hold fails naming it", function()
	local set = Granary(true)
	local ok, err = pcall(set.Owner, set, "stale")
	T.eq(ok, false)
	T.eq(tostring(err):find("no control point stale in the set", 1, true) ~= nil, true, tostring(err))
end)

-- The kill feed names who took a point (TF2's cappers): a capture's owner
-- event carries their names, any other change of owner none.
T.test("a capture's owner event names its cappers; any other change of owner none", function()
	local set = Granary()
	local capture = set:SetOwner("cap_middle", RED, Capture.CAUSE_CAPTURE, POINTS_MAY_BE_CAPTURED, { "Alice", "#npc_combine_s" })
	T.eq(table.concat(capture[1].cappers, ","), "Alice,#npc_combine_s", "the cappers")
	local unnamed = set:SetOwner("cap_middle", BLU, Capture.CAUSE_CAPTURE, POINTS_MAY_BE_CAPTURED)
	T.eq(#unnamed[1].cappers, 0, "a capture no one is named for")
	local forced = set:SetOwner("cap_middle", RED, Capture.CAUSE_FORCE)
	T.eq(#forced[1].cappers, 0, "forced")
end)

T.finish()
