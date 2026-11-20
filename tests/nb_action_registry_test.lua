-- action_registry: actions registered by name, each reading through to its base; a class
-- waits for a base registered after it; a reload refills a name in place; and a second class
-- claiming a registered name, from another file or another base, is refused. The AI war's top
-- monitor once took "NextSoldier", base_nextsoldier's root, and the refill put it under every
-- soldier; its Idle and Travel took the pathfollower bench's.
local T = dofile ("tests/harness.lua")
require ("action_registry")
local Registry = action_registry

T.test ("a class reads through to its base and knows its name", function ()
	local Walk = Registry.Register ("Walk", {})
	function Walk:Pace () return 1 end
	local Run = Registry.Register ("Run", {}, "Walk")
	T.eq (Registry.Get ("Run"):Pace (), 1)
	T.eq (type (Registry.New ("Run").Continue), "function", "the root's results")
	T.eq (Registry.New ("Run").name, "Run")
	T.eq (Registry.BaseOf ("Run"),   "Walk")
	T.eq (Registry.BaseOf ("Walk"),  "Action")
end)

T.test ("a class waits for a base registered after it", function ()
	Registry.Register ("Sprint", {}, "Dash")
	T.eq (Registry.Exists ("Sprint"), false)
	T.eq (Registry.Pending ().Sprint, "Dash")
	Registry.Register ("Dash", { Fast = function () return true end })
	T.eq (Registry.Exists ("Sprint"),      true)
	T.eq (Registry.New ("Sprint"):Fast (), true)
end)

T.test ("a reload refills the name in place, its derived classes reading the new one", function ()
	local Old = Registry.Register ("Patrol", { Leg = function () return "old" end })
	local Derived = Registry.Register ("NightPatrol", {}, "Patrol")
	local New = Registry.Register ("Patrol", { Leg = function () return "new" end })
	T.eq (New == Old, true, "the one table the name keeps")
	T.eq (Registry.New ("NightPatrol"):Leg (),     "new")
	T.eq (Derived == Registry.Get ("NightPatrol"), true)
end)

T.test ("a second class claiming a name from another base is refused, the first left as it is", function ()
	Registry.Register ("NextBot2", {})
	local OWNER = "base_nextsoldier/init.lua"
	local Root = Registry.Register ("NextSoldier", { Root = function () return true end }, "NextBot2", OWNER)
	local ok, why = pcall (Registry.Register, "NextSoldier", { Monitor = true }, nil, OWNER)
	T.eq (ok, false)
	T.eq (tostring (why):find ("deriving from NextBot2, not Action", 1, true) ~= nil, true, tostring (why))
	T.eq (Registry.Get ("NextSoldier") == Root, true)
	T.eq (Registry.New ("NextSoldier"):Root (), true, "its hooks kept")
	T.eq (Registry.BaseOf ("NextSoldier"), "NextBot2")
end)

T.test ("a name is its file's: another file claiming it, even from the same base, is refused", function ()
	local Mine = Registry.Register ("Idle", { Mine = function () return true end }, nil, "pathfollower.lua")
	local ok, why = pcall (Registry.Register, "Idle", { Theirs = true }, nil, "ns_behaviors.lua")
	T.eq (ok, false)
	T.eq (tostring (why):find ("Idle is pathfollower.lua's, not ns_behaviors.lua's", 1, true) ~= nil, true, tostring (why))
	T.eq (Registry.New ("Idle"):Mine (), true, "the first kept")
	T.eq (Registry.Register ("Idle", { Again = true }, nil, "pathfollower.lua") == Mine, true, "its own file again: a reload")
end)

T.finish ()
