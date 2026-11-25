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

-- Responders: a class declares the events every action deriving from it must answer, beyond the
-- events any action may answer (nextsoldier.behavior.EVENTS); an action that exists answers them.
local function Refused (why, text)
	return tostring (why):find (text, 1, true) ~= nil
end

T.test ("an action leaving its family's responder unanswered is refused as it is made, naming it", function ()
	local Crouch = Registry.Register ("Crouch", {})
	Registry.Responders ("Crouch", { "OnCrouchHold", "OnCrouchRelease" })
	function Crouch:OnCrouchHold () end
	Registry.Register ("Duck", {}, "Crouch")
	local ok, why = pcall (Registry.New, "Duck")
	T.eq (ok, false)
	T.eq (Refused (why, "Duck does not answer OnCrouchRelease (Crouch's)"), true, tostring (why))
	ok, why = pcall (Registry.Get ("Duck").New, Registry.Get ("Duck"))
	T.eq (ok,                                                               false, "the chart's New too")
	T.eq (Refused (why, "Duck does not answer OnCrouchRelease (Crouch's)"), true,  tostring (why))
	T.eq (Registry.Unanswered ().Duck [1], "OnCrouchRelease")
	function Crouch:OnCrouchRelease () end
	T.eq (Registry.New ("Duck").name, "Duck", "answered through its family")
	T.eq (Registry.Unanswered ().Duck, nil)
end)

T.test ("a responder answered above the family is not its answer", function ()
	Registry.Register ("Stance", { OnBrace = function () end })
	local Brace = Registry.Register ("Brace", {}, "Stance")
	Registry.Responders ("Brace", { "OnBrace" })
	T.eq (pcall (Registry.New, "Brace"), false, "Stance's OnBrace is not Brace's")
	function Brace:OnBrace () end
	Registry.Register ("Kneel", {}, "Brace")
	T.eq (Registry.New ("Kneel").name, "Kneel", "Brace's is Kneel's")
end)

T.test ("a reload taking a responder away is refused again", function ()
	Registry.Register ("Sway", { OnSway = function () end })
	Registry.Responders ("Sway", { "OnSway" })
	T.eq (Registry.New ("Sway").name, "Sway")
	Registry.Register ("Sway", {})
	T.eq (pcall (Registry.New, "Sway"), false)
	Registry.Register ("Sway", { OnSway = function () end })
end)

T.test ("responders declared after an action was made bind the next one", function ()
	Registry.Register ("Lean", {})
	T.eq (Registry.New ("Lean").name, "Lean")
	Registry.Responders ("Lean", { "OnLean" })
	T.eq (pcall (Registry.New, "Lean"), false)
	Registry.Responders ("Lean", {})
end)

T.test ("files add responders to a family; one declaring again replaces only its own", function ()
	Registry.Register ("Signal", { OnHand = function () end })
	Registry.Register ("Beckon", {}, "Signal")
	Registry.Responders ("Signal", { "OnHand" },    "hands.lua")
	Registry.Responders ("Signal", { "OnWhistle" }, "whistles.lua")
	T.eq (table.concat (Registry.Unanswered ().Beckon, ","), "OnWhistle")
	Registry.Responders ("Signal", {}, "whistles.lua")
	T.eq (Registry.Unanswered ().Beckon, nil)
	T.eq (Registry.New ("Beckon").name,  "Beckon")
end)

T.test ("Check names every action leaving a responder unanswered", function ()
	Registry.Register ("Wave", {})
	Registry.Register ("Salute", {}, "Wave")
	Registry.Responders ("Wave", { "OnWave", "OnAttention" })
	local ok, why = pcall (Registry.Check)
	T.eq (ok, false)
	T.eq (Refused (why, "Salute does not answer OnAttention, OnWave (Wave's)"), true, tostring (why))
	Registry.Responders ("Wave", {})
	T.eq (pcall (Registry.Check), true)
end)

T.test ("a query is a responder too, answered as an event is", function ()
	Registry.Register ("Peek", {})
	local Glance = Registry.Register ("Glance", {}, "Peek")
	Registry.Responders ("Peek", { "ShouldPeek", "SelectCorner" })
	T.eq (table.concat (Registry.Unanswered ().Glance, ","), "SelectCorner,ShouldPeek")
	function Glance:ShouldPeek () end
	function Glance:SelectCorner () end
	T.eq (Registry.New ("Glance").name, "Glance")
end)

T.test ("a family's base answering none of its responders is abstract: never made, never reported", function ()
	Registry.Register ("Hover", {})
	local Drift = Registry.Register ("Drift", {}, "Hover")
	Registry.Responders ("Hover", { "ShouldDrift" })
	function Drift:ShouldDrift () end
	T.eq (Registry.Unanswered ().Hover, nil,  "not reported")
	T.eq (pcall (Registry.Check),       true, "not refused at load")
	local ok, why = pcall (Registry.New, "Hover")
	T.eq (ok,                                                           false, "but never made")
	T.eq (Refused (why, "Hover does not answer ShouldDrift (Hover's)"), true,  tostring (why))
	T.eq (Registry.New ("Drift").name, "Drift")
end)

T.test ("a responder is an event's name or a query's", function ()
	Registry.Register ("Nod", {})
	T.eq (Refused (select (2, pcall (Registry.Responders, "Nod", { "Hold" })), "Hold is not an event (On...) or a query (Should..., Select...)"), true)
	T.eq (Refused (select (2, pcall (Registry.Responders, "Nod", "OnNod")), "a list of events"), true)
end)

T.test ("every loaded action answers its families' responders", function ()
	T.eq (next (Registry.Unanswered ()), nil)
end)

T.finish ()
