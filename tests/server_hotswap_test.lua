-- The dedicated server's hotswap.lua (.devtools/bin/server_root/): code
-- edited while the server runs, loaded without a restart. A module
-- (WETSAND.require) runs again and keeps its table, so its functions update
-- where every holder has them; a feature's file runs again with its side
-- effects stubbed (hooks, timers, commands, other features), and only the
-- methods named are copied onto the live controller, whose state stays.
local T = dofile("tests/harness.lua")

local ROOT = "sandcastle/gamemode/"

-- files: path -> source; the server's WETSAND.require keeps GAMEMODE_ROOT
-- and CHUNK_ENV as upvalues, as sh_core's does.
local function Load(files, features)
	local commands, hooksAdded = {}, 0
	local GAMEMODE_ROOT = ROOT
	local CHUNK_ENV = setmetatable({}, { __index = _G })
	local WETSAND = {}
	function WETSAND.require(name)
		local _ = GAMEMODE_ROOT, CHUNK_ENV
		return package.loaded[name]
	end
	WETSAND.Feature = function(name) return features[name] end
	local env = setmetatable({
		WETSAND = WETSAND,
		CompileFile = function(path) return assert(loadstring(files[path], path)) end,
		concommand = { Add = function(name, fn) commands[name] = fn end },
		hook = { Add = function() hooksAdded = hooksAdded + 1 end },
		IsValid = function(v) return v ~= nil end,
		print = function() end,
	}, { __index = _G })
	setfenv(assert(loadfile(".devtools/bin/server_root/hotswap.lua")), env)()
	return commands, CHUNK_ENV, function() return hooksAdded end
end

T.test("a module runs again in place: every holder of its table sees the new function", function()
	package.loaded["fake.area"] = nil
	local files = { [ROOT .. "fake/area.lua"] = "module(...) function Answer() return 1 end" }
	local commands, env = Load(files, {})
	setfenv(assert(loadstring(files[ROOT .. "fake/area.lua"])), env)("fake.area")
	local held = package.loaded["fake.area"]
	files[ROOT .. "fake/area.lua"] = "module(...) function Answer() return 2 end function Added() return 3 end"
	commands.wetsand_hotswap_module(nil, nil, { "fake.area" })
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
			Controller.rounds = WETSAND.Feature("rounds")
			Controller.rounds:AddTimerHold("x")
			function Controller:Old() return "new " .. self.set end
			function Controller:Kept() return "changed" end
			return Controller
		]],
	}
	local commands, _, hooks = Load(files, { capture = live, rounds = {} })
	commands.wetsand_hotswap_feature(nil, nil, { "capture", "Old" })
	T.eq(live:Old(), "new live state", "the new method, on the live state")
	T.eq(live:Kept(), "kept", "an unnamed method stays")
	T.eq(hooks(), 0, "no hook added again")
end)

T.test("only the server console or a superadmin may swap", function()
	local commands = Load({}, {})
	local said
	local ply = { IsSuperAdmin = function() return false end, ChatPrint = function(_, text) said = text end }
	commands.wetsand_hotswap_module(ply, nil, { "fake.area" })
	T.eq(said ~= nil, true, "refused")
end)

T.finish()
