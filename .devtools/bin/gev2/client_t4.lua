-- Game events v2, T4 (docs/game-events-v2-plan.md §3): the source path
-- debug.getinfo(fn, "S") reports on this realm for a file the server sent
-- (included, compiled by WS.require, and a feature part) and for an
-- entity and a weapon, with the key Paths.Key would take from it (the part
-- from gamemode/ or entities/ on). Runs on either realm: `gev2_probe.py run
-- client_t4` on the server, `run --client client_t4` on the client; compare
-- the two.
local NAME = "client_t4"
local DIR = "ws_tests/gev2/"
local out = {}

local function Say(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
	out[#out + 1] = table.concat(parts, " | ")
end

-- The suffix rule the plan gives Paths.Key: what follows "<folder>/gamemode/"
-- or "<folder>/entities/", kept with that segment.
local function Key(source)
	local folder = GAMEMODE.FolderName
	for _, segment in ipairs({ "gamemode/", "entities/" }) do
		local at = source:find(folder .. "/" .. segment, 1, true)
		if at then return source:sub(at + #folder + 1) end
	end
	return "not ours"
end

local function Source(label, fn)
	if not isfunction(fn) then
		Say(label, "no function")
		return
	end
	local info = debug.getinfo(fn, "S")
	Say(label, "source=" .. info.source, "short_src=" .. info.short_src, "what=" .. info.what, "key=" .. Key(info.source))
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

Say("--- entry files and ws/ (include)")
if SERVER then
	Source("init.lua GM:PlayerSpawn", GAMEMODE.PlayerSpawn)
else
	Source("cl_init.lua GM:HUDPaint", GAMEMODE.HUDPaint)
end
Source("shared.lua GM:WSModules", GAMEMODE.WSModules)
Source("ws/sh_core.lua WS.require", WS.require)
Source("ws/sh_events.lua Events.Fire", WS.Events and WS.Events.Fire)

Say("--- foundation modules (WS.require's CompileFile)")
for _, name in ipairs({ "games.system.features", "games.system.events", "games.gameplay.teams" }) do
	local key, fn = FirstFunction(package.loaded[name])
	Source(name .. "." .. tostring(key), fn)
end

Say("--- features loaded on this realm (the feature loader's CompileFile)")
local loaded = WS.FeatureLoader and WS.FeatureLoader:Loaded() or {}
Say("loaded features", table.concat(loaded, ","))
for _, name in ipairs(loaded) do
	local value = WS.FeatureLoader.values[name]
	local key, fn = FirstFunction(value)
	if not fn then
		local mt = getmetatable(value or {})
		key, fn = FirstFunction(mt and mt.__index)
	end
	Source("feature " .. name .. "." .. tostring(key), fn)
end

Say("--- scripted entities and weapons (GMod's loader)")
for _, class in ipairs({ "merasmus", "halloween_base_boss", "team_round_timer", "tf_gamerules" }) do
	local stored = scripted_ents.GetStored(class)
	local key, fn = FirstFunction(stored and stored.t)
	Source("ENT " .. class .. "." .. tostring(key), fn)
end
local spellbook = weapons.GetStored("tf_weapon_spellbook")
local wkey, wfn = FirstFunction(spellbook)
Source("SWEP tf_weapon_spellbook." .. tostring(wkey), wfn)

Say("--- GMod's own Lua, for contrast")
Source("lua/includes hook.Add", hook.Add)

local dir = DIR .. (SERVER and "out" or "client_out")
file.CreateDir(dir)
file.Write(dir .. "/" .. NAME .. ".txt", table.concat(out, "\n") .. "\n")
print("ws_tests: gev2 " .. NAME .. " done")
