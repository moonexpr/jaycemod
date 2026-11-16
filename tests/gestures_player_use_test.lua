-- The gesture of +use: what a player's use key shows (Sandcastle's base gamemode).
local T = dofile ("tests/harness.lua")

-- GMod's activities, which the module reads as it loads: distinct numbers stand in for them.
local ACTIVITIES =
{
	"ACT_MP_STAND_IDLE", "ACT_MP_WALK", "ACT_MP_RUN", "ACT_MP_CROUCH_IDLE", "ACT_MP_CROUCHWALK", "ACT_MP_JUMP",
	"ACT_MP_SWIM", "ACT_MP_SWIM_IDLE", "ACT_HL2MP_IDLE_MAGIC", "ACT_HL2MP_WALK_MAGIC", "ACT_HL2MP_RUN_MAGIC",
	"ACT_HL2MP_IDLE_CROUCH_MAGIC", "ACT_HL2MP_WALK_CROUCH_MAGIC", "ACT_HL2MP_JUMP_MAGIC", "ACT_HL2MP_SWIM_MAGIC",
	"ACT_HL2MP_SWIM_IDLE_MAGIC", "ACT_SIGNAL_FORWARD", "ACT_MP_ATTACK_STAND_PRIMARYFIRE"
}
for index, name in ipairs (ACTIVITIES) do _G [name] = 9000 + index end

-- Loaded as shared.lua loads it, in neither realm: the rules and the shared hooks only.
local gestures = {}
local chunk    = assert (loadfile ("addons/sandcastle/gamemodes/sandcastle/gamemode/gestures/player_use.lua"))
setfenv (chunk, setmetatable ({ GM = {}, gestures = gestures, DEFINE_BASECLASS = function () end }, { __index = _G }))
chunk ()
local UseEffects = gestures.player_use

T.test ("the tuning is defined", function ()
	T.defined (UseEffects.DURATION,         "DURATION")
	T.defined (UseEffects.COOLDOWN,         "COOLDOWN")
	T.defined (UseEffects.GESTURE_COOLDOWN, "GESTURE_COOLDOWN")
	T.defined (UseEffects.MIN_BRIGHTNESS,   "MIN_BRIGHTNESS")
	T.defined (UseEffects.NUDGE_RISE,       "NUDGE_RISE")
	T.defined (UseEffects.NUDGE_LIFE,       "NUDGE_LIFE")
end)

T.test ("a crate or a button is used in place; an item or a weapon is taken; anything else shows nothing", function ()
	T.eq (UseEffects.Kind ("item_ammo_crate"), "interact", "ammo crate")
	T.eq (UseEffects.Kind ("func_button"),     "interact", "button")
	T.eq (UseEffects.Kind ("item_healthkit"),  "pickup",   "item")
	T.eq (UseEffects.Kind ("weapon_smg1"),     "pickup",   "weapon")
	T.eq (UseEffects.Kind ("prop_physics"),    nil,        "prop")
	T.eq (UseEffects.Kind ("my_item_thing"),   nil,        "item_ only as a prefix")
end)

T.test ("doors, buttons, crates and chargers take a swipe of the hand", function ()
	for _, class in ipairs ({ "func_door", "prop_door_rotating", "func_button", "item_ammo_crate", "item_healthcharger" }) do
		T.eq (UseEffects.Swipes (class), true, class)
	end
	T.eq (UseEffects.Swipes ("prop_physics"), false, "prop")
	T.eq (UseEffects.Swipes ("weapon_smg1"),  false, "weapon")
end)

T.test ("a pickup worked when the item is gone or the weapon is the player's", function ()
	T.eq (UseEffects.Succeeded (false, false), true,  "gone")
	T.eq (UseEffects.Succeeded (true, true),   true,  "owned")
	T.eq (UseEffects.Succeeded (true, false),  false, "still lying there")
end)

T.test ("a carrying player takes the magic pose in every stance, and only then", function ()
	T.eq (UseEffects.CarryActivity (true, ACT_MP_STAND_IDLE),               ACT_HL2MP_IDLE_MAGIC, "stand")
	T.eq (UseEffects.CarryActivity (true, ACT_MP_CROUCHWALK),               ACT_HL2MP_WALK_CROUCH_MAGIC, "crouch walk")
	T.eq (UseEffects.CarryActivity (true, ACT_MP_SWIM_IDLE),                ACT_HL2MP_SWIM_IDLE_MAGIC, "swim idle")
	T.eq (UseEffects.CarryActivity (false, ACT_MP_STAND_IDLE),              nil, "not carrying")
	T.eq (UseEffects.CarryActivity (true, ACT_MP_ATTACK_STAND_PRIMARYFIRE), nil, "an activity with no carry pose")
end)

T.test ("the nudge rises to full reach, falls back, and is nothing outside its life", function ()
	T.eq (UseEffects.NudgeAmount (0), 0, "not begun")
	T.near (UseEffects.NudgeAmount (UseEffects.NUDGE_RISE / 2), 0.5, 1e-9, "half way out")
	T.near (UseEffects.NudgeAmount (UseEffects.NUDGE_RISE),     1,   1e-9, "full reach")
	local back = UseEffects.NUDGE_RISE + (UseEffects.NUDGE_LIFE - UseEffects.NUDGE_RISE) / 2
	T.near (UseEffects.NudgeAmount (back), 0.5, 1e-9, "half way back")
	T.eq (UseEffects.NudgeAmount (UseEffects.NUDGE_LIFE), 0, "at rest")
	T.eq (UseEffects.NudgeAmount (-1),                    0, "before it began")
end)

T.test ("neon keeps the hue at full brightness, and a colour with no hue is white", function ()
	local r, g, b = UseEffects.Neon (0.24, 0.34, 0.41)
	T.eq (math.max (r, g, b),                          1,    "brightest channel full")
	T.eq (r < g and g < b,                             true, "channel order kept")
	T.eq (select (1, UseEffects.Neon (0.5, 0.5, 0.5)), 1,    "grey is white")
	local wr, wg, wb = UseEffects.Neon (0, 0, 0)
	T.eq (wr + wg + wb, 3, "black is white")
end)

T.test ("a halo's colour is 0..255, and a dark one is lifted to the floor, keeping its hue", function ()
	local floor = UseEffects.MIN_BRIGHTNESS
	local c = UseEffects.ToColor (1, 0.5, 0)
	T.eq (c.r, 255, "red")
	T.eq (c.g, 128, "green")
	T.eq (c.b, 0,   "blue")
	local dark = UseEffects.ToColor (0.1, 0.05, 0)
	T.eq (dark.r, floor,                        "brightest lifted to the floor")
	T.eq (dark.g, math.floor (floor / 2 + 0.5), "others scaled with it")
	local black = UseEffects.ToColor (0, 0, 0)
	T.eq (black.r == floor and black.g == floor and black.b == floor, true, "black is grey")
end)

T.test ("one player announces at most once a cooldown", function ()
	T.eq (UseEffects.Ready (10, nil),    true,  "never announced")
	T.eq (UseEffects.Ready (10, 10.5),   false, "too soon")
	T.eq (UseEffects.Ready (10.5, 10.5), true,  "cooldown spent")
end)

T.test ("the carry arms show in first person only, while carrying", function ()
	T.eq (UseEffects.ShowCarryArms (true, false),  true,  "carrying, first person")
	T.eq (UseEffects.ShowCarryArms (true, true),   false, "third person")
	T.eq (UseEffects.ShowCarryArms (false, false), false, "not carrying")
end)

T.finish ()
