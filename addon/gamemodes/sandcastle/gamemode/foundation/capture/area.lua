-- CTriggerAreaCapture (trigger_area_capture.cpp) as a pure state machine:
-- each think takes the players standing in the area and returns the events
-- the SDK's area would raise, in its order. The capture controller turns
-- the events into outputs, ownership changes, sounds and callbacks.
--
-- Events: { kind = "start" | "break" | "end" | "capturestart", team },
-- { kind = "numcappers", n, blocked } (SetNumCappers), { kind = "blocked", value,
-- capping } (UpdateBlocked), { kind = "owner", old, team } (the area's new owner).
local band = bit.band
local ipairs = ipairs
local Capture = require("foundation.capture")
local Teams = require("foundation.teams")
module(...)

-- mp_blockstyle: whether a block ends the capture or pauses it.
BLOCKSTYLE_BREAK, BLOCKSTYLE_PAUSE = 0, 1

-- SetNumCappers: OnNumCappersChanged2 carries -1 while a block pauses the
-- capture (the cart stands still on a hill).
CAPPERS_BLOCKED = -1

local NOBODY, RED, BLUE = Teams.UNASSIGNED, Teams.RED, Teams.BLUE
local TEAMS = { RED, BLUE }

function New(owner)
	return {
		owner = owner,
		capturing = false,
		cappingTeam = NOBODY,
		timeRemaining = 0,
		blocked = false,
		lastReduction = 0,
		touching = { [RED] = 0, [BLUE] = 0 },
		teamInZone = NOBODY,
	}
end

-- Under mp_capstyle 1 more players cap faster, from a longer base time.
function TotalTime(capTime, scales, numRequired)
	if scales then return capTime * 2 * numRequired end
	return capTime
end

local function Total(s, i)
	return TotalTime(i.capTime, i.scales, i.numRequired[s.cappingTeam])
end

-- UpdateNumPlayers: the capping team's count goes to SetNumCappers.
local function NumPlayers(s, ev, blocked)
	if s.cappingTeam ~= NOBODY then
		ev[#ev + 1] = { kind = "numcappers", n = s.touching[s.cappingTeam], blocked = blocked }
	end
end

local function Start(s, ev, team, i)
	ev[#ev + 1] = { kind = "start", team = team }
	s.cappingTeam = team
	NumPlayers(s, ev, false)
	s.timeRemaining = Total(s, i)
	s.capturing, s.blocked = true, false
	s.lastReduction = i.now
	ev[#ev + 1] = { kind = "capturestart", team = team }
end

local function End(s, ev)
	local team = s.cappingTeam
	ev[#ev + 1] = { kind = "end", team = team }
	ev[#ev + 1] = { kind = "owner", old = s.owner, team = team }
	s.owner = team
	s.capturing, s.cappingTeam, s.timeRemaining = false, NOBODY, 0
	ev[#ev + 1] = { kind = "numcappers", n = 0, blocked = false }
end

-- BreakCapture
local function BreakInto(s, ev)
	if not s.capturing then return end
	ev[#ev + 1] = { kind = "break", team = s.cappingTeam }
	s.capturing, s.cappingTeam, s.timeRemaining = false, NOBODY, 0
	ev[#ev + 1] = { kind = "numcappers", n = 0, blocked = false }
end

local function SetBlocked(s, ev, value)
	if s.blocked == value then return end
	s.blocked = value
	ev[#ev + 1] = { kind = "blocked", value = value, capping = s.cappingTeam }
end

-- Record the counts; returns teams in the zone and whether any count changed.
local function Survey(s, counts)
	local teamsInZone, changed = 0, false
	s.teamInZone = NOBODY
	for _, team in ipairs(TEAMS) do
		if s.touching[team] ~= counts[team] then
			s.touching[team] = counts[team]
			changed = true
		end
		if counts[team] > 0 then
			teamsInZone = teamsInZone + 1
			s.teamInZone = team
		end
	end
	if teamsInZone > 1 then s.teamInZone = NOBODY end
	return teamsInZone, changed
end

-- Time taken off this think: diminishing returns for each extra capper.
local function Reduction(s, i, dt)
	local reduction = dt
	if i.scales then
		for k = 1, (s.touching[s.teamInZone] or 0) - 1 do
			reduction = reduction + dt / (k + 1)
		end
	end
	return reduction
end

local function Advance(s, ev, i, teamsInZone)
	local dt = i.now - s.lastReduction
	local reduction = Reduction(s, i, dt)
	s.lastReduction = i.now
	if teamsInZone > 1 then
		SetBlocked(s, ev, true)
		if i.blockstyle == BLOCKSTYLE_BREAK then BreakInto(s, ev) end
		return
	end
	SetBlocked(s, ev, false)
	local total = Total(s, i)
	if s.cappingTeam == s.teamInZone then
		s.timeRemaining = s.timeRemaining - reduction
	elseif s.owner == NOBODY and s.teamInZone ~= NOBODY then
		s.timeRemaining = s.timeRemaining + reduction
	elseif i.teamMayCapture(s.cappingTeam) then
		-- caps deteriorate over time, six times as fast in overtime
		local scale = i.scales and i.deteriorate or total
		local decrease = total / scale * dt
		if i.overtime then decrease = decrease * 6 end
		s.timeRemaining = s.timeRemaining + decrease
	else
		s.timeRemaining = total
	end
	if s.timeRemaining <= 0 then
		End(s, ev)
	elseif s.timeRemaining >= total then
		BreakInto(s, ev)
	end
end

local function TryStart(s, ev, i)
	for _, team in ipairs(TEAMS) do
		local n = s.touching[team]
		if i.canCap[team] and s.owner ~= team and n > 0 and n >= i.startRequired[team]
			and (i.scales or n >= i.numRequired[team]) then
			Start(s, ev, team, i)
			return
		end
	end
end

-- CaptureThink. i = { now, pointsMayBeCaptured, counts, canCap, numRequired,
-- startRequired, capTime, scales (mp_capstyle), blockstyle, deteriorate,
-- overtime, teamMayCapture(team) }.
function Step(s, i)
	local ev = {}
	if not i.pointsMayBeCaptured then
		BreakInto(s, ev)
		return ev
	end
	local teamsInZone, changed = Survey(s, i.counts)
	-- BLOCKSTYLE_PAUSE: a block pauses the capture and tells the capping
	-- team's listeners there are no cappers (-1 on OnNumCappersChanged2)
	local blocked = false
	if i.blockstyle == BLOCKSTYLE_PAUSE and s.capturing and teamsInZone > 1 then
		blocked = true
		for _, team in ipairs(TEAMS) do
			if s.touching[team] ~= 0 then
				s.touching[team] = 0
				changed = true
			end
		end
	end
	if changed then NumPlayers(s, ev, blocked) end
	if s.capturing then
		Advance(s, ev, i, teamsInZone)
	elseif teamsInZone > 0 then
		TryStart(s, ev, i)
	end
	return ev
end

-- InputCaptureCurrentCP
function CaptureCurrent(s)
	local ev = {}
	if s.capturing then End(s, ev) end
	return ev
end

-- An admin's capture for team (Set Team): the area ends a capture for it as
-- a finished one would, whatever was running.
function CaptureFor(s, team)
	local ev = {}
	s.cappingTeam = team
	End(s, ev)
	return ev
end

-- InputSetControlPoint's BreakCapture
function Break(s)
	local ev = {}
	BreakInto(s, ev)
	return ev
end

-- The HUD's capture progress, 0 (none) to 1 (captured).
function Progress(s, i)
	if not s.capturing then return 0 end
	return 1 - s.timeRemaining / Total(s, i)
end

-- The point's capture sounds for an area event (e): StartCapture's
-- UpdateBlocked and UpdateBlocked itself call CTeamControlPoint::
-- CaptureInterrupted, EndCapture and BreakCapture call CaptureEnd. Each
-- stops the looping sound first; spawnflag SF_NO_CAP_SOUNDS silences the rest.
-- sounds = the point's { start, stop, progress, interrupted }
-- (point_capture_*_sound, PointSet:Sounds). All play from the point.
-- Returns { play = a sound or nil, loop = a looping sound or nil, stopLoop }.
local function Interrupted(blocked, sounds)
	if blocked then
		return {
			loop = sounds.interrupted,
			stopLoop = true,
		}
	end
	return {
		play = sounds.start,
		loop = sounds.progress,
		stopLoop = true,
	}
end

local function CaptureEnd(sounds)
	return {
		play = sounds.stop,
		stopLoop = true,
	}
end

local SOUNDS = {
	start = function(e, sounds) return Interrupted(false, sounds) end,
	blocked = function(e, sounds) return Interrupted(e.value, sounds) end,
	["end"] = function(e, sounds) return CaptureEnd(sounds) end,
	["break"] = function(e, sounds) return CaptureEnd(sounds) end,
}

function PointSounds(e, spawnflags, sounds)
	local handler = SOUNDS[e.kind]
	if not handler then return { stopLoop = false } end
	if band(spawnflags, Capture.SF_NO_CAP_SOUNDS) ~= 0 then return { stopLoop = true } end
	return handler(e, sounds)
end

-- HandleRespawnTimeAdjustments: undo the old owner's team_spawn_N, apply the new one's.
function SpawnAdjustments(old, new, spawnAdjust)
	local out = {}
	if old >= Teams.FIRST_GAME_TEAM and spawnAdjust[old] ~= 0 then out[#out + 1] = { team = old, seconds = -spawnAdjust[old] } end
	if new >= Teams.FIRST_GAME_TEAM and spawnAdjust[new] ~= 0 then out[#out + 1] = { team = new, seconds = spawnAdjust[new] } end
	return out
end
