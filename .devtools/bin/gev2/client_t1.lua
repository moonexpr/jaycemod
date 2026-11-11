-- Game events v2, T1 (docs/game-events-v2-plan.md §3): with sv_allowcslua 0,
-- does the client run the copy the server sent rather than its local copy,
-- for include and for CompileFile (WS.require, the feature loader)? And
-- after joining, does the client's cache/lua hold each sent file under
-- util.SHA256(text .. "\0"):sub(1, 40) of the text the server sent?
--
-- One file, two halves, run by .devtools/bin/gev2_probe.py:
-- 1. On the server, while the markers still read "sent-" (before they are
--    rewritten): `gev2_probe.py run client_t1`. It lists every file the
--    server sends (init.lua's rules) with its cache name, and writes
--    data/ws_tests/gev2/out/client_t1.txt.
-- 2. On the client, once it has joined: `gev2_probe.py run --client client_t1`.
--    It reads the server's list from the shared data folder, reports the
--    marker globals, and checks the cache for every sent file, and for the
--    marked files' current text on disk. It writes
--    data/ws_tests/gev2/client_out/client_t1.txt.
local NAME = "client_t1"
local DIR = "ws_tests/gev2/"
local SERVER_LIST = DIR .. "out/" .. NAME .. ".txt"
local CACHE_PATH = "MOD" -- garrysmod/; the research timed GAME at 463 ms for 191 misses
local MARKERS =
{
	"WS_T1_INCLUDE", -- cl_teams.lua, include
	"WS_T1_COMPILE", -- features/capture/cl.lua, the feature loader's CompileFile
	"WS_T1_REQUIRE" -- optional: a foundation module, WS.require's CompileFile (set as _G.WS_T1_REQUIRE)
}
local MARKED_KEYS =
{
	"gamemode/cl_teams.lua",
	"gamemode/features/capture/cl.lua"
}
local folder = GAMEMODE.FolderName
local out = {}

local function Say (...)
	local parts = {}
	for i = 1, select ("#", ...) do parts [#parts + 1] = tostring (select (i, ...)) end
	out [#out + 1] = table.concat (parts, " | ")
end

local function LuaPath (key)
	return folder .. "/" .. key
end

local function CacheName (text)
	return util.SHA256 (text .. "\0"):sub (1, 40)
end

local function Cached (name)
	return file.Exists ("cache/lua/" .. name .. ".lua", CACHE_PATH)
end

local function Write ()
	local dir = DIR .. (SERVER and "out" or "client_out")
	file.CreateDir (dir)
	file.Write (dir .. "/" .. NAME .. ".txt", table.concat (out, "\n") .. "\n")
	print ("ws_tests: gev2 " .. NAME .. " done")
end

Say ("realm", SERVER and "server" or "client", "VERSION", VERSION, "BRANCH", BRANCH, "map", game.GetMap ())
Say ("time", os.date ("!%Y-%m-%dT%H:%M:%SZ"), "sv_allowcslua", GetConVarString ("sv_allowcslua"))
for _, global in ipairs (MARKERS) do Say ("marker", global, tostring (_G [global])) end

-- The files the server sends: the entry files, the client-safe gamemode
-- trees, root modules, and every entity or weapon with a line
-- starting AddCSLuaFile().
local function SentKeys ()
	local keys = { "gamemode/cl_init.lua", "gamemode/shared.lua", "gamemode/shared_loader.lua" }
	local function Add (key)
		keys [#keys + 1] = key
	end
	local function Walk (dir)
		for _, f in ipairs (file.Find (LuaPath (dir) .. "*.lua", "LUA")) do
			if f ~= "sv.lua" and not f:match ("^sv_") then Add (dir .. f) end
		end
		local _, dirs = file.Find (LuaPath (dir) .. "*", "LUA")
		for _, d in ipairs (dirs) do Walk (dir .. d .. "/") end
	end
	for _, dir in ipairs ({ "gamemode/foundation/", "gamemode/includes/", "gamemode/nextsoldier/",
		"gamemode/wartactics/", "gamemode/features/", "gamemode/vendor/" }) do
			Walk (dir)
		end
	local bootstrap = { ["cl_init.lua"] = true, ["init.lua"] = true, ["shared.lua"] = true, ["shared_loader.lua"] = true }
	for _, f in ipairs (file.Find (LuaPath ("gamemode/") .. "*.lua", "LUA")) do
		if not bootstrap [f] and f ~= "sv.lua" and not f:match ("^sv_") then Add ("gamemode/" .. f) end
	end
	for _, kind in ipairs ({ "entities", "weapons" }) do
		for _, f in ipairs (file.Find (LuaPath ("entities/" .. kind .. "/") .. "*.lua", "LUA")) do
			local key = "entities/" .. kind .. "/" .. f
			if ("\n" .. (file.Read (LuaPath (key), "LUA") or "")):find ("\nAddCSLuaFile%s*%(%)") then Add (key) end
		end
	end
	table.sort (keys)
	return keys
end

if SERVER then
	local keys = SentKeys ()
	Say ("sent", #keys)
	for _, key in ipairs (keys) do
		local text = file.Read (LuaPath (key), "LUA")
		Say ("file", key, text and CacheName (text) or "unreadable", text and #text or 0)
	end
	Write ()
	return
end

-- The client ---------------------------------------------------------------------------------

-- Whether this client ran the file in this session: a foundation or includes
-- module is in package.loaded, a feature part ran if its feature loaded here,
-- and the entry files, root modules and entities always run.
local function Ran (key)
	local module = key:match ("^gamemode/(foundation/.+)%.lua$")
	if module then return package.loaded [module:gsub ("/", ".")] ~= nil end
	module = key:match ("^gamemode/includes/(.+)%.lua$")
	if module then
		module = module:gsub ("^extensions/", "")
		return package.loaded ["games." .. module:gsub ("/", ".")] ~= nil
	end
	local feature = key:match ("^gamemode/features/([^/]+)/")
	if feature then return WS.FeatureLoaded (feature) end
	return true
end

local loaded = WS.FeatureLoader and WS.FeatureLoader:Loaded () or {}
Say ("features loaded here", table.concat (loaded, ","))

local list = file.Read (SERVER_LIST, "DATA")
if not list then
	Say ("no server list", SERVER_LIST, "run `gev2_probe.py run client_t1` on the server first")
else
	local sentName = {}
	local started = SysTime ()
	local counts =
	{
		ran_cached = 0,
		ran_missing = 0,
		unrun_cached = 0,
		unrun_missing = 0
	}
	local missing = {}
	for key, name in list:gmatch ("file | ([^|\n]+) | (%x+) | %d+") do
		sentName [key] = name
		local ran, cached = Ran (key), Cached (name)
		local class = (ran and "ran_" or "unrun_") .. (cached and "cached" or "missing")
		counts [class] = counts [class] + 1
		if ran and not cached then missing [#missing + 1] = key end
	end
	Say ("cache check", CACHE_PATH, string.format ("%.1f ms", (SysTime () - started) * 1000))
	for _, class in ipairs ({ "ran_cached", "ran_missing", "unrun_cached", "unrun_missing" }) do Say ("count", class, counts [class]) end
	for _, key in ipairs (missing) do Say ("ran, not in cache", key, sentName [key]) end
	for _, key in ipairs (MARKED_KEYS) do
		local name = sentName [key]
		Say ("marked, as sent", key, tostring (name), name and (Cached (name) and "in cache" or "not in cache") or "not in the list")
	end
end

-- The marked files' text on disk now (the client has the addon locally: the
-- install is shared), and whether the cache holds that text too.
for _, key in ipairs (MARKED_KEYS) do
	local text = file.Read (LuaPath (key), "LUA")
	if not text then
		Say ("marked, on disk", key, "file.Read returned nil")
	else
		local name = CacheName (text)
		Say ("marked, on disk", key, name, Cached (name) and "in cache" or "not in cache", "first line: " .. (text:match ("^[^\n]*") or ""))
	end
end

Write ()
