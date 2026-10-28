local T = dofile("tests/harness.lua")
local Chart = nextsoldier.chart
local Soldier = nextsoldier.soldier

local GAMEMODE = T.ROOT

local function Code(path)
	local file = assert(io.open(path))
	local text = file:read("*a")
	file:close()
	return (text:gsub("%-%-%[%[.-%]%]", ""):gsub("%-%-[^\n]*", ""))
end

local function Lines(command)
	local list, lines = assert(io.popen(command)), {}
	for line in list:lines() do lines[#lines + 1] = line end
	list:close()
	return lines
end

T.test("the chart sees the soldier through the soldier port", function()
	T.eq(Chart.CHART.port, Soldier.PORT)
	T.eq(table.concat(Soldier.PORT:Methods(), " "), table.concat(Soldier.METHODS, " "))
end)

T.test("a behaviour handles the chart's events and is refused any other", function()
	local Listening = Chart.CHART:State("Listening")
	function Listening:OnHeard(me, pos) return self:Continue() end
	function Listening:OnInjured(me, attacker, amount) return self:Continue() end
	local Deaf = Chart.CHART:State("Deaf")
	T.eq(pcall(function() function Deaf:OnTeleported(me) end end), false, "an undeclared event")
end)

T.test("every event the soldier and the war send its orders is declared", function()
	local sent = {}
	for name in Code(GAMEMODE .. "ws/sh_war_soldier.lua"):gmatch('Tell%(self,%s*"(On%u[%w_]*)"') do sent[name] = true end
	for _, path in ipairs(Lines("ls " .. GAMEMODE .. "features/aiwar/*.lua")) do
		for name in Code(path):gmatch(':Event%(%s*"(On%u[%w_]*)"') do sent[name] = true end
	end
	local declared = {}
	for _, name in ipairs(Chart.EVENTS) do declared[name] = true end
	for name in pairs(sent) do T.eq(declared[name], true, name .. " is a declared event") end
	T.eq(next(sent) ~= nil, true, "events were found")
end)

T.test("every query the soldier and the war ask its orders is declared", function()
	local asked = {}
	for name in Code(GAMEMODE .. "ws/sh_war_soldier.lua"):gmatch('Ask%(self,%s*"([%w_]+)"') do asked[name] = true end
	for _, path in ipairs(Lines("ls " .. GAMEMODE .. "features/aiwar/*.lua")) do
		for name in Code(path):gmatch(':Query%(%s*"([%w_]+)"') do asked[name] = true end
	end
	local declared = {}
	for _, name in ipairs(Chart.QUERIES) do declared[name] = true end
	for name in pairs(asked) do T.eq(declared[name], true, name .. " is a declared query") end
	T.eq(next(asked) ~= nil, true, "queries were found")
end)

T.test("no NextSoldier behaviour extends npc.nextbot's Action past the chart", function()
	local paths = { GAMEMODE .. "features/aiwar/orders.lua" }
	for _, dir in ipairs({ "nextsoldier/", "wartactics/", "features/aiwar/scenario/" }) do
		for _, path in ipairs(Lines("ls " .. GAMEMODE .. dir .. "*.lua")) do paths[#paths + 1] = path end
	end
	for _, path in ipairs(paths) do
		T.eq(Code(path):find("Action:Extend%(") == nil, true, path .. " extends Action directly")
	end
end)

T.finish()
