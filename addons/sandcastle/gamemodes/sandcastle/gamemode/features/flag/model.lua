-- The flag feature's model: item_teamflag (CCaptureFlag,
-- entity_capture_flag.cpp) as a pure state machine, the capture zone's rule
-- (CCaptureZone, func_capture_zone.cpp), the CTF tally against
-- tf_flag_caplimit, the CTF mode (TF_GAMETYPE_CTF) and what TF2's flag
-- panel shows (CTFFlagStatus and CTFArrowPanel, tf_hud_flagstatus.cpp).
--
-- A flag is at HOME, CARRIED or DROPPED. Each change returns events
-- { kind, team }: PICKUP and DROP name the carrier's team, CAPTURE the
-- capturing team, RETURN the flag's own. The flag controller turns them
-- into outputs, game events and announcer lines.
local ipairs, setmetatable = ipairs, setmetatable
local Rounds = require("foundation.rounds")
local State = require("foundation.rounds.state")
local Teams = require("foundation.teams")
local Snapshot = require("game.world.snapshot")
module(...)

local NOBODY, RED, BLUE = Teams.UNASSIGNED, Teams.RED, Teams.BLUE
local GAME_TEAMS = { RED, BLUE }

HOME, CARRIED, DROPPED = "home", "carried", "dropped"
PICKUP, DROP, CAPTURE, RETURN = "pickup", "drop", "capture", "return"

-- item_teamflag's ReturnTime default (the FGD's).
RETURN_TIME_DEFAULT = 60
-- tf_flag_caplimit's default.
CAPLIMIT_DEFAULT = 3

-- Who carries, caps and when --------------------------------------------------------

-- CCaptureFlag::PickUp's team check: a neutral flag goes to anyone; a
-- team's to its enemies, or in MvM (ownersCarry) to its own team only.
function MayCarry(flagTeam, carrierTeam, ownersCarry)
	if carrierTeam ~= RED and carrierTeam ~= BLUE then return false end
	if flagTeam == NOBODY then return true end
	if ownersCarry then return flagTeam == carrierTeam end
	return flagTeam ~= carrierTeam
end

-- CTFGameRules::FlagsMayBeCapped: not in the pre-round nor after a win;
-- nor, in a mode whose flags wait for the wave (MvM's bomb), in setup.
function MayBeCapped(state, inSetup, waitsForWave)
	if waitsForWave and inSetup then return false end
	return state ~= State.PREROUND and state ~= State.TEAM_WIN
end

-- CFuncRespawnRoom::RespawnRoomTouch: a carrier running into its own
-- team's respawn room (roomTeam) drops the flag, unless the room is the
-- invaders' (MvM's TF_TEAM_PVE_INVADERS; nil in other modes).
function DropsIn(roomTeam, carrierTeam, invaders)
	return roomTeam == carrierTeam and roomTeam ~= invaders
end

-- CCaptureZone::Touch: a zone caps for carriers of its team, or of any team
-- when it has none.
function MayCapture(zoneTeam, carrierTeam)
	return zoneTeam == NOBODY or zoneTeam == carrierTeam
end

-- The flag --------------------------------------------------------------------------

local Flag = {}
Flag.__index = Flag

-- t = { team, returnTime (seconds), disabled }.
function New(t)
	return setmetatable({
		team = t.team,
		returnTime = t.returnTime or RETURN_TIME_DEFAULT,
		enabled = not t.disabled,
		state = HOME,
		carrier = nil,
		carrierTeam = NOBODY,
		returnAt = 0,
	}, Flag)
end

-- The flag as plain data (game.world.snapshot): its carrier through
-- refs, its return kept as seconds from now.
local SNAPSHOT = Snapshot.Spec({
	name = "flag",
	times = { "returnAt" },
})

function Flag:Snapshot(now, refs) return Snapshot.Take(self, SNAPSHOT, now, refs) end
function Flag:Restore(snapshot, now, refs) Snapshot.Apply(self, snapshot, SNAPSHOT, now, refs) end

function Flag:State() return self.state end
function Flag:Team() return self.team end
function Flag:Enabled() return self.enabled end
function Flag:Carrier() return self.carrier end
function Flag:CarrierTeam() return self.carrierTeam end
function Flag:ReturnTime() return self.returnTime end
function Flag:ReturnAt() return self.returnAt end

function Flag:SetTeam(team) self.team = team end
function Flag:SetReturnTime(seconds) self.returnTime = seconds end

local function Event(kind, team)
	return {
		{
			kind = kind,
			team = team,
		},
	}
end

local function GoHome(self)
	self.state, self.carrier, self.carrierTeam = HOME, nil, NOBODY
end

-- q = { ownersCarry, mayBeCapped }.
function Flag:PickUp(carrier, carrierTeam, q)
	if not self.enabled or self.state == CARRIED or not q.mayBeCapped then return {} end
	if not MayCarry(self.team, carrierTeam, q.ownersCarry) then return {} end
	self.state, self.carrier, self.carrierTeam = CARRIED, carrier, carrierTeam
	return Event(PICKUP, carrierTeam)
end

-- The carrier died, left or was made to drop it (ForceDrop). Dropped in a
-- func_respawnflag zone (inResetZone), it is reset at once
-- (CCaptureFlag::Drop's PointInRespawnFlagZone): DROP, then RETURN.
function Flag:Drop(now, inResetZone)
	if self.state ~= CARRIED then return {} end
	local team = self.carrierTeam
	self.state, self.carrier, self.carrierTeam = DROPPED, nil, NOBODY
	self.returnAt = now + self.returnTime
	local events = Event(DROP, team)
	if inResetZone then events[2] = self:Reset(false)[1] end
	return events
end

-- A dropped flag returns home once its ReturnTime has passed.
function Flag:Think(now)
	if self.state ~= DROPPED or now < self.returnAt then return {} end
	return self:Reset(false)
end

-- ForceReset, or ForceResetSilent: home, announced unless silent.
function Flag:Reset(silent)
	if self.state == HOME then return {} end
	GoHome(self)
	if silent then return {} end
	return Event(RETURN, self.team)
end

-- The carrier stands in a zone of zoneTeam.
function Flag:Capture(zoneTeam)
	if self.state ~= CARRIED or not MayCapture(zoneTeam, self.carrierTeam) then return {} end
	local team = self.carrierTeam
	GoHome(self)
	return Event(CAPTURE, team)
end

-- Enable and Disable: a disabled flag goes home silently.
function Flag:SetEnabled(on)
	self.enabled = on
	if on then return {} end
	return self:Reset(true)
end

-- The announcer ---------------------------------------------------------------------

-- CCaptureFlag's BroadcastSound calls: the acting team (the carrier's, or
-- the flag's on a return) hears the Team line, every other the Enemy line.
local LINES = {
	[PICKUP] = "Stolen",
	[DROP] = "Dropped",
	[CAPTURE] = "Captured",
	[RETURN] = "Returned",
}

function Lines(e)
	local lines = {}
	for _, team in ipairs(GAME_TEAMS) do
		lines[#lines + 1] = {
			team = team,
			sound = "CaptureFlag." .. (team == e.team and "Team" or "Enemy") .. LINES[e.kind],
		}
	end
	return lines
end

-- ResetMessage for MvM's bomb (TF_FLAGTYPE_ATTACK_DEFEND): a return is told
-- to its own team (TF_AD_TEAM_RETURNED) and the defenders
-- (TF_MVM_AD_ENEMY_RETURNED); the bomb's other events go unannounced.
function InvadeLines(e)
	if e.kind ~= RETURN then return {} end
	local lines = {}
	for _, team in ipairs(GAME_TEAMS) do
		lines[#lines + 1] = {
			team = team,
			sound = team == e.team and "AttackDefend.TeamReturned" or "MVM.AttackDefend.EnemyReturned",
		}
	end
	return lines
end

-- The CTF tally ---------------------------------------------------------------------

local Tally = {}
Tally.__index = Tally

function NewTally()
	return setmetatable({ caps = { [RED] = 0, [BLUE] = 0 } }, Tally)
end

local TALLY_SNAPSHOT = Snapshot.Spec({ name = "tally" })

function Tally:Snapshot() return Snapshot.Take(self, TALLY_SNAPSHOT, 0) end
function Tally:Restore(snapshot) Snapshot.Apply(self, snapshot, TALLY_SNAPSHOT, 0) end

function Tally:Captures(team) return self.caps[team] end

-- Counts a capture; true when it brings the team to a limit above 0.
function Tally:Capture(team, limit)
	self.caps[team] = self.caps[team] + 1
	return limit > 0 and self.caps[team] >= limit
end

function Tally:Reset()
	for _, team in ipairs(GAME_TEAMS) do self.caps[team] = 0 end
end

-- The mode --------------------------------------------------------------------------

-- CTFGameRules::Activate: flags make the game CTF over control points; a
-- train watcher's payload, KOTH and the rest outrank it.
Mode = Rounds.Mode:Extend("ctf")
Mode.OBJECTIVE = true
Mode.PRIORITY = 1.5
Mode.FLAG_CAPS_SCORE = true

-- At the time limit the team with more captures this round wins
-- (world.captures, the tally); even captures leave it to the scores.
function Mode:TimelimitWin(world)
	local red, blue = world.captures[RED], world.captures[BLUE]
	if red ~= blue then return red > blue and RED or BLUE, Rounds.WINREASON.MOST_CAPTURES end
	return Rounds.Mode.TimelimitWin(self, world)
end

-- The flag panel --------------------------------------------------------------------

local COLOUR = {
	[RED] = "red",
	[BLUE] = "blue",
}

local STATUS_ICONS = {
	[HOME] = "hud/objectives_flagpanel_ico_flag_home",
	[DROPPED] = "hud/objectives_flagpanel_ico_flag_dropped",
	[CARRIED] = "hud/objectives_flagpanel_ico_flag_moving",
}

-- CTFFlagStatus::UpdateStatus: StatusIcon.
function StatusIcon(state)
	return STATUS_ICONS[state]
end

-- CTFFlagStatus::UpdateStatus: in MvM the Briefcase shows the bomb.
function BombImage(state)
	return state == CARRIED and "hud/bomb_carried" or "hud/bomb_dropped"
end

-- CTFArrowPanel: the flag's colour (grey for a neutral one), an arrow
-- once it leaves home.
function Compass(team, state)
	local colour = COLOUR[team]
	if not colour then return "hud/objectives_flagpanel_compass_grey" end
	return "hud/objectives_flagpanel_compass_" .. colour .. (state == HOME and "_noarrow" or "")
end

-- HudObjectiveFlagPanel.res's two CTFFlagStatus panels, left and right.
SLOT_BLUE, SLOT_RED = "BlueFlag", "RedFlag"

local SLOT_OF = {
	[BLUE] = SLOT_BLUE,
	[RED] = SLOT_RED,
}

-- shown: { team, state, enabled }s. Returns slot -> the flag it shows: in
-- CTF each team's flag in its panel and a neutral one where free; in MvM
-- one bomb on the left, a carried one first. A disabled flag is hidden.
function Slots(shown, mvm)
	local slots = {}
	if mvm then
		for _, f in ipairs(shown) do
			local current = slots[SLOT_BLUE]
			if f.enabled and (not current or (f.state == CARRIED and current.state ~= CARRIED)) then slots[SLOT_BLUE] = f end
		end
		return slots
	end
	for _, f in ipairs(shown) do
		local slot = SLOT_OF[f.team]
		if f.enabled and slot and not slots[slot] then slots[slot] = f end
	end
	for _, f in ipairs(shown) do
		if f.enabled and not SLOT_OF[f.team] then
			if not slots[SLOT_BLUE] then
				slots[SLOT_BLUE] = f
			elseif not slots[SLOT_RED] then
				slots[SLOT_RED] = f
			end
		end
	end
	return slots
end

-- CTFHudFlagObjectives::SetCarriedImage: the flag's colour, a neutral
-- flag's in its carrier's.
function CarriedImage(flagTeam, carrierTeam)
	return "hud/objectives_flagpanel_carried_" .. (COLOUR[flagTeam] or COLOUR[carrierTeam])
end
