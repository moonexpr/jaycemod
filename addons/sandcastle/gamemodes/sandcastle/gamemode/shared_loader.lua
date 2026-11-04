-- The first file the gamemode runs, on both realms (shared.lua). It defines
-- the gamemode's require, then loads foundation: each namespace's index,
-- named below by hand, publishes its modules as globals (list.queue,
-- math.geometry). foundation may replace GMod's defaults, so a module joins
-- by a line here and in its index, never by a loop or a folder scan, and
-- each replacement is a line someone wrote (docs/foundation-game-split-plan.md).
WS = WS or {}

-- Lua 5.1's require for the gamemode's module(...) files: GMod's include
-- passes no name to the chunk, so load it here, once, calling it with the
-- dotted name. Above its module(...) call the chunk sees this require
-- (GMod's own looks only in includes/modules/), to load its siblings.
-- sandcastle_dev's reload reads CHUNK_ENV off it.
-- GM exists only while the gamemode loads.
local GAMEMODE_ROOT = GM.FolderName .. "/gamemode/"
local Boot = WS.Logger("boot")
local CHUNK_ENV = setmetatable({}, { __index = _G })

local API_EXTENSIONS = { list = true, timer = true, world = true, generator = true }
local function ModulePath(name)
	local path = name
	local namespace = name:match("^games%.([%w_]+)%.")
	if namespace then
		path = name:gsub("^games%.", "includes.")
		if API_EXTENSIONS[namespace] then path = path:gsub("^includes%.", "includes.extensions.") end
	end
	return path:gsub("%.", "/") .. ".lua"
end

-- The trees an addon of the repo ships under its own lua/, on the LUA
-- path's root rather than the gamemode's folder: the tactics engine
-- (addons/wartactics/lua/wartactics/), and NextSoldier
-- (addons/nextsoldier/lua/nextsoldier/) for sandcastle_dev's reload alone.
local ADDON_TREES = { nextsoldier = true, wartactics = true }

-- A gamemode-relative path (nextsoldier/sh_init.lua, includes/npc/actor.lua)
-- as a LUA path. What sends clients the module folders, and sandcastle_dev's
-- reload, read files through it too.
local function LoaderFile(path)
	if ADDON_TREES[path:match("^([%w_]+)/")] then return path end
	return GAMEMODE_ROOT .. path
end
WS.LoaderFile = LoaderFile

-- A module's file as a LUA path.
local function ModuleFile(name)
	return LoaderFile(ModulePath(name))
end
WS.ModuleFile = ModuleFile

function WS.require(name)
	if package.loaded[name] == nil then
		Boot("require %s", name)
		local chunk = CompileFile(ModuleFile(name))
		setfenv(chunk, CHUNK_ENV)(name)
	end
	return package.loaded[name]
end
CHUNK_ENV.require = WS.require

-- The native foundation (native/, docs/native-foundation-plan.md): a server
-- with a binary module installed has it put its native twins at their
-- globals first, before any index runs; each module's index line (Twin)
-- then keeps the native twin, whole, so every module that binds one to a
-- local as it loads gets the native one. One line a module, never a loop.
local NATIVE = SERVER and util.IsBinaryModuleInstalled("foundation")
if NATIVE then require("foundation") end
if SERVER and util.IsBinaryModuleInstalled("wetsands") then require("wetsands") end

-- The indexes run in core.namespace's environment: the native one, which
-- the binary put at its global, on a server with it; the Lua twin's on a
-- client.
local Namespaces = NATIVE and core.namespace or WS.require("foundation.core.namespace")
local INDEX_ENV = Namespaces.Environment(_G, WS.require)

local function Index(path)
	Boot("index %s", path)
	setfenv(CompileFile(LoaderFile(path)), INDEX_ENV)()
end

-- A module reads the modules it uses by their globals as it loads, so a
-- namespace comes after every namespace its modules read
-- (tests/foundation_index_test.lua checks the order).
Index("foundation/world/sh_index.lua")
Index("foundation/tree/sh_index.lua")
Index("foundation/list/sh_index.lua")
Index("foundation/math/sh_index.lua")
Index("foundation/file/sh_index.lua")
Index("foundation/core/sh_index.lua")
Index("foundation/graph/sh_index.lua")
Index("foundation/cache/sh_index.lua")
Index("foundation/generator/sh_index.lua")
Index("foundation/encoding/sh_index.lua")
Index("foundation/analysis/sh_index.lua")
Index("foundation/wetsands/sh_index.lua")
Index("foundation/sh_index.lua")

-- game: published at once, each module loaded the first time it is read,
-- so a map pays only for the gameplay it uses.
Index("includes/system/sh_init.lua")
Index("includes/extensions/list/sh_init.lua")
Index("includes/extensions/timer/sh_init.lua")
Index("includes/extensions/world/sh_init.lua")
Index("includes/extensions/generator/sh_init.lua")
Index("includes/gameplay/sh_init.lua")
Index("includes/npc/sh_init.lua")

-- NextSoldier, the soldier itself, its own addon (addons/nextsoldier) on
-- foundation, which loads itself whole and shares nothing of ours; then the
-- war's tactics engine, its own addon too (addons/wartactics).
include("nextsoldier/sh_init.lua")
Index("wartactics/sh_init.lua")
