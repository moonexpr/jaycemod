-- The loader's locals stay local: shared_loader.lua and the always-loaded
-- root modules never read GAMEMODE_ROOT or CHUNK_ENV as a global (each file
-- that needs one makes its own), which the game would see as nil.
local T = dofile ("tests/harness.lua")

local LOCALS = { "GAMEMODE_ROOT", "CHUNK_ENV" }

local function Lines (command)
	local pipe = assert (io.popen (command))
	local lines = {}
	for line in pipe:lines () do lines [#lines + 1] = line end
	pipe:close ()
	return lines
end

-- The globals a file reads, from LuaJIT's bytecode listing (GGET).
local function GlobalsRead (path)
	local read = {}
	for _, line in ipairs (Lines ("luajit -bl '" .. path .. "'")) do
		local name = line:match ('GGET%s+%d+%s+%d+%s+;%s+"([%w_]+)"')
		if name then read [name] = true end
	end
	return read
end

T.test ("the loader and root modules read none of the loader's locals as globals", function ()
	local paths = Lines ("ls " .. T.ROOT .. "*.lua")
	paths [#paths + 1] = T.ROOT .. "shared_loader.lua"
	for _, path in ipairs (paths) do
		local read = GlobalsRead (path)
		for _, name in ipairs (LOCALS) do
			T.eq (read [name], nil, path:sub (#T.ROOT + 1) .. " reads the global " .. name)
		end
	end
end)

T.test ("WS.require keeps logical module names while resolving the new directory layout", function ()
	local compiled, fakePackage = {}, { loaded = {} }
	local env
	env = setmetatable (
		{
			GM = { FolderName = "sandcastle" },
			SERVER = false,
			CLIENT = false,
			WS = { Logger = function () return function () end end },
			package = fakePackage,
			util = { IsBinaryModuleInstalled = function () return false end },
			include = function () end, -- NextSoldier, which loads itself
			CompileFile = function (path)
				compiled [#compiled + 1] = path
				if path == "sandcastle/gamemode/foundation/core/namespace.lua" then
					return function (name)
						fakePackage.loaded [name] =
						{
							Environment = function (globals, requireModule)
								return setmetatable ({ require = requireModule }, { __index = globals })
							end
						}
					end
				end
				if path:match ("/sh_index%.lua$") or path:match ("/sh_init%.lua$") then return function () end end
				return function (name) fakePackage.loaded [name] = {} end
			end
		}, { __index = _G })
	env._G = env
	setfenv (assert (loadfile (T.ROOT .. "shared_loader.lua")), env) ()

	for name, path in pairs (
		{
			["includes.replicated"] = "includes/replicated.lua",
			["games.gameplay.teams"] = "includes/gameplay/teams.lua",
			["games.list.drawlist"] = "includes/extensions/list/drawlist.lua"
		}
	) do
		env.WS.require (name)
		T.eq (compiled [#compiled], "sandcastle/gamemode/" .. path, name)
	end
end)

T.finish ()
