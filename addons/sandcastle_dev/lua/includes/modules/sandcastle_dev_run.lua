-- The dev workbench's running of a Lua file again, now (dev.run, and dev.reload's push of an
-- entity to clients, sv_run.lua):
--   LuaPath(path) -> its path in the LUA tree: a repo path (addons/sandcastle/gamemodes/...,
--     addons/<addon>/lua/...) without its prefix; a LUA path as it is
--   Realm(luaPath) -> "sv", "cl" or "sh", the realms that run it, by its name: sv_, sv, init the
--     server's; cl_, cl the clients'; sh_, sh, shared, an entity, a weapon and a module both
--     realms'; anything else the server's
--   Script(luaPath) -> { kind = "entity" | "weapon", class } for an entity's or weapon's own file,
--     nil for any other
--   Wrapped(source[, script]) -> source as a chunk that runs as the gamemode ran it: GM the
--     gamemode while it runs and gone after, a script's ENT or SWEP fresh and registered as its
--     class; its lines keep their numbers and its error is raised again
local ipairs = ipairs
local format, match = string.format, string.match
module(...)

local REPO_PREFIXES = { "^addons/sandcastle/gamemodes/", "^addons/[%w_]+/lua/" }

function LuaPath(path)
	for _, prefix in ipairs(REPO_PREFIXES) do
		local stripped, count = path:gsub(prefix, "", 1)
		if count == 1 then return stripped end
	end
	return path
end

local SERVER_NAMES = { init = true, sv = true }
local CLIENT_NAMES = { cl = true }
local SHARED_NAMES = { sh = true, shared = true }
-- Trees whose files both realms load: foundation, the games modules, the soldier's addons.
local SHARED_TREES = { "/gamemode/foundation/", "/gamemode/includes/", "^nextsoldier/", "^wartactics/" }

function Script(luaPath)
	local dir, class = match(luaPath, "([%w_]+)/([%w_]+)%.lua$")
	if dir == "entities" then return { kind = "entity", class = class } end
	if dir == "weapons" then return { kind = "weapon", class = class } end
	return nil
end

function Realm(luaPath)
	local name = match(luaPath, "([%w_]+)%.lua$") or ""
	if SERVER_NAMES[name] or match(name, "^sv_") then return "sv" end
	if CLIENT_NAMES[name] or match(name, "^cl_") then return "cl" end
	if SHARED_NAMES[name] or match(name, "^sh_") or Script(luaPath) then return "sh" end
	for _, tree in ipairs(SHARED_TREES) do
		if match(luaPath, tree) then return "sh" end
	end
	return "sv"
end

-- What a script's file fills, and how it is registered.
local SCRIPTS = {
	entity = { global = "ENT", folder = "entities/", register = "scripted_ents.Register" },
	weapon = { global = "SWEP", folder = "weapons/", register = "weapons.Register" },
}

-- All on the source's first line and after its last, so its lines keep their numbers.
function Wrapped(source, script)
	local kind = script and SCRIPTS[script.kind]
	local open = kind and format("%s = { Folder = %q } ", kind.global, kind.folder .. script.class) or ""
	local register = kind and format("if __dev_ok then %s(%s, %q) end %s = nil ", kind.register, kind.global, script.class, kind.global) or ""
	return "GM = GAMEMODE " .. open .. "local __dev_ok, __dev_err = pcall(function(...) " .. source
		.. "\nend, ...) GM = nil " .. register .. "if not __dev_ok then error(__dev_err, 0) end"
end
