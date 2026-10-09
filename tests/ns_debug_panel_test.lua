-- The Debug NextSoldier panel (wetsand/cl_ns_debug.lua) and the NPC
-- context menu (wetsand/cl_nb_menu.lua) run only commands and convars the
-- gamemode registers; the menu has a toggle for every debug layer and every
-- part of the overlay.
local T = dofile("tests/harness.lua")

local ROOT = T.ROOT
local PANEL = ROOT .. "wetsand/cl_ns_debug.lua"
local MENU = ROOT .. "wetsand/cl_nb_menu.lua"

local function ReadFile(path)
	local f = assert(io.open(path, "r"))
	local text = f:read("*a")
	f:close()
	return text
end

-- Every command and convar registered anywhere in the gamemode.
local function Registered()
	local names = {}
	local list = assert(io.popen("find " .. ROOT .. " -name '*.lua'"))
	for path in list:lines() do
		local text = ReadFile(path)
		for name in text:gmatch('concommand%.Add%(%s*"([%w_]+)"') do names[name] = true end
		for name in text:gmatch('CreateConVar%(%s*"([%w_]+)"') do names[name] = true end
		for name in text:gmatch('CreateClientConVar%(%s*"([%w_]+)"') do names[name] = true end
		-- the nbdebug commands, registered from a table of names
		for name in text:gmatch('name = "(wetsand_nb_[%w_]+)"') do names[name] = true end
		-- NextSoldier's commands, registered through AdminCommand and WarCommand
		for name in text:gmatch('AdminCommand%(%s*"([%w_]+)"') do names[name] = true end
		for name in text:gmatch('WarCommand%(%s*"([%w_]+)"') do names[name] = true end
	end
	list:close()
	return names
end

T.test("every command the panel and the menu run is registered", function()
	local panel, registered = ReadFile(PANEL) .. ReadFile(MENU), Registered()
	local count = 0
	for name in panel:gmatch('RunConsoleCommand%(%s*"([%w_]+)"') do
		count = count + 1
		T.eq(registered[name], true, name)
	end
	for name in panel:gmatch('panel:Button%(%s*"[^"]*",%s*"([%w_]+)"') do
		count = count + 1
		T.eq(registered[name], true, name)
	end
	for name in panel:gmatch('ConVarToggle%(%s*panel,%s*"[^"]*",%s*"([%w_]+)"') do
		count = count + 1
		T.eq(registered[name], true, name)
	end
	T.eq(count >= 12, true, "the panel's commands were found: " .. count)
end)

T.test("the menu toggles every part of the overlay, and the overlay reads each part", function()
	local panel = ReadFile(MENU)
	local view = ReadFile(ROOT .. "features/nbdebug/cl.lua")
	local Overlay = T.require("foundation.ns.overlay")
	T.eq(panel:find("for _, part in ipairs(Overlay.PARTS) do", 1, true) ~= nil and panel:find("Check(parts, PART_LABELS[part]", 1, true) ~= nil, true, "a toggle per part")
	for _, part in ipairs(Overlay.PARTS) do
		local constant = part:upper()
		T.eq(panel:find("[Overlay." .. constant .. "]", 1, true) ~= nil, true, "a label for " .. part)
		T.eq(view:find("Shows(Parts." .. constant .. ")", 1, true) ~= nil, true, "the overlay reads " .. part)
	end
end)

T.test("the menu toggles every debug layer, and the panel keeps only showing and clearing them all", function()
	local menu, panel = ReadFile(MENU), ReadFile(PANEL)
	local Debug = T.require("foundation.npc.debug")
	for _, layer in ipairs(Debug.LAYERS) do
		T.eq(menu:find("[Debug." .. layer .. "]", 1, true) ~= nil, true, "a label for " .. layer)
	end
	T.eq(panel:find('"Show All"', 1, true) ~= nil, true, "show all")
	T.eq(panel:find('"Clear All"', 1, true) ~= nil, true, "clear all")
	T.eq(panel:find("Toggle(", 1, true), nil, "no toggles left in the panel")
end)

T.finish()
