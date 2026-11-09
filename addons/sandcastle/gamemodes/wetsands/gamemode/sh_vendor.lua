-- The vendored libraries under vendor/ (docs/vendor.md: ZakBlystone's
-- loaders, and Foohy's Jazztronauts libraries), included the first time
-- something asks, since the Jazztronauts BSP query reads the whole map then.
-- They are GMod Lua with globals of their own (bsp3, bsp2, brush, poly,
-- task, ...); the gamemode reaches them through here.
--   WS.MapFile(names): this map's .bsp read by bsp3, only the lumps named
--     (bsp3.LUMP_<name>: "TEXDATA_STRING_DATA", ...), each parsed, by name
--     (bsp3 is loaded only then, so callers name lumps, not its constants).
--   WS.MapQuery(): the Jazztronauts map (bsp2): brushes, leafs, brush
--     models, entities, displacements and :Trace{ pos, dir, tmin, tmax,
--     mask }, the whole map loaded once.
--   WS.UseVendored(): every library included, for the rest (sh_mdl's model
--     loader, phy3's collision models).
local ROOT = GM.FolderName .. "/gamemode/vendor/"

-- In Jazztronauts' own order (its lib/shared.lua); sh_irt includes sh_rect
-- and sh_scene, which includes sh_camera.
local LOADERS = { "loaders/bsp3.lua", "loaders/phy3.lua" }
local JAZZTRONAUTS = {
	"sh_gc.lua", "sh_task.lua", "sh_mesh.lua", "sh_mathutils.lua", "sh_geomutils.lua",
	"sh_irt.lua", "sh_gfx.lua", "sh_poly.lua", "sh_brush.lua", "sh_bsp2.lua",
	"sh_bmodelmap.lua", "sh_bspquery.lua", "sh_mdl.lua",
}

local loadersIn, jazztronautsIn = false, false

local function Loaders()
	if loadersIn then return end
	loadersIn = true
	for _, path in ipairs(LOADERS) do include(ROOT .. path) end
end

function WS.UseVendored()
	Loaders()
	if jazztronautsIn then return end
	jazztronautsIn = true
	for _, name in ipairs(JAZZTRONAUTS) do include(ROOT .. "jazztronauts/" .. name) end
	-- bmodelmap maps the map's brush entities at InitPostEntity, long past
	-- by now: map those standing
	hook.GetTable().OnReloaded.JazzBModelMapInit()
end

function WS.MapFile(names)
	Loaders()
	local ids = {}
	for i, name in ipairs(names) do
		ids[i] = bsp3["LUMP_" .. name]
		if not ids[i] then error("bsp3 has no lump " .. name, 2) end
	end
	local data = bsp3.LoadBSP("maps/" .. game.GetMap() .. ".bsp", ids, "GAME")
	if not data then error("could not read maps/" .. game.GetMap() .. ".bsp") end
	local lumps = {}
	for i, name in ipairs(names) do lumps[name] = data[ids[i]] end
	return lumps
end

function WS.MapQuery()
	WS.UseVendored()
	return bsp2.GetCurrent()
end
