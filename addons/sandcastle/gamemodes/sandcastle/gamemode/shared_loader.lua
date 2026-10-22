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

local INDEX_ENV = WS.require("foundation.core.namespace").Environment(_G, WS.require)

local function Index(path)
	setfenv(CompileFile(GAMEMODE_ROOT .. path), INDEX_ENV)()
end

Index("foundation/core/sh_index.lua")
Index("foundation/math/sh_index.lua")
Index("foundation/list/sh_index.lua")
Index("foundation/tree/sh_index.lua")
Index("foundation/map/sh_index.lua")
Index("foundation/graph/sh_index.lua")
Index("foundation/cache/sh_index.lua")
Index("foundation/generator/sh_index.lua")
Index("foundation/encoding/sh_index.lua")
Index("foundation/file/sh_index.lua")
Index("foundation/analysis/sh_index.lua")
Index("foundation/npc/sh_index.lua")
Index("foundation/sh_index.lua")
