-- games.world.io: entity lookups over cached name and class maps,
-- recorded output connections, and observers of outputs and inputs.
local T = dofile("tests/harness.lua")
local MapIO = T.require("games.world.io")

-- A world of plain entity tables: { name, class, valid }. It counts full
-- scans, so a test can see a lookup served from the cache, and logs fires.
local function World()
	local world = { entities = {}, scans = 0, fired = {}, players = {} }
	function world:Add(name, class)
		local ent = { name = name, class = class, valid = true }
		self.entities[#self.entities + 1] = ent
		return ent
	end
	function world:Entities()
		self.scans = self.scans + 1
		return self.entities
	end
	function world:NameOf(ent) return ent.name end
	function world:ClassOf(ent) return ent.class end
	function world:IsValid(ent) return ent ~= nil and ent.valid end
	function world:FirstPlayer() return self.players[1] end
	function world:Fire(target, input, param, delay, activator, caller)
		self.fired[#self.fired + 1] = {
			target = target,
			input = input,
			param = param,
			delay = delay,
			activator = activator,
			caller = caller,
		}
	end
	return world
end

local function Names(list)
	local names = {}
	for _, ent in ipairs(list) do names[#names + 1] = ent.name end
	return table.concat(names, ",")
end

T.test("lookups by name and class come from one scan until a recache", function()
	local world = World()
	local door = world:Add("door_red", "func_door")
	world:Add("door_blu", "func_door")
	world:Add("relay", "logic_relay")
	local io = MapIO.New(world)
	T.eq(io:FirstByName("door_red"), door, "first by name")
	T.eq(Names(io:FindByClass("func_door")), "door_red,door_blu", "by class, in map order")
	T.eq(#io:FindByName("nobody"), 0, "an unknown name finds nothing")
	T.eq(world.scans, 1, "one scan")
	io:Recache()
	io:FindByName("relay")
	T.eq(world.scans, 2, "a recache scans again")
end)

T.test("names and classes match without case, and a trailing * matches a prefix", function()
	local world = World()
	world:Add("Cap_A", "team_control_point")
	world:Add("cap_b", "team_control_point")
	world:Add("capture_zone", "trigger_capture_area")
	local io = MapIO.New(world)
	T.eq(Names(io:FindByName("CAP_A")), "Cap_A", "case")
	T.eq(Names(io:FindByName("cap_*")), "Cap_A,cap_b", "prefix")
	T.eq(#io:FindByClass("team_*"), 2, "class prefix")
end)

T.test("an empty name finds nothing", function()
	local world = World()
	world:Add("", "info_target")
	local io = MapIO.New(world)
	T.eq(#io:FindByName(""), 0, "empty")
	T.eq(io:FirstByName(""), nil, "no first")
end)

T.test("a tracked entity is indexed at the next lookup, by the name it has then", function()
	local world = World()
	local io = MapIO.New(world)
	io:Recache()
	local spawned = { name = "", class = "prop_dynamic", valid = true }
	io:Track(spawned)
	spawned.name = "statue" -- keyvalues land after creation
	T.eq(io:FirstByName("statue"), spawned, "found by its later name")
	T.eq(world.scans, 1, "no rescan")
end)

T.test("a forgotten or invalid entity is never returned", function()
	local world = World()
	local a = world:Add("crate", "prop_physics")
	local b = world:Add("crate", "prop_physics")
	local io = MapIO.New(world)
	io:Forget(a)
	T.eq(Names(io:FindByClass("prop_physics")), "crate", "one left")
	b.valid = false
	T.eq(#io:FindByName("crate"), 0, "invalid filtered")
end)

T.test("a renamed entity is found by its new name once reindexed", function()
	local world = World()
	local ent = world:Add("old", "info_target")
	local io = MapIO.New(world)
	io:FindByName("old")
	ent.name = "new"
	io:Reindex(ent)
	T.eq(#io:FindByName("old"), 0, "old name gone")
	T.eq(io:FirstByName("new"), ent, "new name")
end)

T.test("an output connection parses Hammer's comma or ESC form", function()
	local comma = MapIO.ParseOutput("OnTrigger", "door,Open,,1.5,1")
	T.eq(comma.target, "door", "target")
	T.eq(comma.input, "Open", "input")
	T.eq(comma.param, "", "empty param kept")
	T.eq(comma.delay, 1.5, "delay")
	T.eq(comma.times, 1, "times")
	local esc = MapIO.ParseOutput("OnTrigger", "relay\27Trigger\27a,b\27\27")
	T.eq(esc.param, "a,b", "ESC form keeps commas in the param")
	T.eq(esc.delay, 0, "missing delay is none")
	T.eq(esc.times, MapIO.TIMES_UNLIMITED, "missing times is unlimited")
end)

T.test("recorded keyvalues keep outputs in map order and other keys lower-cased", function()
	local world = World()
	local relay = world:Add("relay", "logic_relay")
	local io = MapIO.New(world)
	io:RecordKeyValue(relay, "Target", "door")
	io:RecordKeyValue(relay, "OnTrigger", "a,Open,,0,-1")
	io:RecordKeyValue(relay, "OnTrigger", "b,Close,,0,-1")
	local kv = io:KeyValues(relay)
	T.eq(kv.target, "door", "lower-cased key")
	T.eq(#kv.outputs, 2, "outputs")
	T.eq(kv.outputs[2].target, "b", "map order")
	T.eq(#io:KeyValues(world:Add("bare", "info_target")).outputs, 0, "no keyvalues: no outputs")
end)

T.test("firing an output fires each connection's targets, honouring !self, !activator and times", function()
	local world = World()
	local relay = world:Add("relay", "logic_relay")
	local door = world:Add("door", "func_door")
	local player = { name = "", class = "player", valid = true }
	world.players[1] = player
	local io = MapIO.New(world)
	io:RecordKeyValue(relay, "OnTrigger", "door,Open,,0.5,1")
	io:RecordKeyValue(relay, "OnTrigger", "!self,Disable,,0,-1")
	io:RecordKeyValue(relay, "OnTrigger", "!activator,SetHealth,100,0,-1")
	io:RecordKeyValue(relay, "OnTrigger", "!player,Ignite,,0,-1")
	io:RecordKeyValue(relay, "OnSpawn", "door,Close,,0,-1")
	local activator = { name = "", class = "npc", valid = true }
	io:FireOutput(relay, "OnTrigger", activator)
	T.eq(#world.fired, 4, "four connections")
	T.eq(world.fired[1].target, door, "named target")
	T.eq(world.fired[1].delay, 0.5, "delay passed")
	T.eq(world.fired[1].caller, relay, "caller passed")
	T.eq(world.fired[2].target, relay, "!self")
	T.eq(world.fired[3].target, activator, "!activator")
	T.eq(world.fired[3].param, "100", "param")
	T.eq(world.fired[4].target, player, "!player")
	world.fired = {}
	io:FireOutput(relay, "OnTrigger", activator)
	T.eq(#world.fired, 3, "the once-only connection is spent")
end)

T.test("output observers hear each output fired, in the order they subscribed", function()
	local world = World()
	local relay = world:Add("relay", "logic_relay")
	local io = MapIO.New(world)
	local heard = {}
	io:Observe(MapIO.OUTPUT, "OnTrigger", function(caller, name, activator)
		heard[#heard + 1] = "first " .. caller.name .. " " .. name .. " " .. activator
	end)
	io:Observe(MapIO.OUTPUT, "ontrigger", function() heard[#heard + 1] = "second" end)
	io:FireOutput(relay, "OnTrigger", "someone")
	T.eq(table.concat(heard, "; "), "first relay OnTrigger someone; second", "both, in order, case-free")
end)

T.test("input observers hear inputs the engine accepts, and track state from them", function()
	local world = World()
	local track = world:Add("track_1", "path_track")
	local io = MapIO.New(world)
	local disabled = {}
	io:Observe(MapIO.INPUT, "DisablePath", function(ent) disabled[ent] = true end)
	io:Observe(MapIO.INPUT, "EnablePath", function(ent) disabled[ent] = nil end)
	io:AcceptInput(track, "disablepath", "", nil, nil)
	T.eq(disabled[track], true, "disabled")
	io:AcceptInput(track, "EnablePath", "", nil, nil)
	T.eq(disabled[track], nil, "enabled")
	io:AcceptInput(track, "Unheard", "", nil, nil)
end)

T.test("an observer stops hearing once unobserved", function()
	local world = World()
	local relay = world:Add("relay", "logic_relay")
	local io = MapIO.New(world)
	local count = 0
	local id = io:Observe(MapIO.OUTPUT, "OnTrigger", function() count = count + 1 end)
	io:FireOutput(relay, "OnTrigger")
	io:Unobserve(id)
	io:FireOutput(relay, "OnTrigger")
	T.eq(count, 1, "heard once")
end)

T.test("observing an unknown kind is refused", function()
	local io = MapIO.New(World())
	T.eq(pcall(io.Observe, io, "sideways", "OnTrigger", function() end), false, "raises")
end)

T.finish()
