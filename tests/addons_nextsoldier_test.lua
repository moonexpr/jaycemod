-- NextSoldier's addon (addons/nextsoldier): the soldier's modules under
-- lua/nextsoldier/, its base entities under lua/entities/, and the response
-- rules it speaks by (their GMod modules, their autorun and their scripts).
-- The gamemode loads the modules from the LUA path's root, not its own
-- folder, and keeps none of them.
local T = dofile("tests/harness.lua")

local ADDON = "addons/nextsoldier/"
local BASES = { "base_nextsoldier", "base_nextsoldier_npc", "base_nextsoldier_combat" }
local RESPONSE_RULES = {
	"lua/includes/modules/responserules.lua",
	"lua/includes/modules/responserules_script.lua",
	"lua/autorun/server/responserules.lua",
	"scripts/responserules/response_rules.txt",
	"scripts/responserules/combine.txt",
	"scripts/responserules/rebel.txt",
	"scripts/responserules/gestures.txt",
}

local function Exists(path)
	local file = io.open(path, "r")
	if file then file:close() end
	return file ~= nil
end

local function Lines(command)
	local pipe = assert(io.popen(command))
	local lines = {}
	for line in pipe:lines() do lines[#lines + 1] = line end
	pipe:close()
	return lines
end

T.test("the addon has a manifest", function()
	T.eq(Exists(ADDON .. "addon.json"), true, ADDON .. "addon.json")
end)

T.test("every nextsoldier module the index publishes is the addon's", function()
	local count = 0
	for module in pairs(T.Published.global) do
		if module:match("^nextsoldier%.") then
			count = count + 1
			T.eq(T.Path(module), ADDON .. "lua/" .. module:gsub("%.", "/") .. ".lua", module)
			T.eq(Exists(T.Path(module)), true, T.Path(module))
		end
	end
	T.eq(count > 0, true, "nextsoldier modules published")
end)

T.test("the index runs from the addon", function()
	T.eq(T.File("nextsoldier/sh_init.lua"), ADDON .. "lua/nextsoldier/sh_init.lua")
	T.eq(Exists(T.File("nextsoldier/sh_init.lua")), true, "the addon's index")
end)

T.test("the gamemode keeps no NextSoldier module", function()
	T.eq(#Lines("ls " .. T.ROOT .. "nextsoldier/ 2>/dev/null"), 0, T.ROOT .. "nextsoldier/")
end)

T.test("the base entities are the addon's, and the gamemode's no longer", function()
	for _, class in ipairs(BASES) do
		T.eq(Exists(ADDON .. "lua/entities/" .. class .. ".lua"), true, class .. " in the addon")
		T.eq(Exists("addons/sandcastle/gamemodes/sandcastle/entities/entities/" .. class .. ".lua"), false,
			class .. " out of the gamemode")
	end
end)

T.test("the response rules are merged into the addon", function()
	for _, path in ipairs(RESPONSE_RULES) do T.eq(Exists(ADDON .. path), true, path) end
	T.eq(#Lines("ls addons/responserules/ 2>/dev/null"), 0, "addons/responserules/ is gone")
	T.eq(T.Path("responserules"), ADDON .. "lua/includes/modules/responserules.lua", "GMod's require finds it")
end)

T.finish()
