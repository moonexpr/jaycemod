-- The client's load order (cl_init.lua, shared.lua): every ws module
-- that builds on WS.UI or WS.TFHud loads after the module defining it, an
-- sh_ module (loaded with shared.lua, before any cl_) included; the
-- player's feedback (hit sounds, damage numbers) loads before the HUD and
-- reads nothing of it; and a module that fails to load takes no other
-- with it. Run against the real file listing, with include recording the
-- order.
local T = dofile("tests/harness.lua")

local ROOT = "addons/sandcastle/gamemodes/sandcastle/gamemode/"

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

-- The ws modules cl_init includes, in order, and the errors it reported;
-- failing: a path whose include raises, as a module failing at load.
local function clientOrder(failing)
	local order, reported = {}, {}
	local env
	env = setmetatable({
		GM = { FolderName = "sandcastle" },
		CLIENT = true, SERVER = false,
		DeriveGamemode = function() end,
		ErrorNoHaltWithStack = function(err) reported[#reported + 1] = err end,
		file = { Find = function(pattern) return listing(pattern:match("ws/(%w+_)%*")) end },
		include = function(path)
			if path == "shared.lua" then
				setfenv(assert(loadfile(ROOT .. path)), env)()
				return
			end
			order[#order + 1] = path
			if path == failing then error(path .. ": failed at load") end
		end,
	}, { __index = _G })
	setfenv(assert(loadfile(ROOT .. "cl_init.lua")), env)()
	return order, reported
end

local function indexOf(order, path)
	for i, p in ipairs(order) do
		if p == path then return i end
	end
end

-- Every module whose source uses pattern loads after definer.
local function loadsAfter(definer, pattern)
	local order = clientOrder()
	local at = indexOf(order, definer)
	T.eq(at ~= nil, true, definer .. " is loaded")
	for i, path in ipairs(order) do
		if path ~= definer and source(path):find(pattern) then
			T.eq(i > at, true, path .. " loads after " .. definer)
		end
	end
end

T.test("every module using WS.UI loads after cl_ui defines it", function()
	loadsAfter("ws/cl_ui.lua", "WS%.UI%.")
end)

T.test("every module using WS.TFHud loads after cl_tf_hud defines it", function()
	loadsAfter("ws/cl_tf_hud.lua", "WS%.TFHud")
end)

-- What the player hears and sees of their own hits is the last thing to
-- fail: it loads before any HUD module and draws on none of the HUD's.
local FEEDBACK = { "ws/cl_hits.lua" }
local HUD_PARTS = { "WS%.HUD[:%.]", "WS%.TFHud", "WS%.UI%." }

T.test("the player's feedback loads before every module of the HUD", function()
	local order = clientOrder()
	for _, feedback in ipairs(FEEDBACK) do
		local at = indexOf(order, feedback)
		T.eq(at ~= nil, true, feedback .. " is loaded")
		for i, path in ipairs(order) do
			for _, part in ipairs(HUD_PARTS) do
				if path:find("^ws/cl_") and path ~= feedback and source(path):find(part) then
					T.eq(at < i, true, feedback .. " loads before " .. path)
				end
			end
		end
	end
end)

T.test("the player's feedback reads nothing of the HUD", function()
	for _, feedback in ipairs(FEEDBACK) do
		for _, part in ipairs(HUD_PARTS) do
			T.eq(source(feedback):find(part), nil, feedback .. " uses no " .. part)
		end
	end
end)

T.test("a module failing at load is reported and every other still loads", function()
	local all = clientOrder()
	for _, failing in ipairs({ "ws/cl_ui.lua", "ws/cl_freeze_panel.lua", all[#all] }) do
		local order, reported = clientOrder(failing)
		T.eq(#order, #all, failing .. " failing: every module still included")
		T.eq(#reported, 1, failing .. " failing: reported once")
		T.eq(tostring(reported[1]):find(failing, 1, true) ~= nil, true, "the report names it")
	end
end)

T.finish()
