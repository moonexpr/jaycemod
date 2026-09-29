-- The capture system: a PointSet holding every control point of a map
-- (team_control_point, team_control_point.cpp) with the rules TF2 spreads
-- over the point, the master's point list and the gamerules: owners, locks
-- and timed unlocks, capture order (CTFGameRules::TeamMayCapturePoint),
-- groups, and why a player may not capture (the HUD's capture panel).
-- Its parts: .area (a trigger_capture_area's capture) and .master (the
-- master and its mini-rounds).
module(...)

-- A control point index or rank that names no point (the SDK's -1).
NO_POINT = -1
MAX_PREVIOUS_POINTS = 3 -- team_control_point.h

-- shareddefs.h: point_warn_on_cap
CP_WARN = {
	NORMAL = 0,
	FINALCAP = 1,
	NO_ANNOUNCEMENTS = 2,
}

-- team_control_point.h spawnflags
SF_HIDE_MODEL = 2 -- SF_CAP_POINT_HIDE_MODEL
SF_NO_CAP_SOUNDS = 8 -- SF_CAP_POINT_NO_CAP_SOUNDS

-- The point_capture_*_sound defaults (CTeamControlPoint::Spawn).
SOUND_START = "Hologram.Start"
SOUND_END = "Hologram.Stop"
SOUND_PROGRESS = "Hologram.Move"
SOUND_INTERRUPTED = "Hologram.Interrupted"
