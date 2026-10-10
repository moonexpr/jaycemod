-- Hot swapping on the dedicated server (server_root.py): code edited while
-- the server runs, loaded without a restart, where lua_refresh_file cannot
-- reach (it re-runs included files, and modules and features are compiled).
-- From the server console (srcds.py rcon) or a superadmin:
--   wetsand_hotswap_module <foundation.capture.area>   runs the module's file
--     again; module(...) keeps its table, so the new functions are where
--     every holder of the module has them, and its state stays
--   wetsand_hotswap_feature <capture> <Method> [Method...]   runs the
--     feature's sv.lua again with its side effects stubbed (hooks, timers,
--     commands, convar callbacks, net, other features), and copies only the
--     methods named onto the live controller, whose state stays
-- A new file, or a change to a local the live code already holds, still
-- needs the map to change.

-- sh_core's WETSAND.require keeps the gamemode's root and the modules'
-- environment as upvalues.
local function RequireUpvalue(wanted)
	for i = 1, math.huge do
		local name, value = debug.getupvalue(WETSAND.require, i)
		if not name then return nil end
		if name == wanted then return value end
	end
end

local function Tell(ply, text)
	if IsValid(ply) then ply:ChatPrint(text) else print(text) end
end

local function Allowed(ply)
	if not IsValid(ply) or ply:IsSuperAdmin() then return true end
	Tell(ply, "hotswap: superadmins only")
	return false
end

concommand.Add("wetsand_hotswap_module", function(ply, _, args)
	if not Allowed(ply) then return end
	local name = args[1]
	local chunk = CompileFile(RequireUpvalue("GAMEMODE_ROOT") .. name:gsub("%.", "/") .. ".lua")
	setfenv(chunk, RequireUpvalue("CHUNK_ENV"))(name)
	Tell(ply, "hotswap: " .. name .. " reloaded")
end)

-- Stands for anything a feature's file reaches at load: every field and
-- call is itself, so nothing outside the rerun changes.
local INERT = setmetatable({}, {})
getmetatable(INERT).__index = function() return INERT end
getmetatable(INERT).__call = function() return INERT end

local STUBBED = { hook = INERT, timer = INERT, concommand = INERT, cvars = INERT, net = INERT }

concommand.Add("wetsand_hotswap_feature", function(ply, _, args)
	if not Allowed(ply) then return end
	local name = args[1]
	local live = WETSAND.Feature(name)
	local wetsand = setmetatable({ Feature = function() return INERT end }, { __index = WETSAND })
	local env = setmetatable({ WETSAND = wetsand }, { __index = function(_, key)
		if STUBBED[key] then return STUBBED[key] end
		if key == "util" then return setmetatable({ AddNetworkString = INERT }, { __index = util }) end
		return _G[key]
	end })
	local chunk = CompileFile(RequireUpvalue("GAMEMODE_ROOT") .. "features/" .. name .. "/sv.lua")
	local fresh = setfenv(chunk, env)()
	for i = 2, #args do live[args[i]] = fresh[args[i]] end
	Tell(ply, "hotswap: " .. name .. " " .. table.concat(args, " ", 2) .. " swapped")
end)
