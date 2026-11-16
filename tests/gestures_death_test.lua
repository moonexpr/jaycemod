-- The gesture of death: a player's death scream, and a crit's canned death (Sandcastle's base gamemode).
local T = dofile ("tests/harness.lua")

-- Loaded as shared.lua loads it, in neither realm: the rules, on the classes it registers.
local registered = {}
local chunk      = assert (loadfile ("addons/sandcastle/gamemodes/sandcastle/gamemode/gestures/death.lua"))
local gesture    = { Register = function (name, class) registered [name] = class end }
setfenv (chunk, setmetatable ({ gesture = gesture }, { __index = _G }))
chunk ()
local Death = registered.player_death

T.test ("the tuning is defined", function ()
	T.defined (Death.LEVEL,      "LEVEL")
	T.defined (Death.BODY_LIFE,  "BODY_LIFE")
	T.defined (Death.MAX_BODIES, "MAX_BODIES")
end)

T.test ("a crit's death is one of the player model's deaths, drawn by the caller; any other is none", function ()
	local drawn = {}
	for index = 1, #Death.DEATHS do
		drawn [index] = Death.Canned (true, function (low, high)
			T.eq (low == 1 and high == #Death.DEATHS, true, "draws from the list")

			return index
		end)
	end
	T.eq (table.concat (drawn, " "),                      table.concat (Death.DEATHS, " "), "each death drawable")
	T.eq (Death.Canned (false, function () return 1 end), nil,                              "not a crit")
end)

T.test ("a body is canned only when it leaves one", function ()
	T.eq (Death.LeavesBody (false, false), true,  "a plain death")
	T.eq (Death.LeavesBody (true, false),  false, "dissolving")
	T.eq (Death.LeavesBody (false, true),  false, "no ragdoll asked")
end)

T.test ("a canned body's cycle runs 0..1 over its length and holds at the end", function ()
	T.eq (Death.Cycle (0, 2), 0,   "start")
	T.eq (Death.Cycle (1, 2), 0.5, "half")
	T.eq (Death.Cycle (3, 2), 1,   "held")
end)

T.finish ()
