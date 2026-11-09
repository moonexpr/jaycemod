-- Wetsands' side of the flags: game_ctf's tally and lines and the names of a
-- flag's states, as this game's features read them, when flags may be capped by the round's state,
-- the flags' snapshots, the CTF mode (TF_GAMETYPE_CTF) and what TF2's flag
-- panel shows (CTFFlagStatus and CTFArrowPanel, tf_hud_flagstatus.cpp).
local ipairs = ipairs
local Base = game_manager.GetClass("game_ctf")
local Rounds = gameplay.rounds
local State = require("games.gameplay.rounds.state")
local Teams = gameplay.teams
local Snapshot = world.snapshot
module(...)

local RED, BLUE = Teams.RED, Teams.BLUE

-- What item_teamflag networks and its events' kinds.
HOME, CARRIED, DROPPED = "home", "carried", "dropped"
PICKUP, DROP, CAPTURE, RETURN = "pickup", "drop", "capture", "return"
CAPLIMIT_DEFAULT = Base.CAPLIMIT_DEFAULT
NewTally, Lines, InvadeLines = Base.NewTally, Base.Lines, Base.InvadeLines

-- CTFGameRules::FlagsMayBeCapped: not in the pre-round nor after a win;
-- nor, in a mode whose flags wait for the wave (MvM's bomb), in setup.
function MayBeCapped(state, inSetup, waitsForWave)
	if waitsForWave and inSetup then return false end
	return state ~= State.PREROUND and state ~= State.TEAM_WIN
end

-- The flag as plain data (games.world.snapshot): its carrier through
-- refs, its return kept as seconds from now.
local SNAPSHOT = Snapshot.Spec({
	name = "flag",
	times = { "returnAt" },
})

function SnapshotFlag(flag, now, refs) return Snapshot.Take(flag, SNAPSHOT, now, refs) end
function RestoreFlag(flag, snapshot, now, refs) Snapshot.Apply(flag, snapshot, SNAPSHOT, now, refs) end

local TALLY_SNAPSHOT = Snapshot.Spec({ name = "tally" })

function Base.TallyClass:Snapshot() return Snapshot.Take(self, TALLY_SNAPSHOT, 0) end
function Base.TallyClass:Restore(snapshot) Snapshot.Apply(self, snapshot, TALLY_SNAPSHOT, 0) end

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
