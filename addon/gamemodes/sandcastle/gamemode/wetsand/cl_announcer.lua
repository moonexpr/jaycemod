-- The round announcer as each TF2 client plays it. The timer's countdown is
-- CTeamRoundTimer::ClientThink (teamplay_round_timer.cpp): "Mission begins
-- in 60 seconds" ... "1" through setup, "Mission ends in ..." through normal
-- time, and the siren when setup gives way to the round. Only the timer shown
-- in the HUD speaks, and only while it runs with auto_countdown on. Overtime
-- is CTFGameRules::HandleOvertimeBegin. Win, loss, stalemate and sudden death
-- music arrive from the server as wetsand_pa_sound_file.
WETSAND.RoundsLib = WETSAND.require("foundation.rounds")

local SETUP_SOUND = {
	[60] = "Announcer.RoundBegins60Seconds", [30] = "Announcer.RoundBegins30Seconds",
	[10] = "Announcer.RoundBegins10Seconds", [5] = "Announcer.RoundBegins5Seconds",
	[4] = "Announcer.RoundBegins4Seconds", [3] = "Announcer.RoundBegins3Seconds",
	[2] = "Announcer.RoundBegins2Seconds", [1] = "Announcer.RoundBegins1Seconds",
}

local ROUND_SOUND = {
	[60] = "Announcer.RoundEnds60seconds", [30] = "Announcer.RoundEnds30seconds",
	[10] = "Announcer.RoundEnds10seconds", [5] = "Announcer.RoundEnds5seconds",
	[4] = "Announcer.RoundEnds4seconds", [3] = "Announcer.RoundEnds3seconds",
	[2] = "Announcer.RoundEnds2seconds", [1] = "Announcer.RoundEnds1seconds",
}

local ROUND_START_BELL = "Ambient.Siren"
local OVERTIME = "Game.Overtime"

local function Play(name)
	local ply = LocalPlayer()
	if IsValid(ply) then ply:EmitSound(name) end
end

net.Receive("wetsand_pa_sound_file", function()
	Play(net.ReadString())
end)

local serial, wasSetup
local wasOvertime = false
local armed = {}

-- OnDataChanged: overtime beginning is announced once.
local function OvertimeThink()
	local overtime = GetGlobal2Bool("wetsand_round_overtime", false)
	if overtime and not wasOvertime then Play(OVERTIME) end
	wasOvertime = overtime
end

local function CountdownThink()
	if not GetGlobal2Bool("wetsand_timer_shown", false) or WETSAND.GameplayStopped() then return end
	local setup = GetGlobal2Bool("wetsand_timer_in_setup", false)
	local paused = GetGlobal2Bool("wetsand_timer_paused", true)
	local speaks = not paused and GetGlobal2Bool("wetsand_timer_auto_countdown", true)
	local left
	if paused then
		left = GetGlobal2Float("wetsand_timer_time_left", 0)
	else
		left = GetGlobal2Float("wetsand_timer_end_time", 0) - CurTime()
	end

	-- OnDataChanged: setup giving way to normal time rings the bell.
	if wasSetup == true and not setup and speaks then Play(ROUND_START_BELL) end
	wasSetup = setup

	-- The warnings are re-armed whenever the timer's length changes.
	local s = GetGlobal2Int("wetsand_timer_serial", 0)
	if s ~= serial then
		serial = s
		armed = WETSAND.RoundsLib.ArmClientWarnings(left)
	end
	if paused then return end

	local warning = WETSAND.RoundsLib.NextClientWarning(armed, left)
	if warning then
		armed[warning] = false
		if speaks then Play((setup and SETUP_SOUND or ROUND_SOUND)[warning]) end
	end
end

function WETSAND.AnnouncerThink()
	OvertimeThink()
	CountdownThink()
end
