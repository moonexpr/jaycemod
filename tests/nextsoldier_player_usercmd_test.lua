-- nextsoldier.player.usercmd: the user command a CLuaNextBotPlayer is given,
-- a player's keys as a value: parsed once from a table, refused whole when
-- any field is not one, and written onto the engine's CUserCmd.
local T = dofile ("tests/harness.lua")
local Usercmd = nextsoldier.player.usercmd

local function Refused (fields)
	local ok, err = pcall (Usercmd.New, fields)
	return not ok and tostring (err) or nil
end

T.test ("a command from nothing presses nothing, moves nowhere and keeps the eyes where they are", function ()
	local cmd = Usercmd.New ({})
	T.eq (cmd.buttons, 0,   "buttons")
	T.eq (cmd.forward, 0,   "forward")
	T.eq (cmd.side,    0,   "side")
	T.eq (cmd.up,      0,   "up")
	T.eq (cmd.impulse, 0,   "impulse")
	T.eq (cmd.pitch,   nil, "pitch kept")
	T.eq (cmd.yaw,     nil, "yaw kept")
	T.eq (cmd.weapon,  nil, "weapon kept")
end)

T.test ("buttons are Source's IN_ bits, by name or as a mask", function ()
	T.eq (Usercmd.BUTTONS.attack,                                   1,     "IN_ATTACK")
	T.eq (Usercmd.BUTTONS.jump,                                     2,     "IN_JUMP")
	T.eq (Usercmd.BUTTONS.duck,                                     4,     "IN_DUCK")
	T.eq (Usercmd.BUTTONS.use,                                      32,    "IN_USE")
	T.eq (Usercmd.BUTTONS.attack2,                                  2048,  "IN_ATTACK2")
	T.eq (Usercmd.BUTTONS.reload,                                   8192,  "IN_RELOAD")
	T.eq (Usercmd.New ({ buttons = { "attack", "duck" } }).buttons, 5,     "names")
	T.eq (Usercmd.New ({ buttons = 6 }).buttons,                    6,     "a mask")
	T.eq (Usercmd.Has (5, "duck"),                                  true,  "pressed")
	T.eq (Usercmd.Has (5, "jump"),                                  false, "not pressed")
end)

T.test ("a command takes its eyes and moves as given", function ()
	local cmd = Usercmd.New ({ forward = 200, side = -50, up = 10, pitch = 15, yaw = 90, roll = 0, impulse = 100, weapon = "weapon_pistol" })
	T.eq (cmd.forward, 200,             "forward")
	T.eq (cmd.side,    -50,             "side")
	T.eq (cmd.up,      10,              "up")
	T.eq (cmd.pitch,   15,              "pitch")
	T.eq (cmd.yaw,     90,              "yaw")
	T.eq (cmd.impulse, 100,             "impulse")
	T.eq (cmd.weapon,  "weapon_pistol", "weapon")
end)

T.test ("a field that is not one refuses the whole command, naming it", function ()
	T.eq (Refused ({ fowrard = 1 }) ~= nil,                                   true, "an unknown field")
	T.eq ((Refused ({ fowrard = 1 }) or ""):find ("fowrard", 1, true) ~= nil, true, "named")
	T.eq (Refused ({ forward = "fast" }) ~= nil,                              true, "a move not a number")
	T.eq (Refused ({ buttons = { "attack", "fly" } }) ~= nil,                 true, "an unknown button")
	T.eq (Refused ({ buttons = -1 }) ~= nil,                                  true, "a negative mask")
	T.eq (Refused ({ buttons = 1.5 }) ~= nil,                                 true, "a mask not whole")
	T.eq (Refused ({ impulse = 256 }) ~= nil,                                 true, "an impulse past a byte")
	T.eq (Refused ({ yaw = 0 / 0 }) ~= nil,                                   true, "an angle not a number")
	T.eq (Refused ({ weapon = 3 }) ~= nil,                                    true, "a weapon not a class name")
	T.eq (Refused ({ pitch = 10 }) ~= nil,                                    true, "a pitch without a yaw")
end)

T.test ("a command is a value: it refuses to be changed", function ()
	local cmd = Usercmd.New ({ forward = 1 })
	T.eq (pcall (function () cmd.forward = 2 end), false, "an existing field")
	T.eq (pcall (function () cmd.jump = true end), false, "a new one")
	T.eq (cmd.forward,                             1,     "unchanged")
end)

T.test ("held buttons join a command's own", function ()
	local cmd = Usercmd.With (Usercmd.New ({ buttons = { "attack" }, forward = 5 }), Usercmd.Buttons ({ "duck" }), 7)
	T.eq (cmd.buttons,                        5, "attack and duck")
	T.eq (cmd.forward,                        5, "the rest kept")
	T.eq (cmd.impulse,                        7, "the impulse given")
	T.eq (Usercmd.With (cmd, 0, nil).impulse, 7, "no impulse keeps its own")
end)

T.test ("steering moves toward a way whichever way the eyes look", function ()
	local forward, side = Usercmd.Steer (0, 0, 100)
	T.near (forward, 100, 1e-6, "ahead: forward")
	T.near (side,    0,   1e-6, "ahead: no side")
	forward, side = Usercmd.Steer (0, 90, 100)
	T.near (forward, 0,    1e-6, "to the left: no forward")
	T.near (side,    -100, 1e-6, "to the left: Source's side move is negative")
	forward, side = Usercmd.Steer (90, 270, 100)
	T.near (forward, -100, 1e-6, "behind: back")
end)

T.test ("the angles from an eye to a point are Source's: yaw from +x, pitch down", function ()
	local pitch, yaw = Usercmd.AnglesTo ({ x = 0, y = 0, z = 0 }, { x = 0, y = 100, z = 0 })
	T.near (pitch, 0,  1e-6, "level")
	T.near (yaw,   90, 1e-6, "+y")
	pitch = Usercmd.AnglesTo ({ x = 0, y = 0, z = 100 }, { x = 100, y = 0, z = 0 })
	T.near (pitch, 45, 1e-6, "below is positive")
end)

-- A CUserCmd as the engine hands StartCommand one, recording what is set.
local function FakeCUserCmd ()
	local set = { cleared = {} }
	local cmd = {}
	function cmd:ClearMovement () set.cleared.movement = true end
	function cmd:ClearButtons () set.cleared.buttons = true end
	function cmd:SetButtons (b) set.buttons = b end
	function cmd:SetForwardMove (v) set.forward = v end
	function cmd:SetSideMove (v) set.side = v end
	function cmd:SetUpMove (v) set.up = v end
	function cmd:SetImpulse (v) set.impulse = v end
	function cmd:SetViewAngles (a) set.angles = a end
	return cmd, set
end

local function Angle (p, y, r) return { p = p, y = y, r = r } end

T.test ("applied, a command replaces what the engine's held, and sets the eyes only when it has them", function ()
	local target, set = FakeCUserCmd ()
	Usercmd.Apply (Usercmd.New ({ buttons = { "jump" }, forward = 3, side = 4, up = 5, impulse = 9 }), target, Angle)
	T.eq (set.cleared.movement, true, "movement cleared")
	T.eq (set.cleared.buttons,  true, "buttons cleared")
	T.eq (set.buttons,          2,    "buttons")
	T.eq (set.forward,          3,    "forward")
	T.eq (set.side,             4,    "side")
	T.eq (set.up,               5,    "up")
	T.eq (set.impulse,          9,    "impulse")
	T.eq (set.angles,           nil,  "eyes kept")
	Usercmd.Apply (Usercmd.New ({ pitch = 10, yaw = 20 }), target, Angle)
	T.eq (set.angles.p, 10, "pitch")
	T.eq (set.angles.y, 20, "yaw")
	T.eq (set.angles.r, 0,  "no roll given: level")
end)

T.finish ()
