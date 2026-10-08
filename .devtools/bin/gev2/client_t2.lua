-- Game events v2, T2 (docs/game-events-v2-plan.md §3): after lua_refresh_file
-- of features/capture/cl.lua, and after a plain save, each with a new marker
-- line `WETSAND_T2 = "<step>-<nonce>"` at its top: does the connected client
-- gain the new text's cache entry, and does a client that joins next run the
-- new text?
--
-- Runs on either realm (gev2_probe.py run client_t2, or run --client
-- --label <step> client_t2). It reports the marker this realm is running
-- (the global; the server never runs a cl.lua, so nil there), the marker in
-- the text on disk now, that text's cache name, and on the client whether
-- cache/lua holds it.
local NAME = "client_t2"
local DIR = "wetsand_tests/gev2/"
local KEY = "gamemode/features/capture/cl.lua"
local CACHE_PATH = "MOD"
local out = {}

local function Say(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
	out[#out + 1] = table.concat(parts, " | ")
end

Say("realm", SERVER and "server" or "client", "VERSION", VERSION, "map", game.GetMap())
Say("time", os.date("!%Y-%m-%dT%H:%M:%SZ"), "sv_allowcslua", GetConVarString("sv_allowcslua"))
Say("running WETSAND_T2", tostring(WETSAND_T2))
if CLIENT then Say("capture loaded here", tostring(WETSAND.FeatureLoaded("capture"))) end

local text = file.Read(GAMEMODE.FolderName .. "/" .. KEY, "LUA")
if not text then
	Say("on disk", KEY, "file.Read returned nil")
else
	local name = util.SHA256(text .. "\0"):sub(1, 40)
	Say("on disk WETSAND_T2", tostring(text:match('WETSAND_T2%s*=%s*"([^"]*)"')))
	Say("on disk", KEY, "bytes", #text, "cache name", name)
	if CLIENT then
		Say("on disk text in cache", file.Exists("cache/lua/" .. name .. ".lua", CACHE_PATH) and "yes" or "no")
	end
end

local dir = DIR .. (SERVER and "out" or "client_out")
file.CreateDir(dir)
file.Write(dir .. "/" .. NAME .. ".txt", table.concat(out, "\n") .. "\n")
print("wetsand_tests: gev2 " .. NAME .. " done")
