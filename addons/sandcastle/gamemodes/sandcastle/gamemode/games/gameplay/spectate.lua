-- Pure rules of TF2's observer: death phases, mode cycling, valid targets and
-- target cycling (tf_player.cpp, player.cpp). No GMod globals: sv_spectate.lua
-- turns entities into the plain descriptors used here.
--
-- Modes are named, not numbered: "fixed", "in_eye", "chase", "roaming".
-- Target descriptors: { id, kind = "player"|"npc"|"point"|"entity", team,
--   alive (players, NPCs), deathTime (players), enabled, associatedTeam
--   (points), train (entities) }. NPCs are Sandcastle's own: watched as a
--   player of their team is, in any mode, while they live.
-- Viewer: { id, team }. Rules: { forcecamera, teamWin, now }.
local ipairs = ipairs
local Teams = gameplay.teams
module(...)

local NOBODY, SPECTATOR, FIRST_GAME_TEAM = Teams.UNASSIGNED, Teams.SPECTATOR, Teams.FIRST_GAME_TEAM

-- mp_forcecamera values (shareddefs.h OBS_ALLOW_*)
FORCE_ALL = 0
FORCE_TEAM = 1
FORCE_NONE = 2

TIMES = {
	deathAnim = 2.0,         -- TF_DEATH_ANIMATION_TIME
	freezeTravel = 0.4,      -- spec_freeze_traveltime
	freezeTime = 4.0,        -- spec_freeze_time
	abortGrace = 0.5,        -- CTFPlayer::AttemptToExitFreezeCam
	freezeSoundLength = 0.3, -- StateThinkDYING's TFPlayer.FreezeCam lead
	watchDead = 3.0,         -- DEATH_ANIMATION_TIME (baseplayer_shared.h)
}

local function FreezeEnd(deathTime)
	return deathTime + TIMES.deathAnim + TIMES.freezeTravel + TIMES.freezeTime
end

-- CTFPlayer::StateThinkDYING: deathcam for the death animation, then the
-- freezecam on the killer, then observing. Without a killer the deathcam
-- holds until the freezecam would have ended, since nobody respawns earlier.
function DeathPhase(now, deathTime, hasKiller, aborted)
	if not deathTime or aborted then return "observer" end
	if now < deathTime + TIMES.deathAnim then return "deathcam" end
	if now >= FreezeEnd(deathTime) then return "observer" end
	return hasKiller and "freezecam" or "deathcam"
end

function CanAbortFreezeCam(now, deathTime)
	return now >= deathTime + TIMES.deathAnim + TIMES.freezeTravel + TIMES.abortGrace
end

function FreezeSoundTime(deathTime)
	return deathTime + TIMES.deathAnim + TIMES.freezeTravel - TIMES.freezeSoundLength
end

-- spec_mode steps IN_EYE -> CHASE -> (POI) -> ROAMING -> IN_EYE, and
-- CTFPlayer::SetObserverMode turns ROAMING into IN_EYE for team players.
local NEXT = { fixed = "in_eye", in_eye = "chase", chase = "roaming", roaming = "in_eye" }
function NextMode(mode, isSpectator)
	local nextMode = NEXT[mode]
	if nextMode == "roaming" and not isSpectator then return "in_eye" end
	return nextMode
end

-- The mode the camera shows for a target kind. Roaming stays roaming (it
-- starts from the target). An observer point is a fixed camera
-- (C_BasePlayer::CalcChaseCamView treats a model-less target so); only
-- players and NPCs can be watched in-eye (CTFPlayer::ValidateCurrentObserverTarget
-- allows players alone; Sandcastle's NPCs are watched as players are);
-- without a target the view holds still (ValidateCurrentObserverTarget, TF_DLL).
function ViewMode(mode, kind)
	if mode == "roaming" then return "roaming" end
	if kind == "point" or kind == nil then return "fixed" end
	if kind == "entity" and mode ~= "chase" then return "chase" end
	return mode
end

-- CObserverPoint::CanUseObserverPoint (without the mini-round check).
local function CanUsePoint(viewer, point, rules)
	if not point.enabled then return false end
	if point.associatedTeam and rules.forcecamera == FORCE_TEAM and not rules.teamWin
		and point.associatedTeam ~= viewer.team and viewer.team >= FIRST_GAME_TEAM then
		return false
	end
	return true
end

local function ForceCameraAllows(viewer, targetTeam, rules)
	if rules.forcecamera == FORCE_TEAM then return targetTeam == viewer.team end
	return rules.forcecamera == FORCE_ALL
end

-- CTFPlayer::IsValidObserverTarget, non-player branch.
local function ValidEntity(viewer, target, rules)
	if target.kind == "point" and not CanUsePoint(viewer, target, rules) then return false end
	if target.train and rules.teamWin then return false end
	if viewer.team == SPECTATOR then return true end
	if target.team == NOBODY and rules.forcecamera ~= FORCE_NONE then return true end
	return ForceCameraAllows(viewer, target.team, rules)
end

-- CBasePlayer::IsValidObserverTarget: live players, or the recently dead.
local function ValidPlayer(viewer, target, rules)
	if not target.alive then
		if not target.deathTime or rules.now > target.deathTime + TIMES.watchDead then return false end
	end
	if viewer.team == SPECTATOR then return true end
	return ForceCameraAllows(viewer, target.team, rules)
end

-- A living NPC: a team's under mp_forcecamera as its players are, one of
-- no team (a monster) as any other entity.
local function ValidNpc(viewer, target, rules)
	if not target.alive then return false end
	if viewer.team == SPECTATOR then return true end
	if target.team == NOBODY then return rules.forcecamera ~= FORCE_NONE end
	return ForceCameraAllows(viewer, target.team, rules)
end

function IsValidTarget(viewer, target, rules)
	if not target or target.id == viewer.id then return false end
	if target.kind == "player" then return ValidPlayer(viewer, target, rules) end
	if target.kind == "npc" then return ValidNpc(viewer, target, rules) end
	return ValidEntity(viewer, target, rules)
end

-- CTFPlayer::FindNextObserverTarget over the observable list. current is the
-- index of the present target or nil; returns an index or nil.
function FindNext(list, current, reverse, valid)
	local n = #list
	if n == 0 then return nil end
	local dir = reverse and -1 or 1
	local start = ((current or (reverse and 1 or 0)) - 1 + dir) % n + 1
	local i = start
	repeat
		if valid(list[i]) then return i end
		i = (i - 1 + dir) % n + 1
	until i == start
	return nil
end

-- CTFPlayer::FindNearestObservableTarget, by each candidate's precomputed dist.
function Nearest(list, valid)
	local best, bestDist
	for i, c in ipairs(list) do
		if valid(c) and (not bestDist or c.dist < bestDist) then
			best, bestDist = i, c.dist
		end
	end
	return best
end

-- CTFPlayer::PickWelcomeObserverPoint: walks the points taking each usable
-- one, and stops at the first marked defaultwelcome.
function WelcomePoint(points, valid)
	local chosen
	for i, p in ipairs(points) do
		if valid(p) then chosen = i end
		if p.welcome then break end
	end
	return chosen
end

-- Watching an NPC (WS.NpcCamera, ws/sh_spectate.lua): the
-- engine's observer camera sits at a non-player's origin, at its feet; ours
-- follows its model. First person looks out from just below the top of its
-- bounds; third person over its right shoulder. Points and directions are
-- { x, y, z }; mins and maxs are its world bounds.

NPC_EYE_BELOW_TOP = 8 -- first person sits this far below the top of its bounds
SHOULDER_BELOW_EYE = 6 -- the shoulder the third person camera pivots on
SHOULDER_DISTANCE = 72 -- behind the shoulder, along the view
SHOULDER_RIGHT = 24 -- to the right of it

function NpcFocus(mins, maxs)
	return {
		x = (mins.x + maxs.x) / 2,
		y = (mins.y + maxs.y) / 2,
		z = (mins.z + maxs.z) / 2,
	}
end

function NpcEye(mins, maxs)
	local focus = NpcFocus(mins, maxs)
	focus.z = maxs.z - NPC_EYE_BELOW_TOP
	return focus
end

function ShoulderPivot(mins, maxs)
	local eye = NpcEye(mins, maxs)
	eye.z = eye.z - SHOULDER_BELOW_EYE
	return eye
end

-- Where the camera would be, before walls pull it in: back along the
-- view's forward and out along its right (unit vectors).
function ShoulderOrigin(pivot, forward, right)
	return {
		x = pivot.x - forward.x * SHOULDER_DISTANCE + right.x * SHOULDER_RIGHT,
		y = pivot.y - forward.y * SHOULDER_DISTANCE + right.y * SHOULDER_RIGHT,
		z = pivot.z - forward.z * SHOULDER_DISTANCE + right.z * SHOULDER_RIGHT,
	}
end
