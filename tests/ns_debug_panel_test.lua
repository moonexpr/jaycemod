-- The Debug NextSoldier panel (wetsand/cl_ns_debug.lua), the NPC context
-- menu (wetsand/cl_nb_menu.lua) and the AI War panel's slot list
-- (wetsand/sh_aiwar.lua, wetsand/cl_aiwar_slots.lua) run only commands and
-- convars the gamemode registers; the menu has a toggle for every debug
-- layer and every part of the overlay, and the panel a checkbox per part.
local T = dofile("tests/harness.lua")

local ROOT = T.ROOT
local PANEL = ROOT .. "wetsand/cl_ns_debug.lua"
local MENU = ROOT .. "wetsand/cl_nb_menu.lua"
local AIWAR_PANEL = ROOT .. "wetsand/sh_aiwar.lua"
local SLOT_LIST = ROOT .. "wetsand/cl_aiwar_slots.lua"

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
		-- the AI war's, through Command and SlotCommand, and its pins' from a table
		for name in text:gmatch('Command%(%s*"([%w_]+)"') do names[name] = true end
		for name in text:gmatch('(mp_aiwar_slots_[%w_]+) = {') do names[name] = true end
	end
	list:close()
	return names
end

T.test("every command the panels and the menu run is registered", function()
	local panel = ReadFile(PANEL) .. ReadFile(MENU) .. ReadFile(AIWAR_PANEL) .. ReadFile(SLOT_LIST)
	local registered = Registered()
	local count = 0
	for name in panel:gmatch('RunConsoleCommand%(%s*"([%w_]+)"') do
		count = count + 1
		T.eq(registered[name], true, name)
	end
	for name in panel:gmatch('panel:Button%(%s*"[^"]*",%s*"([%w_]+)"') do
		count = count + 1
		T.eq(registered[name], true, name)
	end
	for name in panel:gmatch('SelectedButton%(%s*panel,%s*list,%s*"[^"]*",%s*"([%w_]+)"') do
		count = count + 1
		T.eq(registered[name], true, name)
	end
	T.eq(count >= 20, true, "the panels' commands were found: " .. count)
end)

T.test("the menu toggles and the panel checks every part of the overlay, and the overlay reads each part", function()
	local menu, panel = ReadFile(MENU), ReadFile(PANEL)
	local view = ReadFile(ROOT .. "features/nbdebug/cl.lua")
	local Overlay = T.require("foundation.ns.overlay")
	T.eq(menu:find("Check(parts, Overlay.LABELS[part]", 1, true) ~= nil, true, "a toggle per part")
	T.eq(panel:find("for _, part in ipairs(Overlay.PARTS) do panel:CheckBox(Overlay.LABELS[part], Overlay.ConVar(part))", 1, true) ~= nil,
		true, "a checkbox per part")
	for _, part in ipairs(Overlay.PARTS) do
		T.eq(type(Overlay.LABELS[part]), "string", "a label for " .. part)
		T.eq(view:find("Shows(Parts." .. part:upper() .. ")", 1, true) ~= nil, true, "the overlay reads " .. part)
	end
end)

T.test("selecting an NPC for debug is its own entry beside Debug NPC, checked for the one selected", function()
	local menu = ReadFile(MENU)
	local select = menu:match('properties%.Add%("wetsand_nb_select", (%b{})%)')
	T.eq(select ~= nil, true, "its own property")
	T.eq(select:find('MenuLabel = "Select NPC for Debug"', 1, true) ~= nil, true, "named")
	T.eq(select:find('Type = "toggle"', 1, true) ~= nil, true, "a toggle")
	T.eq(menu:match('properties%.Add%("wetsand_nb_debug", (%b{})%)'):find("wetsand_nb_select", 1, true), nil, "no longer inside Debug NPC")
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
