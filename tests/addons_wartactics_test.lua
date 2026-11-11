-- The tactics engine's addon (addons/wartactics): the strategy NextSoldier's
-- soldiers are organised by, its modules under lua/wartactics/. The gamemode
-- loads them from the LUA path's root, not its own folder, and keeps none.
local T = dofile ("tests/harness.lua")

local ADDON = "addons/wartactics/"

local function Exists (path)
	local file = io.open (path, "r")
	if file then file:close () end
	return file ~= nil
end

local function Lines (command)
	local pipe = assert (io.popen (command))
	local lines = {}
	for line in pipe:lines () do lines [#lines + 1] = line end
	pipe:close ()
	return lines
end

T.test ("the addon has a manifest", function ()
	T.eq (Exists (ADDON .. "addon.json"), true, ADDON .. "addon.json")
end)

T.test ("every wartactics module the index publishes is the addon's", function ()
	local count = 0
	for module in pairs (T.Published.global) do
		if module:match ("^wartactics%.") then
			count = count + 1
			T.eq (T.Path (module),          ADDON .. "lua/" .. module:gsub ("%.", "/") .. ".lua", module)
			T.eq (Exists (T.Path (module)), true,                                                 T.Path (module))
		end
	end
	T.eq (count > 0, true, "wartactics modules published")
end)

T.test ("the index runs from the addon", function ()
	T.eq (T.File ("wartactics/sh_init.lua"), ADDON .. "lua/wartactics/sh_init.lua")
	T.eq (Exists (T.File ("wartactics/sh_init.lua")), true, "the addon's index")
end)

T.test ("the gamemode keeps no tactics module", function ()
	T.eq (#Lines ("ls " .. T.ROOT .. "wartactics/ 2>/dev/null"), 0, T.ROOT .. "wartactics/")
end)

T.test ("the gamemode's loader reads the tree from the addon", function ()
	local loader = assert (io.open (T.ROOT .. "shared_loader.lua")):read ("*a")
	local trees = loader:match ("local ADDON_TREES = (%b{})")
	T.eq (trees:find ("wartactics = true", 1, true) ~= nil, true, trees)
end)

T.test ("the addon reaches nothing of the war's feature", function ()
	for _, path in ipairs (Lines ("find " .. ADDON .. "lua -name '*.lua'")) do
		local source = assert (io.open (path)):read ("*a")
		T.eq (source:find ('require%s*%("features%.'), nil, path .. " requires a feature")
		T.eq (source:find ('require%s*%("ws%.'),       nil, path .. " requires glue")
	end
end)

-- Every module of tree, read with the other tree's global refusing any read.
local function LoadsApart (tree, other, except)
	local kept = _G [other]
	_G [other] = setmetatable ({}, { __index = function (_, key) error ("read " .. other .. "." .. key, 2) end })
	local count, refused = 0, {}
	for module in pairs (T.Published.global) do
		local key = module:match ("^" .. tree .. "%.(.+)$")
		if key and key ~= except then
			count = count + 1
			-- NextSoldier loaded whole already, so its file runs again here
			local loaded, why = pcall (function ()
				if tree == "nextsoldier" then return dofile (T.Path (module)) end
				return _G [tree] [key]
			end)
			if not loaded then refused [#refused + 1] = module .. ": " .. tostring (why) end
		end
	end
	_G [other] = kept
	T.eq (table.concat (refused, "\n"), "",   tree .. " modules read " .. other)
	T.eq (count > 0,                    true, tree .. " modules published")
end

T.test ("the tactics engine loads with NextSoldier out of reach, but for the bridge", function ()
	LoadsApart ("wartactics", "nextsoldier", "bridge")
end)

T.test ("NextSoldier loads with the tactics engine out of reach", function ()
	LoadsApart ("nextsoldier", "wartactics")
end)

T.finish ()
