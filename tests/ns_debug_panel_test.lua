-- The Debug NextSoldier panel (wetsand/cl_ns_debug.lua) runs only
-- commands and convars the gamemode registers, and has a toggle for every
-- part of the overlay.
local T = dofile("tests/harness.lua")

local ROOT = T.ROOT
local PANEL = ROOT .. "wetsand/cl_ns_debug.lua"

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

T.test("every command the panel runs is registered", function()
	local panel, registered = ReadFile(PANEL), Registered()
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

T.test("the panel toggles every part of the overlay, and the overlay reads each part", function()
	local panel = ReadFile(PANEL)
	local view = ReadFile(ROOT .. "features/nbdebug/cl.lua")
	local Overlay = T.require("foundation.ns.overlay")
	T.eq(panel:find("for _, part in ipairs(Overlay.PARTS) do ConVarToggle", 1, true) ~= nil, true, "a toggle per part")
	for _, part in ipairs(Overlay.PARTS) do
		local constant = part:upper()
		T.eq(panel:find("[Overlay." .. constant .. "]", 1, true) ~= nil, true, "a label for " .. part)
		T.eq(view:find("Shows(Parts." .. constant .. ")", 1, true) ~= nil, true, "the overlay reads " .. part)
	end
end)

T.finish()
