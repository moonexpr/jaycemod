-- A player's custom attributes (CTFPlayer::AddCustomAttribute and
-- RemoveCustomAttribute), as far as GMod can honour them: map triggers
-- (trigger_add_or_remove_tf_player_attributes) give and take them, and they
-- last until removed, for their duration, or until the player spawns or
-- dies; the Wheel of Fate gives and takes some too. These have an effect:
-- "dmg taken from fire reduced" (mult_dmgtaken_from_fire), and the wheel's
-- "major move speed bonus", "major increased jump height", "cancel falling
-- damage" and "head scale" (the controller applies them to speed, jump
-- power, fall damage and the head bone). GMod has no attribute system for
-- the rest (the wheel's "voice pitch scale" among them: voice chat cannot be
-- pitched), and the trigger says so once.
--
-- Pure functions over one player's attrs table: name -> { value, expireAt }.
local require = require
local Actor = npc.actor
local bor, band = bit.bor, bit.band
local pairs = pairs
module(...)

FIRE_DAMAGE_TAKEN = "dmg taken from fire reduced"

DMG_IGNITE = 16777216 -- TF2's DMG_IGNITE, Source's DMG_PLASMA (1 << 24)
FIRE_DAMAGE = bor(Actor.DMG_BURN, DMG_IGNITE) -- what mult_dmgtaken_from_fire scales

-- The Wheel of Fate's (CWheelOfDoom::ApplyAttributeToPlayer).
MOVE_SPEED_BONUS = "major move speed bonus" -- multiplies top speed
JUMP_HEIGHT_BONUS = "major increased jump height" -- multiplies jump speed
CANCEL_FALL_DAMAGE = "cancel falling damage" -- non-zero: falls do not hurt
HEAD_SCALE = "head scale"
VOICE_PITCH_SCALE = "voice pitch scale"

UNTIL_REMOVED = -1 -- a duration of 0 or less

-- The attributes that change damage taken: name -> the damage bits scaled.
local DAMAGE_TAKEN = {
	[FIRE_DAMAGE_TAKEN] = FIRE_DAMAGE,
}

-- The others with an effect here.
local APPLIED = {
	[MOVE_SPEED_BONUS] = true,
	[JUMP_HEIGHT_BONUS] = true,
	[CANCEL_FALL_DAMAGE] = true,
	[HEAD_SCALE] = true,
}

function Supported(name)
	return DAMAGE_TAKEN[name] ~= nil or APPLIED[name] == true
end

-- AddCustomAttribute: a second add stomps the value and the expiry.
function Add(attrs, name, value, duration, now)
	local expireAt = nil
	if duration > 0 then expireAt = now + duration end
	attrs[name] = {
		value = value,
		expireAt = expireAt,
	}
end

function Remove(attrs, name)
	attrs[name] = nil
end

-- UpdateCustomAttributes removes one once now is past its expiry.
local function Live(attrs, name, now)
	local attr = attrs[name]
	if attr and attr.expireAt and now > attr.expireAt then
		attrs[name] = nil
		return nil
	end
	return attr
end

-- CTFGameRules::ApplyOnDamageModifyRules: the multiplier on damage of
-- dmgType taken.
function DamageTakenScale(attrs, dmgType, now)
	local scale = 1
	for name, bits in pairs(DAMAGE_TAKEN) do
		local attr = Live(attrs, name, now)
		if attr and band(dmgType, bits) ~= 0 then scale = scale * attr.value end
	end
	return scale
end

-- An attribute's value now, or `plain` without it.
local function ValueOr(attrs, name, now, plain)
	local attr = Live(attrs, name, now)
	if attr then return attr.value end
	return plain
end

function SpeedScale(attrs, now) return ValueOr(attrs, MOVE_SPEED_BONUS, now, 1) end
function JumpScale(attrs, now) return ValueOr(attrs, JUMP_HEIGHT_BONUS, now, 1) end
function FallDamageCancelled(attrs, now) return ValueOr(attrs, CANCEL_FALL_DAMAGE, now, 0) ~= 0 end
function HeadScale(attrs, now) return ValueOr(attrs, HEAD_SCALE, now, 1) end

-- CTriggerAddOrRemoveTFPlayerAttributes; trigger = { name, value, duration,
-- remove }.
ADD, REMOVE = "add", "remove"

function StartTouchAction(trigger)
	if trigger.remove then return REMOVE end
	return ADD
end

-- EndTouch takes back only what it added, and leaves a timed one to run
-- out.
function EndTouchRemoves(trigger)
	return not trigger.remove and trigger.duration <= 0
end
