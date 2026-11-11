-- model_viewer_catalog (addons/model_viewer): what the viewer shows of a model
-- and how it plays, apart from any panel.
local T = dofile ("tests/harness.lua")
local Catalog = T.require ("model_viewer_catalog")

-- A model's sequences, as an entity answers for them: { name, act, seconds }s,
-- numbered from 0 as the engine numbers them; poses { name, min, max }s.
local function Model (sequences, poses)
	local ent = {}
	function ent:GetSequenceCount () return #sequences end
	function ent:GetSequenceName (i) return sequences [i + 1] [1] end
	function ent:GetSequenceActivityName (i) return sequences [i + 1] [2] end
	function ent:SequenceDuration (i) return sequences [i + 1] [3] end
	function ent:GetNumPoseParameters () return #(poses or {}) end
	function ent:GetPoseParameterName (i) return poses [i + 1] [1] end
	function ent:GetPoseParameterRange (i) return poses [i + 1] [2], poses [i + 1] [3] end
	return ent
end

-- Paths ----------------------------------------------------------------------

T.test ("a model's path is read as the engine names it", function ()
	T.eq (Catalog.ModelPath ("models/player/scout.mdl"), "models/player/scout.mdl", "already plain")
	T.eq (Catalog.ModelPath ("Models\\Player\\Scout.MDL"), "models/player/scout.mdl", "case and slashes")
	T.eq (Catalog.ModelPath ("player/scout"), "models/player/scout.mdl", "the folder and the extension left out")
	T.eq (Catalog.ModelPath ('  "models/player/scout.mdl" '), "models/player/scout.mdl", "spaces and quotes around it")
end)

T.test ("nothing is no path", function ()
	T.eq (Catalog.ModelPath (""), nil, "empty")
	T.eq (Catalog.ModelPath ('  "" '), nil, "only spaces and quotes")
end)

-- Sequences --------------------------------------------------------------------

T.test ("sequences come by act, those with no act last, each act's in the model's order", function ()
	local entries = Catalog.Sequences (Model (
		{
			{ "ref", "", 0.1 },
			{ "run_b", "ACT_RUN", 0.8 },
			{ "jump", "ACT_JUMP", 0.5 },
			{ "run_a", "ACT_RUN", 0.7 },
			{ "pose", "", 0.2 }
		}
	))
	T.eq (#entries, 5, "every sequence")
	local order = {}
	for i, entry in ipairs (entries) do order [i] = entry.name end
	T.eq (table.concat (order, " "), "jump run_b run_a ref pose", "the order")
	T.eq (entries [1].sequence, 2, "an entry keeps the engine's number")
	T.eq (entries [1].act, "ACT_JUMP", "its act")
	T.eq (entries [1].seconds, 0.5, "its length")
end)

T.test ("a model with no sequences has an empty list", function ()
	T.eq (#Catalog.Sequences (Model ({})), 0, "none")
end)

T.test ("a search keeps what has all its words, in the act or the name, whatever the case", function ()
	local entries = Catalog.Sequences (Model (
		{
			{ "jumpstart", "ACT_MP_JUMP_START_PRIMARY", 1 },
			{ "jumpfloat", "ACT_MP_JUMP_FLOAT_PRIMARY", 1 },
			{ "idle", "ACT_MP_STAND_PRIMARY", 1 },
			{ "start_cheer", "", 1 }
		}
	))
	T.eq (#Catalog.Matching (entries, ""), 4, "no words keep all")
	T.eq (#Catalog.Matching (entries, "   "), 4, "spaces are no words")
	T.eq (#Catalog.Matching (entries, "JUMP"), 2, "case-free, in the act")
	T.eq (#Catalog.Matching (entries, "cheer"), 1, "in the name")
	T.eq (#Catalog.Matching (entries, "start"), 2, "in either")
	T.eq (Catalog.Matching (entries, "jump start") [1].name, "jumpstart", "every word")
	T.eq (#Catalog.Matching (entries, "jump start"), 1, "only those with every word")
	T.eq (#Catalog.Matching (entries, "act_(mp"), 0, "a search is text, not a pattern")
end)

T.test ("stepping through a list wraps at its ends", function ()
	T.eq (Catalog.Step (3, 1, 1), 2, "the next")
	T.eq (Catalog.Step (3, 3, 1), 1, "past the last, the first")
	T.eq (Catalog.Step (3, 1, -1), 3, "before the first, the last")
end)

T.test ("stepping starts from an end when nothing is chosen, and an empty list has no step", function ()
	T.eq (Catalog.Step (3, nil, 1), 1, "forward, the first")
	T.eq (Catalog.Step (3, nil, -1), 3, "back, the last")
	T.eq (Catalog.Step (0, nil, 1), nil, "nothing to step to")
end)

-- Playing ----------------------------------------------------------------------

T.test ("the cycle runs through a sequence at its rate", function ()
	T.near (Catalog.Advance (0, 1, 4, 1, true), 0.25, 1e-9, "a quarter of its length")
	T.near (Catalog.Advance (0, 1, 4, 2, true), 0.5, 1e-9, "twice as fast")
end)

T.test ("a looped sequence wraps, however long the gap", function ()
	T.near (Catalog.Advance (0.9, 1, 5, 1, true), 0.1, 1e-9, "past the end")
	T.near (Catalog.Advance (0, 11, 2, 1, true), 0.5, 1e-9, "several times round")
end)

T.test ("an unlooped sequence holds its last frame", function ()
	T.eq (Catalog.Advance (0.9, 1, 5, 1, false), 1, "stops at the end")
	T.eq (Catalog.Advance (1, 1, 5, 1, false), 1, "and stays")
end)

T.test ("a sequence with no length stays where it is", function ()
	T.eq (Catalog.Advance (0, 1, 0, 1, true), 0, "looped")
	T.eq (Catalog.Advance (0, 1, 0, 1, false), 0, "unlooped")
end)

T.test ("poses start at rest, in their range, with a walker's legs walking forward", function ()
	local poses = Catalog.Poses (Model ({},
		{
			{ "body_yaw", -45, 45 },
			{ "move_x", -1, 1 },
			{ "move_y", -1, 1 },
			{ "raise", 10, 90 },
			{ "lower", -90, -10 }
		}
	))
	local value = {}
	for _, pose in ipairs (poses) do value [pose.name] = pose.value end
	T.eq (#poses, 5, "every pose")
	T.eq (poses [1].min, -45, "its range")
	T.eq (poses [1].max, 45, "its range")
	T.eq (value.body_yaw, 0, "rest")
	T.eq (value.move_x, 1, "walking forward, so a run's blend shows a run")
	T.eq (value.move_y, 0, "not to the side")
	T.eq (value.raise, 10, "rest held to a range above it")
	T.eq (value.lower, -10, "rest held to a range below it")
end)

T.test ("a walker's forward pose is held to its range", function ()
	local poses = Catalog.Poses (Model ({}, { { "move_x", 0, 0.5 } }))
	T.eq (poses [1].value, 0.5, "the range's top")
end)

-- The camera --------------------------------------------------------------------

T.test ("the camera looks at the middle of a model, far enough to fit it", function ()
	local center, distance = Catalog.Framing ({ x = -10, y = -10, z = 0 }, { x = 10, y = 10, z = 80 }, 40)
	T.eq (center.x, 0, "x")
	T.eq (center.y, 0, "y")
	T.eq (center.z, 40, "halfway up")
	local radius = math.sqrt (10 * 10 + 10 * 10 + 40 * 40)
	T.near (math.sin (math.rad (20)) * distance, radius, 1e-6, "the bounds' sphere touches the view's edge")
end)

T.test ("a model with no size still has the camera some way off", function ()
	local _, distance = Catalog.Framing ({ x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = 0 }, 40)
	T.eq (distance > 0, true, "not on top of it")
end)

T.test ("the camera orbits its centre at its distance", function ()
	local center = { x = 1, y = 2, z = 3 }
	local x, y, z = Catalog.Orbit (center, 10, 0, 0)
	T.near (x, 11, 1e-9, "yaw 0 is in front of the model, along +x")
	T.near (y, 2, 1e-9, "y")
	T.near (z, 3, 1e-9, "z")
	x, y = Catalog.Orbit (center, 10, 90, 0)
	T.near (x, 1, 1e-9, "a quarter turn")
	T.near (y, 12, 1e-9, "a quarter turn")
	x, _, z = Catalog.Orbit (center, 10, 0, 90)
	T.near (x, 1, 1e-9, "straight above")
	T.near (z, 13, 1e-9, "straight above")
end)

T.test ("orbiting stops short of the poles, where a view has no up", function ()
	T.eq (Catalog.Pitch (0, 200) < 90, true, "above")
	T.eq (Catalog.Pitch (0, -200) > -90, true, "below")
	T.eq (Catalog.Pitch (10, 5), 15, "moves freely between")
end)

T.test ("the wheel zooms in and out, within reach of the fit", function ()
	T.eq (Catalog.Zoom (100, 100, 1) < 100, true, "up is in")
	T.eq (Catalog.Zoom (100, 100, -1) > 100, true, "down is out")
	local near = 100
	local far = 100
	for _ = 1, 200 do
		near = Catalog.Zoom (near, 100, 1)
		far = Catalog.Zoom (far, 100, -1)
	end
	T.eq (near > 0, true, "never through the model")
	T.eq (near < 100, true, "but close")
	T.eq (far > 100, true, "and far")
	T.eq (far < 100000, true, "not out of sight")
end)

T.finish ()
