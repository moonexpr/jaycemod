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

-- Loaded as shared.lua loads it, in neither realm: the rules, on the classes it registers.
local registered = {}
local chunk      = assert (loadfile ("addons/sandcastle/gamemodes/sandcastle/gamemode/gestures/player_use.lua"))
local gesture    = { Register = function (name, class) registered [name] = class end }
setfenv (chunk, setmetatable ({ gesture = gesture }, { __index = _G }))
chunk ()
local Use, Carry, Release = registered.player_use, registered.player_carry, registered.player_carry_release

T.test ("the tuning is defined", function ()
	T.defined (Use.Duration,       "Duration")
	T.defined (Use.COOLDOWN,       "COOLDOWN")
	T.defined (Use.SWIPE_COOLDOWN, "SWIPE_COOLDOWN")
	T.defined (Use.MIN_BRIGHTNESS, "MIN_BRIGHTNESS")
	T.defined (Use.NUDGE_RISE,     "NUDGE_RISE")
	T.defined (Use.NUDGE_LIFE,     "NUDGE_LIFE")
end)

T.test ("a crate or a button is used in place; an item or a weapon is taken; anything else shows nothing", function ()
	T.eq (Use.Kind ("item_ammo_crate"), "interact", "ammo crate")
	T.eq (Use.Kind ("func_button"),     "interact", "button")
	T.eq (Use.Kind ("item_healthkit"),  "pickup",   "item")
	T.eq (Use.Kind ("weapon_smg1"),     "pickup",   "weapon")
	T.eq (Use.Kind ("prop_physics"),    nil,        "prop")
	T.eq (Use.Kind ("my_item_thing"),   nil,        "item_ only as a prefix")
end)

T.test ("doors, buttons, crates and chargers take a swipe of the hand", function ()
	local swiped = { "func_door", "prop_door_rotating", "func_button", "item_ammo_crate", "item_healthcharger" }
	for _, class in ipairs (swiped) do
		T.eq (Use.Swipes (class), true, class)
	end
	T.eq (Use.Swipes ("prop_physics"), false, "prop")
	T.eq (Use.Swipes ("weapon_smg1"),  false, "weapon")
end)

T.test ("a pickup worked when the item is gone or the weapon is the player's", function ()
	T.eq (Use.Succeeded (false, false), true,  "gone")
	T.eq (Use.Succeeded (true, true),   true,  "owned")
	T.eq (Use.Succeeded (true, false),  false, "still lying there")
end)

T.test ("a carrying player takes the magic pose in every stance it has one for", function ()
	T.eq (Carry.Activity (ACT_MP_STAND_IDLE),               ACT_HL2MP_IDLE_MAGIC, "stand")
	T.eq (Carry.Activity (ACT_MP_CROUCHWALK),               ACT_HL2MP_WALK_CROUCH_MAGIC, "crouch walk")
	T.eq (Carry.Activity (ACT_MP_SWIM_IDLE),                ACT_HL2MP_SWIM_IDLE_MAGIC, "swim idle")
	T.eq (Carry.Activity (ACT_MP_ATTACK_STAND_PRIMARYFIRE), nil, "an activity with no carry pose")
end)

T.test ("the nudge rises to full reach, falls back, and is nothing outside its life", function ()
	T.eq (Use.NudgeAmount (0), 0, "not begun")
	T.near (Use.NudgeAmount (Use.NUDGE_RISE / 2), 0.5, 1e-9, "half way out")
	T.near (Use.NudgeAmount (Use.NUDGE_RISE),     1,   1e-9, "full reach")
	local back = Use.NUDGE_RISE + (Use.NUDGE_LIFE - Use.NUDGE_RISE) / 2
	T.near (Use.NudgeAmount (back), 0.5, 1e-9, "half way back")
	T.eq (Use.NudgeAmount (Use.NUDGE_LIFE), 0, "at rest")
	T.eq (Use.NudgeAmount (-1),             0, "before it began")
end)

T.test ("neon keeps the hue at full brightness, and a colour with no hue is white", function ()
	local r, g, b = Use.Neon (0.24, 0.34, 0.41)
	T.eq (math.max (r, g, b),                   1,    "brightest channel full")
	T.eq (r < g and g < b,                      true, "channel order kept")
	T.eq (select (1, Use.Neon (0.5, 0.5, 0.5)), 1,    "grey is white")
	local wr, wg, wb = Use.Neon (0, 0, 0)
	T.eq (wr + wg + wb, 3, "black is white")
end)

T.test ("a halo's colour is 0..255, and a dark one is lifted to the floor, keeping its hue", function ()
	local floor = Use.MIN_BRIGHTNESS
	local c = Use.ToColor (1, 0.5, 0)
	T.eq (c.r, 255, "red")
	T.eq (c.g, 128, "green")
	T.eq (c.b, 0,   "blue")
	local dark = Use.ToColor (0.1, 0.05, 0)
	T.eq (dark.r, floor,                        "brightest lifted to the floor")
	T.eq (dark.g, math.floor (floor / 2 + 0.5), "others scaled with it")
	local black = Use.ToColor (0, 0, 0)
	T.eq (black.r == floor and black.g == floor and black.b == floor, true, "black is grey")
end)

T.test ("one player announces at most once a cooldown", function ()
	T.eq (Use.Ready (10, nil),    true,  "never announced")
	T.eq (Use.Ready (10, 10.5),   false, "too soon")
	T.eq (Use.Ready (10.5, 10.5), true,  "cooldown spent")
end)

T.test ("the carry arms show in first person only, while carrying", function ()
	T.eq (Carry.ShowArms (true, false),  true,  "carrying, first person")
	T.eq (Carry.ShowArms (true, true),   false, "third person")
	T.eq (Carry.ShowArms (false, false), false, "not carrying")
end)

T.test ("what comes into view starts fast and slows to a stop; what leaves starts slow and speeds away", function ()
	T.eq (Carry.EaseOut (0, 1),          0,    "in: start")
	T.eq (Carry.EaseOut (0.1, 1) > 0.25, true, "in: fast out of the start")
	T.eq (Carry.EaseOut (0.9, 1) > 0.99, true, "in: slow into the end")
	T.eq (Carry.EaseIn (0.1, 1) < 0.05,  true, "out: slow out of the start")
	T.eq (Carry.EaseIn (0.9, 1) < 0.9,   true, "out: fastest at the end")
	for _, ease in ipairs ({ Carry.EaseOut, Carry.EaseIn }) do
		T.eq (ease (2, 1),  1, "held")
		T.eq (ease (-1, 1), 0, "not begun")
	end
end)

-- Every moment of a move, in steps of a millisecond.
local function Moments (span)
	local step, age = 0.001, -0.001
	return function ()
		age = age + step
		if age <= span + step then return age end
	end
end

T.test ("taken up: the weapon leaves before the arm comes, so the two are never in view at once", function ()
	T.defined (Carry.WEAPON_DROP, "WEAPON_DROP")
	T.defined (Carry.ARMS_RISE,   "ARMS_RISE")
	for age in Moments (Carry.WEAPON_DROP + Carry.ARMS_RISE) do
		local weaponDown, armUp = Carry.TakeUp (age)
		if armUp > 0 then T.eq (weaponDown, 1, "the weapon is gone when the arm shows, at " .. age) end
	end
	T.eq (select (2, Carry.TakeUp (Carry.WEAPON_DROP + Carry.ARMS_RISE)), 1, "the arm up in the end")
end)

T.test ("let go: the arm leaves before the weapon comes back, and the release lasts both", function ()
	T.defined (Carry.ARMS_FALL,   "ARMS_FALL")
	T.defined (Carry.WEAPON_RISE, "WEAPON_RISE")
	T.eq (Release.Duration, Carry.ARMS_FALL + Carry.WEAPON_RISE, "the release's Duration")
	for age in Moments (Release.Duration) do
		local armDown, weaponUp = Carry.LetGo (age)
		if weaponUp > 0 then T.eq (armDown, 1, "the arm is gone when the weapon shows, at " .. age) end
	end
	T.eq (select (2, Carry.LetGo (Release.Duration)), 1, "the weapon up in the end")
end)

T.test ("a thrown object trails a narrowing tube of its thrower's colour, for a moment", function ()
	local Throw = registered.player_throw
	T.defined (Throw.Duration, "Duration")
	T.eq (Throw.TRAIL_MATERIAL, "trails/tube.vmt", "the tube")
	T.defined (Throw.TRAIL_START_WIDTH, "TRAIL_START_WIDTH")
	T.defined (Throw.TRAIL_LIFETIME,    "TRAIL_LIFETIME")
	T.defined (Throw.TRAIL_RESOLUTION,  "TRAIL_RESOLUTION")
	T.eq (Throw.TRAIL_END_WIDTH, 0,   "narrowing to nothing")
	T.eq (Carry.TRAIL_MATERIAL,  nil, "a carried object has its halo alone")
end)

T.test ("a used button or door glows stronger than a taken item's ghost", function ()
	T.defined (Use.INTERACT_BLUR,   "INTERACT_BLUR")
	T.defined (Use.INTERACT_PASSES, "INTERACT_PASSES")
	T.defined (Use.GHOST_BLUR,      "GHOST_BLUR")
	T.eq (Use.INTERACT_BLUR > Use.GHOST_BLUR, true, "wider")
	T.eq (Use.INTERACT_PASSES > Use.PASSES,   true, "brighter")
end)

T.finish ()
