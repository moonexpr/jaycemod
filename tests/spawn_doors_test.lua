-- features.rounds.spawn_doors: the spawn-room triggers held off while the
-- doors stand open (a halt, a win's humiliation), and which come back on.
local T = dofile("tests/harness.lua")
local SpawnDoors = T.require("features.rounds.spawn_doors")

local function Sorted(list)
	table.sort(list)
	return list
end

T.test("the triggers that were on come back on", function()
	local hold = SpawnDoors.New({ "red_a", "red_b" })
	T.eq(table.concat(Sorted(hold:ToEnable()), " "), "red_a red_b")
end)

-- Bug: on pl_goldrush cap_a_capture_relay turns RED's stage-1 spawn trigger
-- off 15s after the win, as the room becomes BLU's; the next stage's restore
-- turned it back on, and RED could open BLU's spawn door.
T.test("a trigger the map turns off while held stays off", function()
	local hold = SpawnDoors.New({ "red_a", "red_b" })
	hold:MapInput("red_a", "disable")
	T.eq(table.concat(Sorted(hold:ToEnable()), " "), "red_b")
end)

T.test("a trigger the map turns on while held stays on", function()
	local hold = SpawnDoors.New({ "red_a" })
	hold:MapInput("blue_a", "enable")
	T.eq(table.concat(Sorted(hold:ToEnable()), " "), "blue_a red_a")
end)

T.test("the map's last word on a trigger counts", function()
	local hold = SpawnDoors.New({ "red_a" })
	hold:MapInput("red_a", "disable")
	hold:MapInput("red_a", "enable")
	hold:MapInput("blue_a", "enable")
	hold:MapInput("blue_a", "disable")
	T.eq(table.concat(Sorted(hold:ToEnable()), " "), "red_a")
end)

T.test("other inputs change nothing", function()
	local hold = SpawnDoors.New({ "red_a" })
	hold:MapInput("red_a", "toggle")
	T.eq(table.concat(Sorted(hold:ToEnable()), " "), "red_a")
end)

T.finish()
