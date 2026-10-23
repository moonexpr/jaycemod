-- The noises a walker's body makes (the AI war's soldiers:
-- ws/sh_drg_soldier.lua), by Source's player rules with HL2's 600 gravity
-- (GMod's): footsteps by its speed (CBasePlayer::UpdateStepSound,
-- GetStepSoundVelocities, SetStepSoundTime), a landing's volume by how fast
-- it fell (CGameMovement::CheckFalling, shareddefs.h's HL2 fall speeds),
-- and how far a noise carries to a listener (DrGBase's hearing of a
-- player's sounds).
module(...)

-- A step below WALK_SPEED is silent; from RUN_SPEED on it is a run (crouched:
-- the crouched speeds).
WALK_SPEED, RUN_SPEED = 90, 220
CROUCH_WALK_SPEED, CROUCH_RUN_SPEED = 60, 80
local WALK_INTERVAL, RUN_INTERVAL = 0.4, 0.3
-- concrete's (the default surface's) volumes, and a crouched step's share
local WALK_VOLUME, RUN_VOLUME, CROUCH_VOLUME = 0.2, 0.5, 0.65

-- How loud a step or landing of volume plays to players: twice Source's,
-- to be heard over the fighting, at most full (ws/sh_footsteps.lua, and the
-- soldiers').
local PLAYED_GAIN = 2

function Played(volume)
	local played = volume * PLAYED_GAIN
	if played > 1 then return 1 end
	return played
end

-- The next step of a walker on the ground at speed, { interval (seconds
-- to the one after), volume, running }, or nil while it is too slow to make
-- one.
function Step(speed, crouched)
	local walk, run = WALK_SPEED, RUN_SPEED
	if crouched then walk, run = CROUCH_WALK_SPEED, CROUCH_RUN_SPEED end
	if speed < walk then return nil end
	local running = speed >= run
	local volume = running and RUN_VOLUME or WALK_VOLUME
	if crouched then volume = volume * CROUCH_VOLUME end
	return { interval = running and RUN_INTERVAL or WALK_INTERVAL, volume = volume, running = running }
end

-- PLAYER_MIN_BOUNCE_SPEED, PLAYER_MAX_SAFE_FALL_SPEED and
-- PLAYER_FALL_PUNCH_THRESHOLD (HL2's), in units a second.
MIN_BOUNCE_SPEED = 173
MAX_SAFE_FALL_SPEED = 526.5
HARD_LANDING_SPEED = 303
-- CheckFalling's volumes: a landing, one past half a safe fall, one past it.
local LANDING_VOLUME, HARDER_VOLUME, UNSAFE_VOLUME = 0.5, 0.85, 1.0
-- A jump onto a ledge (games.nextsoldier.leap) lands as a jump does.
JUMP_LANDING_VOLUME = LANDING_VOLUME

-- The volume of the step a landing at fallSpeed makes; 0, none.
function Landing(fallSpeed)
	if fallSpeed > MAX_SAFE_FALL_SPEED then return UNSAFE_VOLUME end
	if fallSpeed > MAX_SAFE_FALL_SPEED / 2 then return HARDER_VOLUME end
	if fallSpeed < MIN_BOUNCE_SPEED then return 0 end
	return LANDING_VOLUME
end

-- Whether a landing at fallSpeed knocks the walker about (a player's view
-- is punched): its body staggers.
function HardLanding(fallSpeed)
	return fallSpeed >= HARD_LANDING_SPEED
end

-- DrGBase's hearing: a sound of soundLevel and volume carries this far; a
-- listener that cannot see where it was made hears it HIDDEN_HEARING as far.
HIDDEN_HEARING = 0.5

function HearingRange(soundLevel, volume)
	return (soundLevel / 2) ^ 2 * volume
end

-- Whether a listener distance away, seeing the sound's origin or not, with
-- its hearing coefficient (0: deaf), hears it.
function Hears(soundLevel, volume, distance, seen, coefficient)
	local reach = HearingRange(soundLevel, volume) * coefficient
	if not seen then reach = reach * HIDDEN_HEARING end
	return coefficient > 0 and distance <= reach
end
