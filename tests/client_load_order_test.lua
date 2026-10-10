-- The client's load order (cl_init.lua, shared.lua): every ws module
-- that builds on WS.UI loads after ws/cl_ui.lua defines it, an
-- sh_ module (loaded with shared.lua, before any cl_) included. Run against
-- the real file listing, with include recording the order.
local T = dofile("tests/harness.lua")

local ROOT = "addon/gamemodes/sandcastle/gamemode/"

local function listing(prefix)
	local found = {}
	for name in io.popen("ls " .. ROOT .. "ws"):lines() do
		if name:sub(1, #prefix) == prefix and name:match("%.lua$") then found[#found + 1] = name end
	end
	table.sort(found)
	return found
end

local function source(path)
	local f = assert(io.open(ROOT .. path))
	local text = f:read("*a")
	f:close()
	return text
end

local function clientOrder()
	local order = {}
	local env
	env = setmetatable({
		GM = { FolderName = "sandcastle" },
		CLIENT = true, SERVER = false,
		DeriveGamemode = function() end,
		file = { Find = function(pattern) return listing(pattern:match("ws/(%w+_)%*")) end },
		include = function(path)
			if path == "shared.lua" then
				setfenv(assert(loadfile(ROOT .. path)), env)()
			else
				order[#order + 1] = path
			end
		end,
	}, { __index = _G })
	setfenv(assert(loadfile(ROOT .. "cl_init.lua")), env)()
	return order
end

T.test("every module using WS.UI loads after cl_ui defines it", function()
	local order = clientOrder()
	local ui
	for i, path in ipairs(order) do
		if path == "ws/cl_ui.lua" then ui = i end
	end
	T.eq(ui ~= nil, true, "cl_ui.lua is loaded")
	for i, path in ipairs(order) do
		if path ~= "ws/cl_ui.lua" and source(path):find("WS%.UI%.") then
			T.eq(i > ui, true, path .. " loads after cl_ui.lua")
		end
	end
end)

T.finish()
