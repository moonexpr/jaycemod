-- The loader's locals stay local: shared_loader.lua and the always-loaded
-- ws/ files never read GAMEMODE_ROOT or CHUNK_ENV as a global (each file
-- that needs one makes its own), which the game would see as nil.
local T = dofile("tests/harness.lua")

local LOCALS = { "GAMEMODE_ROOT", "CHUNK_ENV" }

local function Lines(command)
	local pipe = assert(io.popen(command))
	local lines = {}
	for line in pipe:lines() do lines[#lines + 1] = line end
	pipe:close()
	return lines
end

-- The globals a file reads, from LuaJIT's bytecode listing (GGET).
local function GlobalsRead(path)
	local read = {}
	for _, line in ipairs(Lines("luajit -bl '" .. path .. "'")) do
		local name = line:match('GGET%s+%d+%s+%d+%s+;%s+"([%w_]+)"')
		if name then read[name] = true end
	end
	return read
end

T.test("the loader and ws/ read none of the loader's locals as globals", function()
	local paths = Lines("ls " .. T.ROOT .. "ws/*.lua")
	paths[#paths + 1] = T.ROOT .. "shared_loader.lua"
	for _, path in ipairs(paths) do
		local read = GlobalsRead(path)
		for _, name in ipairs(LOCALS) do
			T.eq(read[name], nil, path:sub(#T.ROOT + 1) .. " reads the global " .. name)
		end
	end
end)

T.finish()
