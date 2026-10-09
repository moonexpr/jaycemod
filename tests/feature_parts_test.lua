-- foundation.features runs a feature's sv.lua or cl.lua and refuses one
-- that returns no table ("returned nil, not its table"): every such part
-- ends by returning it. Found by a client joining a payload map.
local T = dofile("tests/harness.lua")

local FEATURES = "addon/gamemodes/sandcastle/gamemode/features"

local function LastLine(path)
	local last
	for line in io.lines(path) do
		if line:match("%S") then last = line end
	end
	return last
end

T.test("every feature's own part ends by returning its table", function()
	local list = assert(io.popen("find " .. FEATURES .. " -name sv.lua -o -name cl.lua"))
	local count = 0
	for path in list:lines() do
		count = count + 1
		T.eq(LastLine(path):match("^return [%w_{]") ~= nil, true, path)
	end
	list:close()
	T.eq(count > 10, true, "found the features' parts")
end)

T.finish()
