-- The gesture of pain: a hit's grunt or cry and flinch (Sandcastle's base gamemode).
local T = dofile ("tests/harness.lua")

-- GMod's hit groups, pinned; its flinches, which the file reads as it loads, as distinct numbers.
HITGROUP_GENERIC, HITGROUP_HEAD, HITGROUP_CHEST, HITGROUP_STOMACH = 0, 1, 2, 3
HITGROUP_LEFTARM, HITGROUP_RIGHTARM, HITGROUP_LEFTLEG, HITGROUP_RIGHTLEG, HITGROUP_GEAR = 4, 5, 6, 7, 10
local FLINCHES =
{
	"ACT_FLINCH_HEAD", "ACT_FLINCH_STOMACH", "ACT_FLINCH_SHOULDER_LEFT", "ACT_FLINCH_SHOULDER_RIGHT", "ACT_FLINCH_BACK",
	"ACT_FLINCH_PHYSICS"
}
for index, name in ipairs (FLINCHES) do _G [name] = 9100 + index end

-- Loaded as shared.lua loads it, in neither realm: the rules, on the classes it registers.
local registered = {}
local chunk      = assert (loadfile ("addons/sandcastle/gamemodes/sandcastle/gamemode/gestures/player_pain.lua"))
local gesture    = { Register = function (name, class) registered [name] = class end }
setfenv (chunk, setmetatable ({ gesture = gesture }, { __index = _G }))
chunk ()
local Pain = registered.player_pain

T.test ("the tuning is defined", function ()
	T.defined (Pain.PAIN_SHARE, "PAIN_SHARE")
	T.defined (Pain.COOLDOWN,   "COOLDOWN")
	T.defined (Pain.Duration,   "Duration")
	T.defined (Pain.LEVEL,      "LEVEL")
	T.eq (#Pain.DEFAULT.grunt > 0, true, "DEFAULT is a voice")
end)

T.test ("a model speaks in its voice, and one of none in no voice", function ()
	T.eq (Pain.For ("models/player/Group01/male_07.mdl").name,   "male",     "a citizen, case aside")
	T.eq (Pain.For ("models/player/group03/female_02.mdl").name, "female",   "a rebel")
	T.eq (Pain.For ("models/player/alyx.mdl").name,              "alyx",     "Alyx")
	T.eq (Pain.For ("models/player/combine_soldier.mdl").name,   "combine",  "a Combine soldier")
	T.eq (Pain.For ("models/player/police.mdl").name,            "metrocop", "a metrocop")
	T.eq (Pain.For ("models/player/kleiner.mdl"),                nil,        "no voice")
end)

T.test ("every voice has grunts, cries and deaths", function ()
	for _, voice in ipairs (Pain.VOICES) do
		T.eq (#voice.grunt > 0 and #voice.pain > 0 and #voice.death > 0, true, voice.name)
	end
end)

T.test ("a heavy hit is a cry, a light one a grunt", function ()
	T.eq (Pain.Feedback (100 * Pain.PAIN_SHARE, 100),     "pain",  "at the share")
	T.eq (Pain.Feedback (100 * Pain.PAIN_SHARE - 1, 100), "grunt", "under it")
end)

T.test ("a hit speaks when the cooldown is spent, the player lives and it did damage", function ()
	T.eq (Pain.Speaks (10, nil, 50, 10), true,  "never spoken")
	T.eq (Pain.Speaks (10, 11, 50, 10),  false, "cooling down")
	T.eq (Pain.Speaks (10, 10, 0, 10),   false, "a death has its own sound")
	T.eq (Pain.Speaks (10, 10, 50, 0),   false, "no damage")
end)

T.test ("a hit flinches the part it struck; from behind, the back", function ()
	T.eq (Pain.Flinch (HITGROUP_HEAD, false),     ACT_FLINCH_HEAD,           "head")
	T.eq (Pain.Flinch (HITGROUP_CHEST, false),    ACT_FLINCH_STOMACH,        "chest")
	T.eq (Pain.Flinch (HITGROUP_STOMACH, false),  ACT_FLINCH_STOMACH,        "stomach")
	T.eq (Pain.Flinch (HITGROUP_LEFTARM, false),  ACT_FLINCH_SHOULDER_LEFT,  "left arm")
	T.eq (Pain.Flinch (HITGROUP_RIGHTARM, false), ACT_FLINCH_SHOULDER_RIGHT, "right arm")
	T.eq (Pain.Flinch (HITGROUP_LEFTLEG, false),  ACT_FLINCH_PHYSICS,        "a leg")
	T.eq (Pain.Flinch (HITGROUP_GENERIC, false),  ACT_FLINCH_PHYSICS,        "no part: a blast or a fall")
	T.eq (Pain.Flinch (HITGROUP_HEAD, true),      ACT_FLINCH_BACK,           "from behind")
end)

T.test ("a hit is from behind when its attacker is behind the player's facing", function ()
	local forward = { x = 1, y = 0 }
	T.eq (Pain.Behind (forward, { x = -5, y = 1 }), true,  "behind")
	T.eq (Pain.Behind (forward, { x = 5, y = 1 }),  false, "ahead")
	T.eq (Pain.Behind (forward, { x = 0, y = 5 }),  false, "beside")
end)

T.finish ()
