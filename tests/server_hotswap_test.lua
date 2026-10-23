-- The dedicated server's hotswap.lua (.devtools/bin/server_root/): code
-- edited while the server runs, loaded without a restart. A module
-- (WS.require) runs again and keeps its table, so its functions update
-- where every holder has them; a feature's root runs again, with its parts,
-- with its side effects stubbed (hooks, timers, commands, listeners, other
-- features), and only the methods named are copied onto the live
-- controller, whose state stays. A swap is all or nothing: a name missing
-- from the fresh run, a table the live controller lacks, or a method that
-- closes over the fresh controller refuses the whole swap.
local T = dofile("tests/harness.lua")
local Features = system.features

local ROOT = "sandcastle/gamemode/"

-- files: path -> source; the server's WS.require keeps GAMEMODE_ROOT
-- and CHUNK_ENV as upvalues, as sh_core's does. WS.FeatureParts runs a
-- root's parts from files, as sh_core's does from disk. The fake
-- WS.Events records every Listen and Define call.
-- Returns the commands registered, CHUNK_ENV, the count of hooks added, and
-- fake: printed (each line the console was told), listens (Listen calls),
-- listeners ("<event> <id>" -> fn), defines (Define calls).
local function Load(files, features)
	local commands, hooksAdded = {}, 0
	local fake = {
		printed = {},
		listens = 0,
		listeners = {},
		defines = 0,
	}
	local GAMEMODE_ROOT = ROOT
	local CHUNK_ENV = setmetatable({}, { __index = _G })
	local function CompileFile(path) return assert(loadstring(files[path], path)) end
	local WS = {}
	function WS.require(name)
		local _ = GAMEMODE_ROOT, CHUNK_ENV
		return package.loaded[name]
	end
	WS.Feature = function(name) return features[name] end
	local port = {}
	function port:Compile(path) return CompileFile(ROOT .. path) end
	function WS.FeatureParts(env, name) return Features.Parts(port, env, name) end
	WS.Events = {
		Listen = function(name, id, fn)
			fake.listens = fake.listens + 1
			fake.listeners[name .. " " .. id] = fn
		end,
		Ignore = function(name, id) fake.listeners[name .. " " .. id] = nil end,
		Define = function() fake.defines = fake.defines + 1 end,
	}
	local env = setmetatable({
		WS = WS,
		CompileFile = CompileFile,
		concommand = { Add = function(name, fn) commands[name] = fn end },
		hook = { Add = function() hooksAdded = hooksAdded + 1 end },
		IsValid = function(v) return v ~= nil end,
		print = function(text) fake.printed[#fake.printed + 1] = text end,
	}, { __index = _G })
	setfenv(assert(loadfile(".devtools/bin/server_root/hotswap.lua")), env)()
	return commands, CHUNK_ENV, function() return hooksAdded end, fake
end

-- Everything the console was told, one string.
local function Said(fake)
	return table.concat(fake.printed, "\n")
end

local function Contains(text, wanted)
	return text:find(wanted, 1, true) ~= nil
end

T.test("a module runs again in place: every holder of its table sees the new function", function()
	package.loaded["fake.area"] = nil
	local files = { [ROOT .. "fake/area.lua"] = "module(...) function Answer() return 1 end" }
	local commands, env = Load(files, {})
	setfenv(assert(loadstring(files[ROOT .. "fake/area.lua"])), env)("fake.area")
	local held = package.loaded["fake.area"]
	files[ROOT .. "fake/area.lua"] = "module(...) function Answer() return 2 end function Added() return 3 end"
	commands.ws_hotswap_module(nil, nil, { "fake.area" })
	T.eq(held.Answer(), 2, "the same table, the new function")
	T.eq(held.Added(), 3, "and a new one")
end)

T.test("a feature's named methods are copied onto the live controller; its state and hooks are untouched", function()
	local live = { set = "live state" }
	function live:Old() return "old" end
	function live:Kept() return "kept" end
	local files = {
		[ROOT .. "features/capture/sv.lua"] = [[
			local Controller = {}
			hook.Add("Think", "x", function() end)
			Controller.rounds = WS.Feature("rounds")
			Controller.rounds:AddTimerHold("x")
			function Controller:Old() return "new " .. self.set end
			function Controller:Kept() return "changed" end
			return Controller
		]],
	}
	local commands, _, hooks = Load(files, { capture = live, rounds = {} })
	commands.ws_hotswap_feature(nil, nil, { "capture", "Old" })
	T.eq(live:Old(), "new live state", "the new method, on the live state")
	T.eq(live:Kept(), "kept", "an unnamed method stays")
	T.eq(hooks(), 0, "no hook added again")
end)

-- A split feature: the root declares the state and a Soldier port, and runs
-- its part sv_area, which registers wiring and defines the methods.
local SPLIT_ROOT = [[
	local Controller = {
		war = nil,
		size = nil,
	}
	local Soldier = {}
	Soldier.__index = Soldier
	Controller.Soldier = Soldier
	function Soldier:Move() return "new move" end
	local Part = WS.FeatureParts(getfenv(1), "capture")
	Part("sv_area", Controller)
	return Controller
]]

local SPLIT_PART = [[
	local Controller = ...
	hook.Add("Think", "ws_area_think", function() Controller:Old() end)
	concommand.Add("ws_area_print", function() end)
	function Controller:Old() return "new " .. self.size end
	function Controller:Report() return Controller.war end
	function Controller:Size() return self.size end
	local function Busy() return Controller.war ~= nil end
	function Controller:Busy() return Busy() end
]]

local function SplitFiles(part)
	return {
		[ROOT .. "features/capture/sv.lua"] = SPLIT_ROOT,
		[ROOT .. "features/capture/sv_area.lua"] = part or SPLIT_PART,
	}
end

-- The live controller of the split feature, as the first load left it.
local function SplitLive()
	local live = {
		war = {},
		size = 3,
		Soldier = {},
	}
	live.Soldier.__index = live.Soldier
	function live.Soldier:Move() return "old move" end
	function live:Old() return "old" end
	function live:Report() return "old report" end
	function live:Size() return "old size" end
	function live:Busy() return "old busy" end
	return live
end

T.test("a swap reaches a method defined in a part, and the part's wiring is not registered again", function()
	local live = SplitLive()
	local commands, _, hooks = Load(SplitFiles(), { capture = live })
	commands.ws_hotswap_feature(nil, nil, { "capture", "Old" })
	T.eq(live:Old(), "new 3", "the part's new method, on the live state")
	T.eq(hooks(), 0, "the part's hook is not added again")
	T.eq(commands.ws_area_print, nil, "the part's command is not registered again")
end)

T.test("a Table.Method name reaches every live instance of that table", function()
	local live = SplitLive()
	local soldier = setmetatable({}, live.Soldier)
	local commands = Load(SplitFiles(), { capture = live })
	commands.ws_hotswap_feature(nil, nil, { "capture", "Soldier.Move" })
	T.eq(soldier:Move(), "new move", "the live instance sees the new method")
end)

T.test("a name missing from the fresh side refuses the whole swap and is named", function()
	local live = SplitLive()
	local commands, _, _, fake = Load(SplitFiles(), { capture = live })
	commands.ws_hotswap_feature(nil, nil, { "capture", "Old", "Typo" })
	T.eq(live:Old(), "old", "the valid name in the same call is not copied")
	T.eq(live.Typo, nil, "nothing is set under the missing name")
	T.eq(Contains(Said(fake), "Typo: missing"), true, "the caller is told the name and why")
	T.eq(Contains(Said(fake), "swapped"), false, "nothing is reported swapped")
end)

T.test("an unknown table refuses the whole swap and is named", function()
	local live = SplitLive()
	local commands, _, _, fake = Load(SplitFiles(), { capture = live })
	commands.ws_hotswap_feature(nil, nil, { "capture", "Old", "Nope.Move" })
	T.eq(live:Old(), "old", "the valid name in the same call is not copied")
	T.eq(live.Nope, nil, "no table is made for the unknown name")
	T.eq(Contains(Said(fake), "Nope.Move: not a table"), true, "the caller is told the name and why")
end)

T.test("a part's listener is not rebound: the rerun makes no Listen call and the live listener stays", function()
	local part = SPLIT_PART .. [[
		WS.Events.Listen("x", "ws_x", function() return Controller end)
	]]
	local live = SplitLive()
	local commands, _, _, fake = Load(SplitFiles(part), { capture = live })
	local original = function() end
	fake.listeners["x ws_x"] = original
	commands.ws_hotswap_feature(nil, nil, { "capture", "Old" })
	T.eq(fake.listens, 0, "no Listen call during the rerun")
	T.eq(fake.listeners["x ws_x"], original, "the live listener is the original")
	T.eq(live:Old(), "new 3", "the swap still happened")
end)

T.test("a load-time alias of WS.Events is stubbed too, and Define still reaches the real Events", function()
	local part = SPLIT_PART .. [[
		local E = WS.Events
		E.Define("x", {})
		E.Listen("x", "ws_x", function() return Controller end)
		E.Ignore("y", "ws_y")
	]]
	local live = SplitLive()
	local commands, _, _, fake = Load(SplitFiles(part), { capture = live })
	local original, other = function() end, function() end
	fake.listeners["x ws_x"] = original
	fake.listeners["y ws_y"] = other
	commands.ws_hotswap_feature(nil, nil, { "capture", "Old" })
	T.eq(fake.listens, 0, "no Listen call during the rerun")
	T.eq(fake.listeners["x ws_x"], original, "the live listener is the original")
	T.eq(fake.listeners["y ws_y"], other, "Ignore removed nothing")
	T.eq(fake.defines, 1, "Define reached the real Events")
end)

T.test("a method that reads only self swaps onto the live state", function()
	local live = SplitLive()
	local commands = Load(SplitFiles(), { capture = live })
	commands.ws_hotswap_feature(nil, nil, { "capture", "Size" })
	T.eq(live:Size(), 3, "the new method reads the live size")
end)

T.test("a method that closes over the fresh controller is refused", function()
	local live = SplitLive()
	local commands, _, _, fake = Load(SplitFiles(), { capture = live })
	commands.ws_hotswap_feature(nil, nil, { "capture", "Report" })
	T.eq(live:Report(), "old report", "the live method stays")
	T.eq(Contains(Said(fake), "Report: closes over the controller through Controller"), true, "the caller is told the name and the upvalue")
end)

T.test("a method that reaches the fresh controller through a local helper is refused", function()
	local live = SplitLive()
	local commands, _, _, fake = Load(SplitFiles(), { capture = live })
	commands.ws_hotswap_feature(nil, nil, { "capture", "Busy" })
	T.eq(live:Busy(), "old busy", "the live method stays")
	T.eq(Contains(Said(fake), "Busy: closes over the controller through Busy > Controller"), true, "the caller is told the path")
end)

T.test("a refused method refuses the whole swap: a safe name in the same call is not copied", function()
	local live = SplitLive()
	local commands, _, _, fake = Load(SplitFiles(), { capture = live })
	commands.ws_hotswap_feature(nil, nil, { "capture", "Size", "Report" })
	T.eq(live:Size(), "old size", "the old Size stays")
	T.eq(live:Report(), "old report", "the old Report stays")
	T.eq(Contains(Said(fake), "Report: closes over the controller"), true, "the refused name is named")
end)

T.test("a port method that closes over the fresh port table is refused", function()
	local root = SPLIT_ROOT:gsub("local Part =", "function Soldier.New() return setmetatable({}, Soldier) end\n\tlocal Part =")
	local files = SplitFiles()
	files[ROOT .. "features/capture/sv.lua"] = root
	local live = SplitLive()
	local old = function() return "old new" end
	live.Soldier.New = old
	local commands, _, _, fake = Load(files, { capture = live })
	commands.ws_hotswap_feature(nil, nil, { "capture", "Soldier.New" })
	T.eq(live.Soldier.New, old, "the live constructor stays")
	T.eq(Contains(Said(fake), "Soldier.New: closes over the controller through Soldier"), true, "the caller is told the name and the upvalue")
end)

T.test("naming no methods lists the swappable and the refused ones and copies nothing", function()
	local live = SplitLive()
	local before = {}
	for key, value in pairs(live) do before[key] = value end
	local soldierMove = live.Soldier.Move
	local commands, _, hooks, fake = Load(SplitFiles(), { capture = live })
	commands.ws_hotswap_feature(nil, nil, { "capture" })
	for key, value in pairs(before) do T.eq(live[key], value, "live " .. key .. " unchanged") end
	for key in pairs(live) do T.eq(before[key] ~= nil, true, "no field added: " .. key) end
	T.eq(live.Soldier.Move, soldierMove, "live Soldier.Move unchanged")
	T.eq(hooks(), 0, "no hook added")
	local said = Said(fake)
	-- one name a line: the console cuts a long line short
	T.eq(Contains(said, "swappable:\n  Old\n  Size\n  Soldier.Move\n"), true, "the swappable list: " .. said)
	T.eq(Contains(said, "Busy: closes over the controller through Busy > Controller"), true, "Busy refused")
	T.eq(Contains(said, "Report: closes over the controller through Controller"), true, "Report refused")
	T.eq(Contains(said, "swapped"), false, "nothing is reported swapped")
end)

T.test("only the server console or a superadmin may swap", function()
	local commands = Load({}, {})
	local said
	local ply = { IsSuperAdmin = function() return false end, ChatPrint = function(_, text) said = text end }
	commands.ws_hotswap_module(ply, nil, { "fake.area" })
	T.eq(said ~= nil, true, "refused")
end)

T.finish()
