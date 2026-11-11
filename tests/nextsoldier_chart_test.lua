local T = dofile ("tests/harness.lua")
local Behavior = nextsoldier.behavior

local GAMEMODE = T.ROOT

local function Code (path)
	local file = assert (io.open (path))
	local text = file:read ("*a")
	file:close ()
	return (text:gsub ("%-%-%[%[.-%]%]", ""):gsub ("%-%-[^\n]*", ""))
end

local function Lines (command)
	local list, lines = assert (io.popen (command)), {}
	for line in list:lines () do lines [#lines + 1] = line end
	list:close ()
	return lines
end

T.test ("the chart sees the soldier through the soldier port", function ()
	T.eq (Behavior.CHART.port, Behavior.PORT)
	T.eq (table.concat (Behavior.PORT:Methods (), " "), table.concat (Behavior.METHODS, " "))
end)

T.test ("a behaviour handles the chart's events and is refused any other", function ()
	local Listening = Behavior.CHART:State ("Listening")
	function Listening:OnHeard (me, pos) return self:Continue () end
	function Listening:OnInjured (me, attacker, amount) return self:Continue () end
	local Deaf = Behavior.CHART:State ("Deaf")
	T.eq (pcall (function () function Deaf:OnTeleported (me) end end), false, "an undeclared event")
end)

T.test ("every event the soldier and the war send its orders is declared", function ()
	local sent = {}
	for name in Code (GAMEMODE .. "sh_war_soldier.lua"):gmatch ('Tell%s*%(self,%s*"(On%u[%w_]*)"') do sent [name] = true end
	for _, path in ipairs (Lines ("ls " .. GAMEMODE .. "features/aiwar/*.lua")) do
		for name in Code (path):gmatch (':Event%s*%(%s*"(On%u[%w_]*)"') do sent [name] = true end
	end
	local declared = {}
	for _, name in ipairs (Behavior.EVENTS) do declared [name] = true end
	for name in pairs (sent) do T.eq (declared [name], true, name .. " is a declared event") end
	T.eq (next (sent) ~= nil, true, "events were found")
end)

T.test ("every query the soldier and the war ask its orders is declared", function ()
	local asked = {}
	for name in Code (GAMEMODE .. "sh_war_soldier.lua"):gmatch ('Ask%s*%(self,%s*"([%w_]+)"') do asked [name] = true end
	for _, path in ipairs (Lines ("ls " .. GAMEMODE .. "features/aiwar/*.lua")) do
		for name in Code (path):gmatch (':Query%s*%(%s*"([%w_]+)"') do asked [name] = true end
	end
	local declared = {}
	for _, name in ipairs (Behavior.QUERIES) do declared [name] = true end
	for name in pairs (asked) do T.eq (declared [name], true, name .. " is a declared query") end
	T.eq (next (asked) ~= nil, true, "queries were found")
end)

T.test ("no NextSoldier behaviour extends npc.nextbot's Action past the chart", function ()
	local paths = { GAMEMODE .. "features/aiwar/ns_behaviors.lua" }
	for _, dir in ipairs ({ "nextsoldier/", "wartactics/", "features/aiwar/scenario/" }) do
		for _, path in ipairs (Lines ("ls " .. T.File (dir) .. "*.lua")) do paths [#paths + 1] = path end
	end
	for _, path in ipairs (paths) do
		T.eq (Code (path):find ("Action:Extend%s*%(") == nil, true, path .. " extends Action directly")
	end
end)

T.finish ()
