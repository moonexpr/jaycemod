-- A Lua file run again now, where dev.reload refuses it, so a change is seen without a
-- changelevel: dev.run(path[, realm]) runs the file's text as it is on disk on the server, on
-- every client (through luadev), or both ("sv", "cl", "sh"; by its name unless given:
-- sandcastle_dev_run). It runs as the gamemode ran it, GM the gamemode; an entity's or a weapon's
-- own file is registered again as its class, on each realm it runs on. Running a file again is
-- the caller's judgement: a root file's state (a table it builds anew) starts over. Clients that
-- join later get the file as the map loaded it.
local Run = dev.require ("sandcastle_dev_run")

local REALMS = { sv = true, cl = true, sh = true }

-- Runs code on every client now; how many there were.
local function OnClients (code, path)
	if not luadev then dev.Fail ("luadev is not loaded: clients cannot be reached") end
	luadev.RunOnClients (code, "dev.run " .. path)
	return #player.GetHumans ()
end

function dev.run (path, realm)
	local luaPath = Run.LuaPath (path)
	local source = file.Read (luaPath, "LUA")
	if not source then dev.Fail ("no Lua file " .. luaPath .. " in the LUA path") end
	realm = realm or Run.Realm (luaPath)
	if not REALMS [realm] then dev.Fail ("realm is sv, cl or sh, not " .. tostring (realm)) end
	local code = Run.Wrapped (source, Run.Script (luaPath))
	local result = { file = luaPath, realm = realm }
	if realm ~= "cl" then
		local chunk = CompileString (code, luaPath, false)
		if not isfunction (chunk) then dev.Fail (luaPath .. " did not compile: " .. tostring (chunk)) end
		chunk ()
		result.server = true
	end
	if realm ~= "sv" then result.clients = OnClients (code, luaPath) end
	return result
end

-- dev.reload's: a shared entity's new code to the clients, which registered the old.
function dev.run_entity_on_clients (luaPath)
	local source = file.Read (luaPath, "LUA")
	if not (source and luadev and string.find (source, "AddCSLuaFile(", 1, true)) then return nil end
	return OnClients (Run.Wrapped (source, Run.Script (luaPath)), luaPath)
end

dev.Command ("dev_run", function (args)
	if not args [1] then dev.Fail ("dev_run <file> [sv|cl|sh]") end
	return dev.run (args [1], args [2])
end, "dev_run <file> [sv|cl|sh]: run a Lua file again now, on the server, the clients or both")
