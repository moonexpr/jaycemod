-- Game events v2 research, questions 1, 2 and 5 (server side): the source
-- paths debug.getinfo reports for each way the gamemode loads code, and what
-- file.Read sees in the LUA and GAME paths. Writes
-- data/ws_tests/gev2/out/sources.txt. Run by .devtools/bin/gev2_probe.py.
local NAME = "sources"
local out = {}

local function Say(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
	out[#out + 1] = table.concat(parts, " | ")
end

local function Source(label, fn)
	if not isfunction(fn) then
		Say(label, "no function")
		return
	end
	local info = debug.getinfo(fn, "S")
	Say(label, "source=" .. info.source, "short_src=" .. info.short_src, "what=" .. info.what, "line=" .. info.linedefined)
end

local function FirstFunction(t)
	local keys = {}
	for k, v in pairs(t or {}) do
		if isfunction(v) then keys[#keys + 1] = k end
	end
	table.sort(keys)
	return keys[1], keys[1] and t[keys[1]]
end

Say("realm", SERVER and "server" or "client", "VERSION", VERSION, "BRANCH", BRANCH, "map", game.GetMap())
Say("GM.FolderName", GAMEMODE.FolderName)

Say("--- gamemode files (include)")
Source("init.lua GM:PlayerSpawn", GAMEMODE.PlayerSpawn)
Source("shared.lua GM:StartCommand", GAMEMODE.StartCommand)
Source("shared.lua GM:WSModules", GAMEMODE.WSModules)
Source("ws/sh_core.lua WS.require", WS.require)
Source("ws/sh_events.lua Events.Fire", WS.Events and WS.Events.Fire)

Say("--- foundation modules (CompileFile in WS.require)")
for _, name in ipairs({ "games.system.features", "games.system.events", "games.gameplay.teams" }) do
	local key, fn = FirstFunction(package.loaded[name])
	Source(name .. "." .. tostring(key), fn)
end

Say("--- features (CompileFile in FeatureFiles:Run), loaded on this map")
local loaded = WS.FeatureLoader and WS.FeatureLoader:Loaded() or {}
Say("loaded features", table.concat(loaded, ","))
for _, name in ipairs(loaded) do
	local key, fn = FirstFunction(WS.FeatureLoader.values[name])
	if not fn then
		local mt = getmetatable(WS.FeatureLoader.values[name] or {})
		key, fn = FirstFunction(mt and mt.__index)
	end
	Source("feature " .. name .. "." .. tostring(key), fn)
end

Say("--- scripted entities and weapons (GMod's own loader)")
for _, class in ipairs({ "tf_gamerules", "merasmus", "team_round_timer", "ws_pickup_base" }) do
	local stored = scripted_ents.GetStored(class)
	local key, fn = FirstFunction(stored and stored.t)
	Source("ENT " .. class .. "." .. tostring(key), fn)
end
local spellbook = weapons.GetStored("tf_weapon_spellbook")
local wkey, wfn = FirstFunction(spellbook)
Source("SWEP tf_weapon_spellbook." .. tostring(wkey), wfn)

Say("--- base gamemodes and GMod's own Lua")
Source("sandbox GM:PlayerSpawn (BaseClass)", GAMEMODE.BaseClass and GAMEMODE.BaseClass.PlayerSpawn)
Source("lua/includes hook.Add", hook.Add)
Source("lua/includes net.WriteEntity", net.WriteEntity)

Say("--- chunk names given by the loader functions")
Source("this probe (RunString name)", debug.getinfo(1, "f").func)
Source("CompileFile('sandcastle/gamemode/games/gameplay/teams.lua')", CompileFile("sandcastle/gamemode/games/gameplay/teams.lua"))
Source("CompileString(code, 'x/y.lua')", CompileString("return function() end", "x/y.lua"))

Say("--- file.Read on the server")
local function ReadReport(path, gamePath)
	local text = file.Read(path, gamePath)
	Say("file.Read", gamePath, path, text and ("bytes=" .. #text .. " sha256=" .. util.SHA256(text):sub(1, 16)) or "nil")
end
for _, p in ipairs({
	"sandcastle/gamemode/shared.lua",
	"sandcastle/gamemode/features/capture/cl.lua",
	"sandcastle/entities/entities/merasmus.lua",
	"entities/merasmus.lua",
}) do
	ReadReport(p, "LUA")
	ReadReport(p, "lsv")
	ReadReport(p, "lcl")
end
ReadReport("gamemodes/sandcastle/gamemode/shared.lua", "GAME")
ReadReport("addons/sandcastle/gamemodes/sandcastle/gamemode/shared.lua", "GAME")
ReadReport("addons/sandcastle/gamemodes/sandcastle/gamemode/shared.lua", "MOD")

file.CreateDir("ws_tests/gev2/out")
file.Write("ws_tests/gev2/out/" .. NAME .. ".txt", table.concat(out, "\n") .. "\n")
print("ws_tests: gev2 " .. NAME .. " done")
