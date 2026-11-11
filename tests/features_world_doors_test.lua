-- features.world.doors: the map's doors by kind (spawn, setup, round), opened
-- as the map itself opens them where it does, and the spawn-room triggers
-- held off while the doors stand open (a halt, a win's humiliation), and which
-- come back on.
local T = dofile ("tests/harness.lua")
local Doors = T.require ("features.world.doors")
local KIND = Doors.KIND

local function Output (name, target, input)
	return { name = name, target = target, input = input, param = "", delay = 0 }
end

-- arena_lumberyard's tf_logic_arena: no trigger stands at its doors, and in a
-- stopped game no arena round starts, nor its point unlocks, to open them.
local ARENA =
{
	class = "tf_logic_arena",
	outputs =
	{
		Output ("OnArenaRoundStart", "door_blue_spawn1_*", "Open"),
		Output ("OnCapEnabled", "door_middle*", "Open"),
		Output ("OnArenaRoundStart", "door_red_spawn1_*", "Open"),
		Output ("OnCapEnabled", "cap_flag", "ShowModel")
	}
}
local TIMER = { class = "team_round_timer", outputs = { Output ("OnSetupFinished", "gate_*", "Unlock"), Output ("OnSetupFinished", "relay", "Trigger") } }

local function Targets (connections)
	local list = {}
	for i, c in ipairs (connections) do list [i] = c.output.target .. "." .. c.output.input end
	table.sort (list)
	return table.concat (list, " ")
end

T.test ("the kinds are an enumeration", function ()
	T.eq (KIND.SPAWN ~= KIND.SETUP and KIND.SETUP ~= KIND.ROUND, true,    "apart")
	T.eq (KIND [KIND.ROUND],                                     "ROUND", "named")
end)

T.test ("a spawn door is opened by the map's connection that opens it as play starts", function ()
	T.eq (Targets (Doors.Plan ({ ARENA }, {}, { KIND.SPAWN }).fire), "door_blue_spawn1_*.Open door_red_spawn1_*.Open", "the arena's round start")
end)

T.test ("a round door by the one that opens it later in the round", function ()
	T.eq (Targets (Doors.Plan ({ ARENA }, {}, { KIND.ROUND }).fire), "door_middle*.Open", "the arena's point unlocking")
end)

-- A map may give its timer these at runtime (AddOutput), where no keyvalue shows them: the
-- timer's own OnSetupFinished (the rounds' FinishSetup) opens setup gates.
T.test ("a setup gate is left to its timer", function ()
	T.eq (#Doors.Plan ({ TIMER }, {}, { KIND.SETUP }).fire, 0, "nothing fired here")
end)

T.test ("every kind asked for, and only what opens", function ()
	T.eq (Targets (Doors.Plan ({ ARENA, TIMER }, {}, { KIND.SPAWN, KIND.SETUP, KIND.ROUND }).fire),
		"door_blue_spawn1_*.Open door_middle*.Open door_red_spawn1_*.Open", "no ShowModel")
	T.eq (Doors.Plan ({ ARENA }, {}, { KIND.SPAWN }).fire [1].kind, KIND.SPAWN, "each with its kind")
end)

T.test ("names match in any case, as Source's do", function ()
	local shouting = { class = "tf_logic_arena", outputs = { Output ("ONARENAROUNDSTART", "door_a", "OPEN") } }
	T.eq (#Doors.Plan ({ shouting }, {}, { KIND.SPAWN }).fire, 1, "opened")
end)

T.test ("nothing else's output of that name opens a door", function ()
	local relay = { class = "logic_relay", outputs = { Output ("OnArenaRoundStart", "door_a", "Open") } }
	T.eq (#Doors.Plan ({ relay }, {}, { KIND.SPAWN }).fire, 0, "a relay's")
end)

-- A trigger-guarded spawn door ({ key, name }) no connection opens is opened by hand.
T.test ("a guarded spawn door no connection opens is opened directly", function ()
	local guarded = { { key = "a", name = "spawn_a" }, { key = "b", name = "door_red_spawn1_1" }, { key = "c", name = "" } }
	local plan = Doors.Plan ({ ARENA }, guarded, { KIND.SPAWN })
	local keys = {}
	for i, door in ipairs (plan.open) do keys [i] = door.key end
	T.eq (table.concat (keys, " "), "a c", "not the one the arena opens")
end)

T.test ("guarded doors are spawn doors: asked for other kinds, none is opened directly", function ()
	T.eq (#Doors.Plan ({}, { { key = "a", name = "spawn_a" } }, { KIND.ROUND }).open, 0, "none")
end)

local function Sorted (list)
	table.sort (list)
	return list
end

T.test ("the triggers that were on come back on", function ()
	local hold = Doors.Hold ({ "red_a", "red_b" })
	T.eq (table.concat (Sorted (hold:ToEnable ()), " "), "red_a red_b")
end)

-- Bug: on pl_goldrush cap_a_capture_relay turns RED's stage-1 spawn trigger
-- off 15s after the win, as the room becomes BLU's; the next stage's restore
-- turned it back on, and RED could open BLU's spawn door.
T.test ("a trigger the map turns off while held stays off", function ()
	local hold = Doors.Hold ({ "red_a", "red_b" })
	hold:MapInput ("red_a", "disable")
	T.eq (table.concat (Sorted (hold:ToEnable ()), " "), "red_b")
end)

T.test ("a trigger the map turns on while held stays on", function ()
	local hold = Doors.Hold ({ "red_a" })
	hold:MapInput ("blue_a", "enable")
	T.eq (table.concat (Sorted (hold:ToEnable ()), " "), "blue_a red_a")
end)

T.test ("the map's last word on a trigger counts", function ()
	local hold = Doors.Hold ({ "red_a" })
	hold:MapInput ("red_a",  "disable")
	hold:MapInput ("red_a",  "enable")
	hold:MapInput ("blue_a", "enable")
	hold:MapInput ("blue_a", "disable")
	T.eq (table.concat (Sorted (hold:ToEnable ()), " "), "red_a")
end)

T.test ("other inputs change nothing", function ()
	local hold = Doors.Hold ({ "red_a" })
	hold:MapInput ("red_a", "toggle")
	T.eq (table.concat (Sorted (hold:ToEnable ()), " "), "red_a")
end)

T.finish ()
