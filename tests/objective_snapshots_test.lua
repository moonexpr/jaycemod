-- Snapshot and Restore on the objectives' models: the capture PointSet,
-- a capture area's state, the master, a tf_logic_cp_timer, a flag and the
-- CTF tally. A model taken at one time and restored into a fresh one at
-- another holds the same state, its times kept as time to go, and plays on
-- as the original does.
local T = dofile("tests/harness.lua")
local Capture = T.require("foundation.capture")
local Area = T.require("foundation.capture.area")
local Master = T.require("foundation.capture.master")
local PointTimer = T.require("foundation.capture.point_timer")
local Flag = T.require("features.flag.model")
local Teams = T.require("foundation.teams")

local NOBODY, RED, BLU = Teams.UNASSIGNED, Teams.RED, Teams.BLUE
local NO_FLAGS = 0
local T0, LATER = 100, 7000

-- Entities stand in as tables with a metatable, resolved by name.
local function Entities(names)
	local byName = {}
	for _, name in ipairs(names) do byName[name] = setmetatable({ name = name }, {}) end
	local refs = {
		Encode = function(_, ent) return ent.name end,
		Decode = function(_, name) return byName[name] end,
	}
	return byName, refs
end

local function Equal(a, b, path)
	if type(a) == "table" and type(b) == "table" then
		for k, v in pairs(a) do Equal(v, b[k], path .. "." .. tostring(k)) end
		for k in pairs(b) do
			if a[k] == nil then error(path .. "." .. tostring(k) .. " only in the second", 2) end
		end
		return
	end
	if a ~= b then error(string.format("%s: %s vs %s", path, tostring(a), tostring(b)), 2) end
end

local function Point(id, index, owner)
	return {
		id = id,
		index = index,
		defaultOwner = owner,
		startLocked = false,
		group = 0,
		warnOnCap = Capture.CP_WARN.NORMAL,
		warnSound = "",
		printName = "",
		spawnflags = NO_FLAGS,
		previous = {},
		sounds = {},
		capSounds = {},
		icons = {},
	}
end

local function Set(ents)
	return Capture.New({
		caplinear = true,
		points = {
			Point(ents.cp_1, 1, BLU),
			Point(ents.cp_2, 2, NOBODY),
			Point(ents.cp_3, 3, RED),
		},
	})
end

T.test("a point set keeps owners, locks and unlock times, keyed by its entities", function()
	local ents, refs = Entities({ "cp_1", "cp_2", "cp_3" })
	local set = Set(ents)
	set:SetOwner(ents.cp_2, RED, nil, true, {})
	set:SetLocked(ents.cp_3, true)
	set:SetUnlockTime(ents.cp_3, 30, T0)
	local copy = Set(ents)
	copy:Restore(set:Snapshot(T0 + 10, refs), LATER + 10, refs)
	T.eq(copy:Owner(ents.cp_2), RED, "owner")
	T.eq(copy:Locked(ents.cp_3), true, "locked")
	T.near(copy:UnlockAt(ents.cp_3) - LATER, set:UnlockAt(ents.cp_3) - T0, 1e-9, "unlock time to go")
	Equal(copy:Snapshot(LATER + 10, refs), set:Snapshot(T0 + 10, refs), "set")
end)

T.test("a capture area's progress is kept, and who stands in it is not", function()
	local ents, refs = Entities({ "player" })
	local s = Area.New(BLU)
	s.capturing, s.cappingTeam, s.timeRemaining, s.lastReduction = true, RED, 4.5, T0 + 2
	s.touching[RED] = 1
	s.blockers[ents.player] = true
	local copy = Area.New(BLU)
	copy.touching[BLU] = 2
	Area.Restore(copy, Area.Snapshot(s, T0 + 3, refs), LATER + 3, refs)
	T.eq(copy.capturing, true, "capturing")
	T.eq(copy.cappingTeam, RED, "by red")
	T.eq(copy.timeRemaining, 4.5, "time remaining")
	T.near(copy.lastReduction, LATER + 2, 1e-9, "last reduction as time ago")
	T.eq(copy.touching[BLU], 2, "who stands in it follows the players, not the snapshot")
	T.eq(next(copy.blockers), nil, "blockers too")
end)

local function MasterConfig(rounds)
	return {
		restrict = {},
		switchTeams = false,
		scoreStyle = 0,
		playAllRounds = false,
		partialCapRate = 0,
		capLayout = "",
		disabled = false,
		rounds = rounds,
	}
end

T.test("a master keeps its chosen mini-round and its switches, not its round list", function()
	local master = Master.New(MasterConfig({}))
	master.current, master.disabled, master.capLayout = "round_2", true, "0,1"
	local copy = Master.New(MasterConfig({}))
	local rounds = copy.rounds
	copy:Restore(master:Snapshot(T0), LATER)
	T.eq(copy:Current(), "round_2", "current")
	T.eq(copy.disabled, true, "disabled")
	T.eq(copy.capLayout, "0,1", "layout")
	T.eq(copy.rounds, rounds, "the map's round list is the copy's own")
end)

T.test("a point timer keeps its end as time to go", function()
	local timer = PointTimer.New({
		length = 60,
		team = BLU,
	})
	timer.endTime = T0 + 45
	local copy = PointTimer.New({
		length = 60,
		team = BLU,
	})
	copy:Restore(timer:Snapshot(T0 + 5), LATER + 5)
	T.near(copy:EndTime(), LATER + 45, 1e-9, "end")
	local idle = PointTimer.New({ length = 60 })
	local idleCopy = PointTimer.New({ length = 60 })
	idleCopy.endTime = 5
	idleCopy:Restore(idle:Snapshot(T0), LATER)
	T.eq(idleCopy:EndTime(), nil, "an idle timer stays idle")
end)

T.test("a dropped flag returns when the original would", function()
	local ents, refs = Entities({ "carrier" })
	local flag = Flag.New({ team = RED })
	flag:PickUp(ents.carrier, BLU, {
		ownersCarry = false,
		mayBeCapped = true,
	})
	flag:Drop(T0, false)
	local copy = Flag.New({ team = RED })
	copy:Restore(flag:Snapshot(T0 + 1, refs), LATER + 1, refs)
	T.eq(copy:State(), Flag.DROPPED, "dropped")
	for t = 2, flag:ReturnTime() + 2 do
		local a, b = flag:Think(T0 + t), copy:Think(LATER + t)
		T.eq(#b, #a, "events at +" .. t)
		T.eq(copy:State(), flag:State(), "state at +" .. t)
	end
	T.eq(copy:State(), Flag.HOME, "returned")
end)

T.test("a carried flag keeps its carrier", function()
	local ents, refs = Entities({ "carrier" })
	local flag = Flag.New({ team = RED })
	flag:PickUp(ents.carrier, BLU, {
		ownersCarry = false,
		mayBeCapped = true,
	})
	local copy = Flag.New({ team = RED })
	copy:Restore(flag:Snapshot(T0, refs), LATER, refs)
	T.eq(copy:Carrier(), ents.carrier, "carrier")
	T.eq(copy:CarrierTeam(), BLU, "carrier's team")
end)

T.test("the tally keeps its captures", function()
	local tally = Flag.NewTally()
	tally:Capture(RED, 3)
	tally:Capture(RED, 3)
	local copy = Flag.NewTally()
	copy:Restore(tally:Snapshot())
	T.eq(copy:Captures(RED), 2, "red's")
	T.eq(copy:Captures(BLU), 0, "blue's")
end)

T.finish()
