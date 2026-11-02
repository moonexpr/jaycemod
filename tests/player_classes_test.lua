local T = dofile("tests/harness.lua")

local ROOT = T.ROOT
local CLASS_FILES = {
	{ path = "player_class/player_combatant.lua", name = "player_combatant" },
	{ path = "player_class/player_sandcastle.lua", name = "player_sandcastle" },
	{ path = "player_class/player_spectator.lua", name = "player_spectator" },
}

local file = assert(io.open(ROOT .. "shared.lua"))
local shared = file:read("*a")
file:close()

T.test("shared loader includes and sends every selected player class", function()
	for _, class in ipairs(CLASS_FILES) do
		T.eq(shared:find('"' .. class.path .. '"', 1, true) ~= nil, true, class.name .. " path is listed")
	end
	T.eq(shared:find("if SERVER then AddCSLuaFile(path) end", 1, true) ~= nil, true, "sent to clients")
	T.eq(shared:find("include(path)", 1, true) ~= nil, true, "included in both realms")
end)

T.test("selected player classes register against the Sandbox class", function()
	for _, class in ipairs(CLASS_FILES) do
		local registered
		local env = setmetatable({
			DEFINE_BASECLASS = function() end,
			player_manager = {
				RegisterClass = function(name, definition, base)
					registered = { name = name, definition = definition, base = base }
				end,
			},
		}, { __index = _G })
		setfenv(assert(loadfile(ROOT .. class.path)), env)()
		T.eq(registered.name, class.name, class.path .. " class name")
		T.eq(registered.base, "player_sandbox", class.path .. " base class")
		T.eq(type(registered.definition), "table", class.path .. " class definition")
	end
end)

T.finish()
