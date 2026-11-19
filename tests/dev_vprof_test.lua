-- The dev workbench's reading of the engine's VProf through HolyLib's vprof library
-- (sandcastle_dev_vprof), on a fake of the library: its tree flattened, merged by scope and by
-- budget group, and a scope that a function's error does not leave open.
local T = dofile ("tests/harness.lua")
local VProf = T.require ("sandcastle_dev_vprof")

-- A fake VProfNode tree from { name, group, calls, total, self, peak, children }, and the library
-- around it: frames and time sampled, budget groups by id, scopes entered and left.
local function FakeLib (frames, sampled, tree)
	local lib = { groups = {}, groupIds = {}, depth = 0, entered = {} }
	local function GroupId (name)
		if not lib.groupIds [name] then
			lib.groups [#lib.groups + 1] = name
			lib.groupIds [name] = #lib.groups
		end
		return lib.groupIds [name]
	end
	local Node = {}
	Node.__index = Node
	local function Make (spec)
		local node = setmetatable ({ spec = spec, groupId = GroupId (spec.group or "Other") }, Node)
		local previous
		for _, childSpec in ipairs (spec.children or {}) do
			local child = Make (childSpec)
			if previous then previous.sibling = child else node.child = child end
			previous = child
		end
		return node
	end
	function Node:GetName () return self.spec.name end
	function Node:GetBudgetGroupID () return self.groupId end
	function Node:GetTotalCalls () return self.spec.calls or 0 end
	function Node:GetTotalTime () return self.spec.total or 0 end
	function Node:GetTotalTimeLessChildren () return self.spec.self or 0 end
	function Node:GetPeakTime () return self.spec.peak or 0 end
	function Node:GetChild () return self.child end
	function Node:GetSibling () return self.sibling end
	local root = Make ({ name = "Root", children = tree })
	function lib.GetRoot () return root end
	function lib.GetBudgetGroupName (id) return lib.groups [id] end
	function lib.NumFramesSampled () return frames end
	function lib.GetTotalTimeSampled () return sampled end
	function lib.IsEnabled () return false end
	function lib.EnterScope (name, level, group)
		lib.depth = lib.depth + 1
		lib.entered [#lib.entered + 1] = name .. "|" .. level .. "|" .. group
	end
	function lib.ExitScope () lib.depth = lib.depth - 1 end
	return lib
end

-- 10 frames, 100 ms: a server frame holding the gamemode's Think and the NextBots
local function ServerFrame ()
	return FakeLib (10, 100,
		{
			{
				name = "ServerGameDLL_GameFrame", group = "Game", calls = 10, total = 80, self = 10, peak = 12,
				children =
				{
					{
						name = "CLuaGamemode::Call (Think)", group = "GMOD", calls = 10, total = 30, self = 20, peak = 5,
						children =
						{
							{ name = "hook Think/ws_war", group = "WSProfile", calls = 10, total = 10, self = 10, peak = 2 }
						}
					},
					{ name = "NextBot", group = "NPCs", calls = 40, total = 40, self = 40, peak = 9 }
				}
			},
			{ name = "Physics", group = "Physics", calls = 10, total = 20, self = 20, peak = 3 }
		}
	)
end

T.test ("the tree is flattened depth first, the root left out, with its depth and budget group", function ()
	local nodes, truncated = VProf.Nodes (ServerFrame ())
	local names = {}
	for i, node in ipairs (nodes) do names [i] = node.depth .. " " .. node.name .. " [" .. node.group .. "]" end
	T.eq (table.concat (names, ", "), "1 ServerGameDLL_GameFrame [Game], 2 CLuaGamemode::Call (Think) [GMOD], "
		.. "3 hook Think/ws_war [WSProfile], 2 NextBot [NPCs], 1 Physics [Physics]", "in order")
	T.eq (truncated, false, "whole")
end)

T.test ("a walk past its limit stops and says it was cut short", function ()
	local nodes, truncated = VProf.Nodes (ServerFrame (), 2)
	T.eq (#nodes,    2,    "two nodes")
	T.eq (truncated, true, "cut short")
end)

T.test ("self time by budget group sums to the time sampled, most first, per frame and as a share", function ()
	local report = VProf.Read (ServerFrame ())
	local groups = {}
	for i, row in ipairs (report.groups) do groups [i] = row.name .. "=" .. row.selfMs end
	T.eq (table.concat (groups, " "),   "NPCs=40 GMOD=20 Physics=20 Game=10 WSProfile=10", "by group")
	T.eq (report.groups [1].perFrameMs, 4, "NPCs: 4 ms a frame")
	T.eq (report.groups [1].share,      0.4, "and 40 % of the time sampled")
end)

T.test ("a scope reached from several parents is one row, its calls and times summed", function ()
	local lib = FakeLib (1, 10,
		{
			{ name = "A", group = "G", children = { { name = "S", group = "L", calls = 2, total = 3, self = 3, peak = 2 } } },
			{ name = "B", group = "G", children = { { name = "S", group = "L", calls = 1, total = 4, self = 4, peak = 4 } } }
		}
	)
	local report = VProf.Read (lib)
	local row = report.top [1]
	local summary = table.concat ({ row.name, row.calls, row.totalMs, row.selfMs, row.peakMs }, " ")
	T.eq (summary, "S 3 7 7 4", "merged")
end)

T.test ("a scope nested in itself counts its total once, its outermost's", function ()
	local lib = FakeLib (1, 10,
		{
			{
				name = "R", group = "L", calls = 1, total = 6, self = 2,
				children = { { name = "R", group = "L", calls = 1, total = 4, self = 4 } }
			}
		}
	)
	local row = VProf.Read (lib).top [1]
	T.eq (row.totalMs .. " " .. row.selfMs .. " " .. row.calls, "6 6 2", "total once, self and calls each")
end)

T.test ("the report holds the top rows only, and the flat tree when asked", function ()
	local report = VProf.Read (ServerFrame (), { rows = 2, tree = true })
	T.eq (#report.top,                       2,         "two rows")
	T.eq (report.top [1].name,               "NextBot", "the most self time first")
	T.eq (#report.nodes,                     5,         "the tree")
	T.eq (report.nodes [3].nestedIn,         nil,       "without the merge's marks")
	T.eq (VProf.Read (ServerFrame ()).nodes, nil,       "and none unless asked")
end)

T.test ("the report formats as lines: the header, the groups, the scopes", function ()
	local lines = VProf.Format (VProf.Read (ServerFrame (), { rows = 1 }))
	T.eq (lines [1], "vprof: 10 frames, 100.0 ms sampled (10.000 ms/frame)", "header")
	T.eq (#lines, 1 + 1 + 5 + 1 + 1, "five groups, one scope")
	T.eq (lines [#lines]:find ("[NPCs] NextBot", 1, true) ~= nil, true, lines [#lines])
end)

T.test ("a scoped function enters its scope on the main thread and leaves it", function ()
	local lib = FakeLib (1, 1, {})
	local f = VProf.Scoped (lib, "hook Think/x", "WSProfile", function (a, b) return a + b, "two" end)
	local sum, second = f (1, 2)
	T.eq (sum .. " " .. second, "3 two",                    "its results")
	T.eq (lib.entered [1],      "hook Think/x|0|WSProfile", "entered at detail level 0")
	T.eq (lib.depth,            0,                          "and left")
end)

T.test ("a scoped function that raises leaves its scope and raises the same error", function ()
	local lib = FakeLib (1, 1, {})
	local f = VProf.Scoped (lib, "s", "G", function () error ("broke", 0) end)
	local ok, err = pcall (f)
	T.eq (ok,        false,   "raised")
	T.eq (err,       "broke", "the same error")
	T.eq (lib.depth, 0,       "its scope left")
end)

T.test ("a scoped function called in a coroutine is left unscoped, since a yield would leave it open", function ()
	local lib = FakeLib (1, 1, {})
	local f = VProf.Scoped (lib, "s", "G", function () coroutine.yield (lib.depth) return "done" end)
	local co = coroutine.create (f)
	local _, depthWhileSuspended = coroutine.resume (co)
	T.eq (depthWhileSuspended,               0,      "no scope while it is suspended")
	T.eq (select (2, coroutine.resume (co)), "done", "and it finishes")
	T.eq (#lib.entered,                      0,      "no scope entered")
end)

T.finish ()
