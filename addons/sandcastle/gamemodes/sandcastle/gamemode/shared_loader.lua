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
-- sandcastle_dev's reload reads GAMEMODE_ROOT and CHUNK_ENV off it.
-- GM exists only while the gamemode loads.
local GAMEMODE_ROOT = GM.FolderName .. "/gamemode/"
local CHUNK_ENV = setmetatable({}, { __index = _G })

function WS.require(name)
	if package.loaded[name] == nil then
		local chunk = CompileFile(GAMEMODE_ROOT .. name:gsub("%.", "/") .. ".lua")
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
	setfenv(CompileFile(GAMEMODE_ROOT .. path), INDEX_ENV)()
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
Index("games/system/sh_init.lua")
Index("games/list/sh_init.lua")
Index("games/timer/sh_init.lua")
Index("games/world/sh_init.lua")
Index("games/generator/sh_init.lua")
Index("games/gameplay/sh_init.lua")
Index("games/npc/sh_init.lua")

-- NextSoldier, the soldier itself, beside foundation and games, on both;
-- then the war's tactics engine, on NextSoldier.
Index("nextsoldier/sh_init.lua")
Index("wartactics/sh_init.lua")
