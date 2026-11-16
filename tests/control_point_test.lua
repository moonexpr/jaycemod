-- control_point: a team_control_point's own state (CTeamControlPoint,
-- team_control_point.cpp): its owner, its lock and timed unlock, and what
-- each change sounds and fires.
local T = dofile ("tests/harness.lua")
local Point = control_point

local NOBODY, RED, BLUE = TF_TEAM_UNASSIGNED, TEAM_RED, TEAM_BLUE
local NOW = 100

local function New (spec)
	spec = spec or {}
	spec.id = spec.id or "cap_a"
	return Point.New (spec)
end

local function Kinds (events)
	local kinds = {}
	for i, e in ipairs (events) do kinds [i] = e.kind end
	return table.concat (kinds, ",")
end

T.test ("a point the map says nothing of is nobody's, unlocked, with TF2's sounds and icons", function ()
	local p = New ()
	T.eq (p.owner,              NOBODY,                   "nobody's")
	T.eq (p.locked,             false,                    "unlocked")
	T.eq (p.index,              0,                        "index 0")
	T.eq (p.group,              0,                        "group 0")
	T.eq (p.printName,          "",                       "no name")
	T.eq (p.warnOnCap,          Point.CP_WARN.NORMAL,     "warns as any point")
	T.eq (p.warnSound,          Point.WARN_SOUND_DEFAULT, "the default warning")
	T.eq (p.sounds.start,       Point.SOUND_START,        "the hologram's start")
	T.eq (p.sounds.interrupted, Point.SOUND_INTERRUPTED,  "and interruption")
	T.eq (p.icons [RED],        Point.ICON_DEFAULT [RED], "RED's icon")
end)

T.test ("it starts as the map set it, an empty sound or icon keeping the default", function ()
	local p = New (
		{
			index = 2,
			defaultOwner = BLUE,
			startLocked = true,
			printName = "the Bridge",
			sounds = { start = "My.Start", stop = "" },
			icons = { [BLUE] = "my/icon", [RED] = "" }
		}
	)
	T.eq (p.owner,        BLUE,                     "its default owner's")
	T.eq (p.locked,       true,                     "locked")
	T.eq (p.sounds.start, "My.Start",               "the map's sound")
	T.eq (p.sounds.stop,  Point.SOUND_END,          "an empty one is the default")
	T.eq (p.icons [BLUE], "my/icon",                "the map's icon")
	T.eq (p.icons [RED],  Point.ICON_DEFAULT [RED], "an empty one is the default")
end)

T.test ("a capture changes the owner, sounding and scoring, with its cappers and its sound", function ()
	local p = New ({ capSounds = { [RED] = "Cap.Red" } })
	local events = p:SetOwner (RED, Point.CAUSE_CAPTURE, true, { "Ann" })
	T.eq (Kinds (events), "owner", "one change of owner")
	local e = events [1]
	T.eq (e.id,               "cap_a",             "the point's")
	T.eq (e.old,              NOBODY,              "from nobody")
	T.eq (e.team,             RED,                 "to RED")
	T.eq (e.sounding,         true,                "sounding")
	T.eq (e.scoring,          true,                "scoring")
	T.eq (e.bell,             Point.CAPTURE_BELL,  "the bell")
	T.eq (e.cappers [1],      "Ann",               "its cappers")
	T.eq (e.lines [1].sound,  "Cap.Red",           "the team's capture sound")
	T.eq (e.lines [1].hearer, Point.HEAR_EVERYONE, "to everyone")
	T.eq (p.owner,            RED,                 "RED's now")
end)

T.test ("nothing but a forced owner changes while points may not be captured", function ()
	local p = New ()
	T.eq (Kinds (p:SetOwner (RED, Point.CAUSE_CAPTURE, false)),      "",     "a capture")
	T.eq (Kinds (p:SetOwner (RED, Point.CAUSE_INPUT, false)),        "",     "an input")
	T.eq (Kinds (p:SetOwner (RED, Point.CAUSE_PLAYER_INPUT, false)), "",     "a player's input")
	T.eq (p.owner,                                                   NOBODY, "still nobody's")
	local e = p:SetOwner (RED, Point.CAUSE_FORCE, false) [1]
	T.eq (p.owner,    RED,   "forced")
	T.eq (e.sounding, false, "silently")
	T.eq (e.scoring,  false, "unscored")
	T.eq (e.bell,     nil,   "no bell")
	T.eq (#e.cappers, 0,     "nobody named")
end)

T.test ("an input naming the owner it has does nothing; a relay's is scored but silent, a player's sounds", function ()
	local p = New ({ defaultOwner = RED })
	T.eq (Kinds (p:SetOwner (RED, Point.CAUSE_INPUT, true)), "", "already RED's")
	local relay = p:SetOwner (BLUE, Point.CAUSE_INPUT, true) [1]
	T.eq (relay.sounding, false, "a relay's is silent")
	T.eq (relay.scoring,  true,  "but a team took it")
	local player = p:SetOwner (RED, Point.CAUSE_PLAYER_INPUT, true) [1]
	T.eq (player.sounding, true, "a player's sounds")
	local reset = p:SetOwner (NOBODY, Point.CAUSE_INPUT, true) [1]
	T.eq (reset.scoring, false, "a reset to nobody scores nothing")
end)

T.test ("unlocking fires OnUnlocked, even of an unlocked point; locking fires nothing", function ()
	local p = New ({ startLocked = true })
	T.eq (Kinds (p:SetLocked (false)), "unlocked", "unlocked")
	T.eq (p.locked,                    false,      "open")
	T.eq (Kinds (p:SetLocked (false)), "unlocked", "again")
	T.eq (Kinds (p:SetLocked (true)),  "",         "locking")
	T.eq (p.locked,                    true,       "locked")
end)

T.test ("a timed unlock waits for its time and for the round to run", function ()
	local p = New ({ startLocked = true })
	local events = p:SetUnlockTime (10, NOW)
	T.eq (Kinds (events),                    "unlock_time", "its time told")
	T.eq (events [1].at,                     NOW + 10,      "ten seconds on")
	T.eq (p.shownUnlockAt,                   NOW + 10,      "shown to the HUD")
	T.eq (Kinds (p:Think (NOW + 5, true)),   "",            "not yet")
	T.eq (Kinds (p:Think (NOW + 11, false)), "",            "not while the round is not running")
	T.eq (p.locked,                          true,          "still locked")
	T.eq (Kinds (p:Think (NOW + 11, true)),  "unlocked",    "unlocked once it runs")
	T.eq (p.locked,                          false,         "open")
	T.eq (p.shownUnlockAt,                   nil,           "the HUD's time gone")
	T.eq (Kinds (p:Think (NOW + 12, true)),  "",            "once")
end)

T.test ("an unlock time of none unlocks now; locking again keeps a pending unlock running", function ()
	local p = New ({ startLocked = true })
	T.eq (Kinds (p:SetUnlockTime (0, NOW)), "unlocked", "now")
	p:SetLocked (true)
	p:SetUnlockTime (10, NOW)
	p:SetLocked (true)
	T.eq (p.shownUnlockAt,                  nil,        "the HUD loses the time")
	T.eq (Kinds (p:Think (NOW + 11, true)), "unlocked", "the unlock still comes")
end)

T.test ("a round activating tells whose it starts as, and its lock again", function ()
	local owned = New ({ defaultOwner = BLUE })
	local events = owned:RoundActivate ()
	T.eq (Kinds (events),                                        "round_start_owned,unlocked", "owned and open")
	T.eq (events [1].team,                                       BLUE, "BLU's")
	T.eq (Kinds (New ({ startLocked = true }):RoundActivate ()), "", "nobody's and locked: nothing")
end)

T.test ("a capture starting is heard by those not capping: contested, or the final warning", function ()
	local p = New ({ defaultOwner = RED })
	local line = p:CaptureStarted (BLUE, NOW) [1]
	T.eq (line.sound,                                  Point.CONTESTED,         "contested")
	T.eq (line.hearer,                                 Point.HEAR_OTHERS,       "to the others")
	T.eq (line.team,                                   BLUE,                    "than the cappers")
	T.eq (New ():CaptureStarted (BLUE, NOW) [1].sound, Point.CONTESTED_NEUTRAL, "a neutral point")
	T.eq (#p:CaptureStarted (NOBODY, NOW),             0,                       "nobody capping")
	local final = New ({ warnOnCap = Point.CP_WARN.FINALCAP, warnSound = "Final.Warn" })
	T.eq (final:CaptureStarted (BLUE, NOW) [1].sound,                  "Final.Warn", "the warning")
	T.eq (#final:CaptureStarted (BLUE, NOW + Point.WARN_INTERVAL),     0,            "not again within the interval")
	T.eq (#final:CaptureStarted (BLUE, NOW + Point.WARN_INTERVAL + 1), 1,            "again after it")
	local quiet = New ({ warnOnCap = Point.CP_WARN.NO_ANNOUNCEMENTS })
	T.eq (#quiet:CaptureStarted (BLUE, NOW), 0, "a point with no announcements")
end)

T.finish ()
