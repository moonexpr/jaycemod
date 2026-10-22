-- foundation.capture.area: CTriggerAreaCapture::CaptureThink as a state
-- machine (trigger_area_capture.cpp), and the point's capture sounds.
local T = dofile("tests/harness.lua")
local C = T.require("foundation.capture.area")
local Capture = T.require("foundation.capture")

local Teams = T.require("foundation.teams")

local NOBODY, RED, BLU = Teams.UNASSIGNED, Teams.RED, Teams.BLUE
local LABEL = { [NOBODY] = "nobody", [RED] = "red", [BLU] = "blu" }

-- A 10s point both teams may cap, one player each needed, TF2's defaults.
local function Input(now, red, blu, over)
	local i = {
		now = now,
		pointsMayBeCaptured = true,
		counts = { [RED] = red, [BLU] = blu },
		canCap = { [RED] = true, [BLU] = true },
		numRequired = { [RED] = 1, [BLU] = 1 },
		startRequired = { [RED] = 1, [BLU] = 1 },
		capTime = 10,
		scales = true,
		blockstyle = C.BLOCKSTYLE_PAUSE,
		deteriorate = 90,
		overtime = false,
		teamMayCapture = function() return true end,
	}
	for k, v in pairs(over or {}) do i[k] = v end
	return i
end

local function Kinds(events)
	local out = {}
	for _, e in ipairs(events) do
		local s = e.kind
		if e.team then s = s .. ":" .. LABEL[e.team] end
		if e.kind == "numcappers" then s = s .. ":" .. e.n .. (e.blocked and "b" or "") end
		if e.kind == "blocked" then s = s .. ":" .. tostring(e.value) end
		out[#out + 1] = s
	end
	return table.concat(out, ",")
end

T.test("total time scales with required cappers under mp_capstyle 1", function()
	T.eq(C.TotalTime(10, true, 2), 40)
	T.eq(C.TotalTime(10, false, 2), 10)
end)

T.test("nothing happens on an empty point", function()
	local s = C.New(NOBODY)
	T.eq(Kinds(C.Step(s, Input(0, 0, 0))), "")
end)

T.test("a capture starts when a team that may cap stands on the point", function()
	local s = C.New(RED)
	T.eq(Kinds(C.Step(s, Input(0, 0, 1))), "start:blu,numcappers:1,capturestart:blu")
	T.eq(s.capturing, true)
	T.eq(s.cappingTeam, BLU)
	T.eq(s.timeRemaining, 20)
end)

T.test("the owner cannot start capturing its own point", function()
	local s = C.New(BLU)
	T.eq(Kinds(C.Step(s, Input(0, 0, 2))), "")
end)

T.test("a team that may not cap never starts", function()
	local s = C.New(RED)
	local i = Input(0, 0, 1)
	i.canCap[BLU] = false
	T.eq(Kinds(C.Step(s, i)), "")
end)

T.test("team_startcap: too few players do not start a capture", function()
	local s = C.New(RED)
	local i = Input(0, 0, 1)
	i.startRequired[BLU] = 2
	T.eq(Kinds(C.Step(s, i)), "")
	T.eq(Kinds(C.Step(s, Input(0.1, 0, 2, { startRequired = { [RED] = 1, [BLU] = 2 } }))), "start:blu,numcappers:2,capturestart:blu")
end)

T.test("mp_capstyle 0: team_numcap players are needed to start", function()
	local s = C.New(RED)
	local over = { scales = false, numRequired = { [RED] = 1, [BLU] = 2 } }
	T.eq(Kinds(C.Step(s, Input(0, 0, 1, over))), "")
	T.eq(Kinds(C.Step(s, Input(0.1, 0, 2, over))), "start:blu,numcappers:2,capturestart:blu")
end)

T.test("one capper takes the whole scaled time, then the point is captured", function()
	local s = C.New(RED)
	C.Step(s, Input(0, 0, 1))
	for t = 1, 19 do C.Step(s, Input(t, 0, 1)) end
	T.near(s.timeRemaining, 1)
	T.eq(Kinds(C.Step(s, Input(20, 0, 1))), "end:blu,owner:blu,numcappers:0")
	T.eq(s.owner, BLU)
	T.eq(s.capturing, false)
end)

T.test("each extra capper adds a diminishing share of the rate", function()
	local s = C.New(RED)
	C.Step(s, Input(0, 0, 3))
	C.Step(s, Input(1, 0, 3))
	T.near(s.timeRemaining, 20 - (1 + 1 / 2 + 1 / 3))
end)

T.test("a change in the number of cappers is reported", function()
	local s = C.New(RED)
	C.Step(s, Input(0, 0, 1))
	T.eq(Kinds(C.Step(s, Input(0.1, 0, 2))), "numcappers:2")
	T.eq(Kinds(C.Step(s, Input(0.2, 0, 2))), "")
end)

T.test("mp_blockstyle 1: defenders pause the capture and zero the count, -1 for carts", function()
	local s = C.New(RED)
	C.Step(s, Input(0, 0, 1))
	C.Step(s, Input(1, 0, 1))
	local before = s.timeRemaining
	T.eq(Kinds(C.Step(s, Input(2, 1, 1))), "numcappers:0b,blocked:true")
	T.eq(s.timeRemaining, before)
	T.eq(s.blocked, true)
	T.eq(s.capturing, true)
end)

T.test("a block names the team whose capture it stops", function()
	local s = C.New(RED)
	C.Step(s, Input(0, 0, 1, { blockstyle = C.BLOCKSTYLE_BREAK }))
	local events = C.Step(s, Input(1, 1, 1, { blockstyle = C.BLOCKSTYLE_BREAK }))
	T.eq(events[2].kind, "blocked")
	T.eq(events[2].capping, BLU)
end)

T.test("a block is reported again every think while it lasts", function()
	local s = C.New(RED)
	C.Step(s, Input(0, 0, 1))
	C.Step(s, Input(0.1, 1, 1))
	T.eq(Kinds(C.Step(s, Input(0.2, 1, 1))), "numcappers:0b")
end)

T.test("the capture resumes when the defenders leave", function()
	local s = C.New(RED)
	C.Step(s, Input(0, 0, 1))
	C.Step(s, Input(0.1, 1, 1))
	T.eq(Kinds(C.Step(s, Input(0.2, 0, 1))), "numcappers:1,blocked:false")
	T.eq(s.blocked, false)
end)

T.test("mp_blockstyle 0: a block breaks the capture", function()
	local s = C.New(RED)
	C.Step(s, Input(0, 0, 1, { blockstyle = C.BLOCKSTYLE_BREAK }))
	T.eq(Kinds(C.Step(s, Input(1, 1, 1, { blockstyle = C.BLOCKSTYLE_BREAK }))), "numcappers:1,blocked:true,break:blu,numcappers:0")
	T.eq(s.capturing, false)
end)

T.test("an empty owned point deteriorates over mp_capdeteriorate_time", function()
	local s = C.New(RED)
	C.Step(s, Input(0, 0, 1))
	for t = 1, 10 do C.Step(s, Input(t, 0, 1)) end
	T.near(s.timeRemaining, 10)
	C.Step(s, Input(11, 0, 0))
	T.near(s.timeRemaining, 10 + 20 / 90)
end)

T.test("deterioration is six times faster in overtime", function()
	local s = C.New(RED)
	C.Step(s, Input(0, 0, 1))
	for t = 1, 10 do C.Step(s, Input(t, 0, 1)) end
	C.Step(s, Input(11, 0, 0, { overtime = true }))
	T.near(s.timeRemaining, 10 + 6 * 20 / 90)
end)

T.test("mp_capstyle 0 deteriorates at one second per second", function()
	local s = C.New(RED)
	local over = { scales = false }
	C.Step(s, Input(0, 0, 1, over))
	C.Step(s, Input(4, 0, 1, over))
	C.Step(s, Input(5, 0, 0, over))
	T.near(s.timeRemaining, 7)
end)

T.test("a fully deteriorated capture breaks", function()
	local s = C.New(RED)
	C.Step(s, Input(0, 0, 1))
	T.eq(Kinds(C.Step(s, Input(0.5, 0, 0))), "numcappers:0,break:blu,numcappers:0")
end)

T.test("a payload area (99999s) breaks within a think of its pushers leaving", function()
	local s = C.New(RED)
	C.Step(s, Input(0, 0, 1, { capTime = 99999 }))
	C.Step(s, Input(30, 0, 1, { capTime = 99999 }))
	local events = C.Step(s, Input(30.1, 0, 0, { capTime = 99999 }))
	T.eq(Kinds(events), "numcappers:0,break:blu,numcappers:0")
end)

T.test("a capture the team may no longer make resets at once", function()
	local s = C.New(RED)
	C.Step(s, Input(0, 0, 1))
	local i = Input(1, 0, 0, { teamMayCapture = function() return false end })
	T.eq(Kinds(C.Step(s, i)), "numcappers:0,break:blu,numcappers:0")
end)

T.test("on a neutral point the other team reverses the capture", function()
	local s = C.New(NOBODY)
	C.Step(s, Input(0, 0, 1))
	C.Step(s, Input(5, 0, 1))
	T.near(s.timeRemaining, 15)
	C.Step(s, Input(5.1, 0, 0))
	-- RED alone on a point BLU is capping
	local s2 = C.New(NOBODY)
	C.Step(s2, Input(0, 0, 1))
	C.Step(s2, Input(5, 0, 1))
	C.Step(s2, Input(6, 1, 0))
	T.near(s2.timeRemaining, 16)
end)

T.test("when points may not be captured, a running capture breaks", function()
	local s = C.New(RED)
	C.Step(s, Input(0, 0, 1))
	T.eq(Kinds(C.Step(s, Input(1, 0, 1, { pointsMayBeCaptured = false }))), "break:blu,numcappers:0")
	T.eq(Kinds(C.Step(s, Input(2, 0, 1, { pointsMayBeCaptured = false }))), "")
end)

T.test("CaptureCurrentCP ends a running capture and does nothing otherwise", function()
	local s = C.New(RED)
	T.eq(Kinds(C.CaptureCurrent(s)), "")
	C.Step(s, Input(0, 0, 1))
	T.eq(Kinds(C.CaptureCurrent(s)), "end:blu,owner:blu,numcappers:0")
	T.eq(s.owner, BLU)
end)

-- An admin's Set Team (ws/sh_editors_point.lua): the area ends a
-- capture for the team as a finished one would, so the map hears its
-- OnCapTeam output (cp_steel's relays open the next point's doors).
T.test("CaptureFor ends a capture for the team, as a finished one, whatever was running", function()
	local s = C.New(RED)
	T.eq(Kinds(C.CaptureFor(s, BLU)), "end:blu,owner:blu,numcappers:0", "nothing running")
	T.eq(s.owner, BLU)
	T.eq(s.capturing, false)
	local other = C.New(NOBODY)
	C.Step(other, Input(0, 0, 1))
	T.eq(Kinds(C.CaptureFor(other, RED)), "end:red,owner:red,numcappers:0", "BLU was capping: RED takes it")
	T.eq(other.capturing, false)
end)

T.test("SetControlPoint breaks the capture", function()
	local s = C.New(RED)
	C.Step(s, Input(0, 0, 1))
	T.eq(Kinds(C.Break(s)), "break:blu,numcappers:0")
	T.eq(Kinds(C.Break(s)), "")
end)

T.test("capture progress for the HUD runs from 0 to 1", function()
	local s = C.New(RED)
	T.eq(C.Progress(s, Input(0, 0, 0)), 0)
	C.Step(s, Input(0, 0, 1))
	T.near(C.Progress(s, Input(0, 0, 1)), 0)
	C.Step(s, Input(10, 0, 1))
	T.near(C.Progress(s, Input(10, 0, 1)), 0.5)
end)

T.test("respawn adjustments move from the old owner to the new one", function()
	local adjust = C.SpawnAdjustments(RED, BLU, { [RED] = 4, [BLU] = -2 })
	T.eq(#adjust, 2)
	T.eq(adjust[1].team, RED)
	T.eq(adjust[1].seconds, -4)
	T.eq(adjust[2].team, BLU)
	T.eq(adjust[2].seconds, -2)
	T.eq(#C.SpawnAdjustments(NOBODY, BLU, { [RED] = 0, [BLU] = 0 }), 0)
end)

-- Capture sounds (CTeamControlPoint::CaptureInterrupted and CaptureEnd) ------

local NO_FLAGS = 0

-- The point's sounds as TF2 defaults them (CTeamControlPoint::Spawn).
local DEFAULT_SOUNDS = {
	start = Capture.SOUND_START,
	stop = Capture.SOUND_END,
	progress = Capture.SOUND_PROGRESS,
	interrupted = Capture.SOUND_INTERRUPTED,
}

-- An area event: its kind and one field.
local function Event(kind, field, value)
	return {
		kind = kind,
		[field] = value,
	}
end

local function Sounds(e, flags, sounds)
	local s = C.PointSounds(e, flags or NO_FLAGS, sounds or DEFAULT_SOUNDS)
	return tostring(s.stopLoop) .. "|" .. tostring(s.play) .. "|" .. tostring(s.loop)
end

T.test("a map's point_capture_*_sound keyvalues replace the defaults", function()
	local sounds = {
		start = "Map.Start",
		stop = "Map.Stop",
		progress = "Map.Loop",
		interrupted = "Map.Held",
	}
	T.eq(Sounds(Event("start", "team", BLU), NO_FLAGS, sounds), "true|Map.Start|Map.Loop")
	T.eq(Sounds(Event("blocked", "value", true), NO_FLAGS, sounds), "true|nil|Map.Held")
	T.eq(Sounds(Event("end", "team", BLU), NO_FLAGS, sounds), "true|Map.Stop|nil")
end)

T.test("a capture starting plays the start sound and loops the progress sound", function()
	local s = C.New(RED)
	local events = C.Step(s, Input(0, 0, 1))
	T.eq(events[1].kind, "start", "the area's start event")
	T.eq(Sounds(events[1]), "true|" .. Capture.SOUND_START .. "|" .. Capture.SOUND_PROGRESS)
end)

T.test("a block loops the interrupted sound, and its end restarts the progress loop", function()
	T.eq(Sounds(Event("blocked", "value", true)), "true|nil|" .. Capture.SOUND_INTERRUPTED)
	T.eq(Sounds(Event("blocked", "value", false)), "true|" .. Capture.SOUND_START .. "|" .. Capture.SOUND_PROGRESS)
end)

T.test("a finished capture stops the loop and plays the end sound", function()
	T.eq(Sounds(Event("end", "team", BLU)), "true|" .. Capture.SOUND_END .. "|nil")
end)

-- BreakCapture calls CaptureEnd too (trigger_area_capture.cpp).
T.test("a broken capture stops the loop and plays the end sound", function()
	T.eq(Sounds(Event("break", "team", BLU)), "true|" .. Capture.SOUND_END .. "|nil")
end)

T.test("events without sounds change nothing", function()
	T.eq(Sounds(Event("numcappers", "n", 1)), "false|nil|nil")
	T.eq(Sounds(Event("capturestart", "team", BLU)), "false|nil|nil")
end)

T.test("a point with no cap sounds only stops its loop", function()
	local flags = Capture.SF_NO_CAP_SOUNDS + Capture.SF_HIDE_MODEL
	T.eq(Sounds(Event("start", "team", BLU), flags), "true|nil|nil")
	T.eq(Sounds(Event("blocked", "value", true), flags), "true|nil|nil")
	T.eq(Sounds(Event("end", "team", BLU), flags), "true|nil|nil")
	T.eq(Sounds(Event("break", "team", BLU), flags), "true|nil|nil")
end)

-- CaptureThink's m_Blockers: a block is told with its first defender,
-- once a capture attempt while they stay on the point; one who stepped off
-- and back, or a new attempt, is told again.
T.test("a defender is told of once a capture attempt while they stay on the point", function()
	local s = C.New(NOBODY)
	C.Step(s, Input(0, 1, 0))
	local on = { alice = true }
	local function OnPoint(b) return on[b] == true end
	T.eq(C.TellBlock(s, "alice", OnPoint), true, "the first block")
	T.eq(C.TellBlock(s, "alice", OnPoint), false, "again, still on the point")
	T.eq(C.TellBlock(s, "bob", OnPoint), true, "another defender")
	on.alice = false
	C.TellBlock(s, "bob", OnPoint)
	on.alice = true
	T.eq(C.TellBlock(s, "alice", OnPoint), true, "stepped off and back")
end)

T.test("a new capture attempt tells every defender again", function()
	local s = C.New(NOBODY)
	C.Step(s, Input(0, 1, 0))
	local function OnPoint() return true end
	C.TellBlock(s, "alice", OnPoint)
	C.Step(s, Input(1, 0, 0))
	C.Step(s, Input(30, 0, 0))
	C.Step(s, Input(31, 1, 0))
	T.eq(s.capturing, true, "a new attempt")
	T.eq(C.TellBlock(s, "alice", OnPoint), true, "told again")
end)

T.finish()
