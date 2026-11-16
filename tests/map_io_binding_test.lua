-- gamemode/map_io.lua: the map being played, bound to the engine's entity
-- list and kept in step by the gamemode's hooks.
local T = dofile ("tests/harness.lua")

local SOURCE = "addons/sandcastle/gamemodes/sandcastle/gamemode/map_io.lua"

local function Entity (name, class)
	local ent = { name = name, class = class, valid = true, fired = {} }
	function ent:GetName () return self.name end
	function ent:GetClass () return self.class end
	function ent:Fire (input, param, delay, activator, caller)
		self.fired [#self.fired + 1] = { input = input, param = param, delay = delay, activator = activator, caller = caller }
	end
	return ent
end

-- The engine as the binding reads it, and the hooks it adds.
local function Engine ()
	local engine = { entities = {}, hooks = {}, world = Entity ("", "worldspawn") }
	engine.world.valid = false -- GMod's IsValid says so of the world
	engine.env = setmetatable (
		{
			include = function () end,
			ents = { GetAll = function () return engine.entities end },
			game = { GetWorld = function () return engine.world end },
			player = { GetAll = function () return {} end },
			IsValid = function (ent) return ent ~= nil and ent.valid end,
			hook = { Add = function (event, id, fn) engine.hooks [event] = fn end }
		}, { __index = _G })
	function engine:Add (name, class)
		local ent = Entity (name, class)
		self.entities [#self.entities + 1] = ent
		return ent
	end
	function engine:Load () setfenv (assert (loadfile (SOURCE)), self.env) () end
	return engine
end

-- A map of its own for each test, as a server starting has.
local function Fresh ()
	map_io.map = nil
	local engine = Engine ()
	engine:Load ()
	return engine
end

T.test ("the map being played reads the engine's entities, the world among them", function ()
	local engine = Fresh ()
	local door = engine:Add ("door_red", "func_door")
	T.eq (map_io.Named ("door_red"),                              door, "an entity by its name")
	T.eq (map_io.Map ():FindByClass ("worldspawn") [1],           nil,  "the world is not in the entity list")
	T.eq (map_io.Map ().world:IsValid (engine.world),             true, "but exists, though IsValid says not")
	T.eq (map_io.Map ().world:IsValid (Entity ("crate", "prop")), true, "as a live entity does")
	door.valid = false
	T.eq (map_io.Map ().world:IsValid (door), false, "and a removed one does not")
end)

T.test ("entities created and removed are followed without a scan of the map", function ()
	local engine = Fresh ()
	local door = engine:Add ("door_red", "func_door")
	T.eq (map_io.Named ("door_red"), door, "the first scan")
	local late = engine:Add ("door_blu", "func_door")
	T.eq (map_io.Named ("door_blu"), NULL, "not known until the engine says it was created")
	engine.hooks.OnEntityCreated (late)
	T.eq (map_io.Named ("door_blu"), late, "known once created")
	engine.hooks.EntityRemoved (late)
	T.eq (map_io.Named ("door_blu"), NULL, "gone once removed")
end)

T.test ("a map cleaned up is scanned again", function ()
	local engine = Fresh ()
	local door = engine:Add ("door_red", "func_door")
	T.eq (map_io.Named ("door_red"), door, "before")
	door.valid = false
	engine.entities = {}
	local again = engine:Add ("door_red", "func_door")
	engine.hooks.PostCleanupMap ()
	T.eq (map_io.Named ("door_red"), again, "the new entity of that name")
end)

T.test ("a recorded class's keyvalues are kept and its outputs fire, the keyvalue left as the map set it", function ()
	local engine = Fresh ()
	local point = engine:Add ("cap_a", "team_control_point")
	local relay = engine:Add ("relay", "logic_relay")
	map_io.Record ("team_control_point")
	T.eq (engine.hooks.EntityKeyValue (point, "OnCapTeam1", "relay,Trigger,,0,-1"), nil, "nothing returned")
	map_io.FireOutput (point, "OnCapTeam1", point)
	T.eq (#relay.fired,           1,         "the relay took an input")
	T.eq (relay.fired [1].input,  "Trigger", "the output's")
	T.eq (relay.fired [1].caller, point,     "from the point")
end)

T.test ("an input the engine delivers reaches the map's observers and is let through", function ()
	local engine = Fresh ()
	local track = engine:Add ("track_1", "path_track")
	local heard
	map_io.Map ():Observe (map_io.INPUT, "DisablePath", function (ent, input, param) heard = { ent, param } end)
	T.eq (engine.hooks.AcceptInput (track, "DisablePath", nil, nil, "1"), nil, "nothing returned: the engine takes it")
	T.eq (heard [1],                                                      track, "the entity")
	T.eq (heard [2],                                                      "1", "its parameter")
end)

T.test ("loading the binding again keeps the map and what it recorded", function ()
	local engine = Fresh ()
	local point = engine:Add ("cap_a", "team_control_point")
	map_io.Record ("team_control_point")
	engine.hooks.EntityKeyValue (point, "point_index", "2")
	local map = map_io.Map ()
	engine:Load ()
	T.eq (map_io.Map (),                        map,   "the same map")
	T.eq (map_io.KeyValues (point).point_index, "2",   "its keyvalues, which the engine tells only once")
	T.eq (map_io.Named ("cap_a"),               point, "still reading the engine")
end)

T.finish ()
