-- Game events v2 research, questions 2 and 3 (server side), part 1 of 2:
-- logs every OnReloaded hook call and wraps AddCSLuaFile, include and
-- CompileFile, so that lua_refresh_file runs afterwards show what a refresh
-- re-runs, in what order, and what a wrapper would see. reload_report.lua
-- writes the log. Lives only in the test server's Lua state.
local NAME = "reload_arm"
WS_GEV2 = WS_GEV2 or { log = {} }
local G = WS_GEV2

local function Log(...)
	local parts = { string.format("%.3f", SysTime()) }
	for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
	G.log[#G.log + 1] = table.concat(parts, " | ")
end
G.Log = Log

local function Caller(level)
	local info = debug.getinfo(level, "Sl")
	return info and (info.source .. ":" .. tostring(info.currentline)) or "?"
end

hook.Add("OnReloaded", "ws_tests_gev2", function()
	Log("hook OnReloaded", "GAMEMODE.FolderName=" .. tostring(GAMEMODE and GAMEMODE.FolderName))
end)

local function Wrap(name)
	if G["orig_" .. name] then return end
	local orig = _G[name]
	G["orig_" .. name] = orig
	_G[name] = function(path, ...)
		Log(name, tostring(path), "caller=" .. Caller(3))
		return orig(path, ...)
	end
end
Wrap("AddCSLuaFile")
Wrap("include")
Wrap("CompileFile")

Log("armed")
file.CreateDir("ws_tests/gev2/out")
file.Write("ws_tests/gev2/out/" .. NAME .. ".txt", "armed at " .. SysTime() .. "\n")
print("ws_tests: gev2 " .. NAME .. " done")
