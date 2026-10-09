-- foundation.replicated: the gamemode's convars are replicated, so a client
-- knows every one (its console completes them and shows their values), and
-- notify, so a change is told in chat.
local T = dofile("tests/harness.lua")
local Replicated = T.require("foundation.replicated")

local FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED = 128, 256, 8192

T.test("a convar created by the gamemode's own files is ours", function()
	T.eq(Replicated.Ours("gamemodes/sandcastle/gamemode/features/capture/sv.lua", "sandcastle"), true)
	T.eq(Replicated.Ours("@gamemodes/sandcastle/gamemode/wetsand/sh_aiwar.lua", "sandcastle"), true, "with Lua's @")
	T.eq(Replicated.Ours("addons/ulx/lua/ulx/modules/sh/rcon.lua", "sandcastle"), false, "another addon's")
	T.eq(Replicated.Ours("gamemodes/sandbox/gamemode/init.lua", "sandcastle"), false, "the base gamemode's")
end)

-- A client's own convars (the overlay's part toggles, made in cl_ files
-- with CreateClientConVar) are not replicated: the client sets them, and a
-- replicated one only the server may set.
T.test("a convar from a client-only file is the client's own, never replicated", function()
	T.eq(Replicated.ClientOnly("@gamemodes/sandcastle/gamemode/wetsand/cl_ns_debug.lua"), true, "a wetsand cl_ file")
	T.eq(Replicated.ClientOnly("@gamemodes/sandcastle/gamemode/features/capture/cl.lua"), true, "a feature's client part")
	T.eq(Replicated.ClientOnly("@gamemodes/sandcastle/gamemode/wetsand/sh_aiwar.lua"), false, "shared")
	T.eq(Replicated.ClientOnly("@gamemodes/sandcastle/gamemode/features/aiwar/sv.lua"), false, "a server part")
	T.eq(Replicated.ClientOnly("@gamemodes/sandcastle/gamemode/features/capture/sh.lua"), false, "a feature's shared part")
end)

T.test("the replicated flag joins whatever flags the convar has", function()
	T.eq(Replicated.Flags(nil, FCVAR_REPLICATED), FCVAR_REPLICATED, "none")
	T.eq(Replicated.Flags(FCVAR_ARCHIVE, FCVAR_REPLICATED), FCVAR_ARCHIVE + FCVAR_REPLICATED, "a number")
	T.eq(Replicated.Flags({ FCVAR_ARCHIVE, FCVAR_NOTIFY }, FCVAR_REPLICATED), FCVAR_ARCHIVE + FCVAR_NOTIFY + FCVAR_REPLICATED, "a list")
	T.eq(Replicated.Flags(FCVAR_REPLICATED + FCVAR_ARCHIVE, FCVAR_REPLICATED), FCVAR_REPLICATED + FCVAR_ARCHIVE, "already replicated")
end)

T.test("the gamemode's convars are replicated and notify", function()
	T.eq(Replicated.Added(FCVAR_REPLICATED, FCVAR_NOTIFY), FCVAR_REPLICATED + FCVAR_NOTIFY)
	T.eq(Replicated.Flags(FCVAR_ARCHIVE, Replicated.Added(FCVAR_REPLICATED, FCVAR_NOTIFY)), FCVAR_ARCHIVE + FCVAR_REPLICATED + FCVAR_NOTIFY)
end)

T.finish()
