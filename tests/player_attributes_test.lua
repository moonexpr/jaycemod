local T = dofile("tests/harness.lua")
local Attributes = T.require("foundation.players.attributes")
local Actor = T.require("foundation.npc.actor")

local FIRE = Attributes.FIRE_DAMAGE_TAKEN
local CRIT = "dmg taken from crit reduced"
local UNTIL_REMOVED = Attributes.UNTIL_REMOVED
local HACKSAW = 0.001 -- plr_hacksaw_event's value
local NOW = 100

T.test("fire damage taken scales by the attribute's value", function()
	local attrs = {}
	Attributes.Add(attrs, FIRE, HACKSAW, UNTIL_REMOVED, NOW)
	T.eq(Attributes.DamageTakenScale(attrs, Actor.DMG_BURN, NOW), HACKSAW, "burn")
	T.eq(Attributes.DamageTakenScale(attrs, Attributes.DMG_IGNITE, NOW), HACKSAW, "ignite")
end)

T.test("other damage is untouched", function()
	local attrs = {}
	Attributes.Add(attrs, FIRE, HACKSAW, UNTIL_REMOVED, NOW)
	T.eq(Attributes.DamageTakenScale(attrs, Actor.DMG_BLAST, NOW), 1, "blast")
	T.eq(Attributes.DamageTakenScale({}, Actor.DMG_BURN, NOW), 1, "no attributes")
end)

T.test("a second Add stomps the value and the expiry", function()
	local attrs = {}
	Attributes.Add(attrs, FIRE, HACKSAW, 5, NOW)
	Attributes.Add(attrs, FIRE, 0.5, UNTIL_REMOVED, NOW)
	T.eq(Attributes.DamageTakenScale(attrs, Actor.DMG_BURN, NOW + 10), 0.5, "stomped")
end)

T.test("a timed attribute lasts its duration, then is gone", function()
	local attrs = {}
	Attributes.Add(attrs, FIRE, HACKSAW, 5, NOW)
	T.eq(Attributes.DamageTakenScale(attrs, Actor.DMG_BURN, NOW + 5), HACKSAW, "at the end still on")
	T.eq(Attributes.DamageTakenScale(attrs, Actor.DMG_BURN, NOW + 5.01), 1, "then off")
	T.eq(attrs[FIRE], nil, "removed")
end)

T.test("a zero duration lasts until removed, as -1 does", function()
	local attrs = {}
	Attributes.Add(attrs, FIRE, HACKSAW, 0, NOW)
	T.eq(Attributes.DamageTakenScale(attrs, Actor.DMG_BURN, NOW + 1000), HACKSAW, "still on")
	Attributes.Remove(attrs, FIRE)
	T.eq(Attributes.DamageTakenScale(attrs, Actor.DMG_BURN, NOW), 1, "removed")
end)

T.test("only the fire attribute is supported", function()
	T.eq(Attributes.Supported(FIRE), true, "fire")
	T.eq(Attributes.Supported(CRIT), false, "crit")
	T.eq(Attributes.Supported(""), false, "none")
end)

-- The Wheel of Fate's attributes (CWheelOfDoom::ApplyAttributeToPlayer).
T.test("speed, jump, fall damage and head scale take effect; voice pitch has no counterpart", function()
	local attrs = {}
	T.eq(Attributes.SpeedScale(attrs, NOW), 1, "plain speed")
	T.eq(Attributes.JumpScale(attrs, NOW), 1, "plain jump")
	T.eq(Attributes.FallDamageCancelled(attrs, NOW), false, "falls hurt")
	T.eq(Attributes.HeadScale(attrs, NOW), 1, "plain head")
	Attributes.Add(attrs, Attributes.MOVE_SPEED_BONUS, 2, UNTIL_REMOVED, NOW)
	Attributes.Add(attrs, Attributes.JUMP_HEIGHT_BONUS, 3, UNTIL_REMOVED, NOW)
	Attributes.Add(attrs, Attributes.CANCEL_FALL_DAMAGE, 1, UNTIL_REMOVED, NOW)
	Attributes.Add(attrs, Attributes.HEAD_SCALE, 0.5, 5, NOW)
	T.eq(Attributes.SpeedScale(attrs, NOW), 2, "twice the speed")
	T.eq(Attributes.JumpScale(attrs, NOW), 3, "three times the jump")
	T.eq(Attributes.FallDamageCancelled(attrs, NOW), true, "falls do not hurt")
	T.eq(Attributes.HeadScale(attrs, NOW), 0.5, "half a head")
	T.eq(Attributes.HeadScale(attrs, NOW + 6), 1, "until it runs out")
	Attributes.Add(attrs, Attributes.CANCEL_FALL_DAMAGE, 0, UNTIL_REMOVED, NOW)
	T.eq(Attributes.FallDamageCancelled(attrs, NOW), false, "a 0 cancels nothing")
	for _, name in ipairs({ Attributes.MOVE_SPEED_BONUS, Attributes.JUMP_HEIGHT_BONUS, Attributes.CANCEL_FALL_DAMAGE, Attributes.HEAD_SCALE }) do
		T.eq(Attributes.Supported(name), true, name)
	end
	T.eq(Attributes.Supported(Attributes.VOICE_PITCH_SCALE), false, "voice pitch")
end)

local function Trigger(fields)
	return {
		name = FIRE,
		value = HACKSAW,
		duration = fields.duration or UNTIL_REMOVED,
		remove = fields.remove == true,
	}
end

T.test("the trigger adds on entry and takes an untimed attribute back on exit", function()
	local trigger = Trigger({})
	T.eq(Attributes.StartTouchAction(trigger), Attributes.ADD, "enter")
	T.eq(Attributes.EndTouchRemoves(trigger), true, "leave")
end)

T.test("a timed attribute is left to run out", function()
	T.eq(Attributes.EndTouchRemoves(Trigger({ duration = 5 })), false, "leave")
end)

T.test("add_or_remove 1 removes on entry and does nothing on exit", function()
	local trigger = Trigger({ remove = true })
	T.eq(Attributes.StartTouchAction(trigger), Attributes.REMOVE, "enter")
	T.eq(Attributes.EndTouchRemoves(trigger), false, "leave")
end)

T.finish()
