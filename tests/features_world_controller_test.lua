-- features/world/sv.lua: a cleanup makes the map's doors anew, shut. In
-- Sandbox mode the world opens them again itself, from the map as the
-- cleanup left it (whichever PostCleanupMap hook runs first).
local T = dofile("tests/harness.lua")

local SOURCE = T.ROOT .. "features/world/sv.lua"
local FILTER_CLASS = "filter_activator_tfteam"
local ORIGIN = { x = 0, y = 0, z = 0 }

local function Bounds(self) return ORIGIN, ORIGIN end

local function Door(name)
	return {
		fired = {},
		GetName = function() return name end,
		GetClass = function() return "func_door" end,
		WorldSpaceAABB = Bounds,
		Fire = function(self, input) self.fired[#self.fired + 1] = input end,
	}
end

local function Trigger()
	local filter = { GetClass = function() return FILTER_CLASS end }
	return {
		WorldSpaceAABB = Bounds,
		Input = function() end,
		GetInternalVariable = function(_, name)
			if name == "m_hFilter" then return filter end
			return false
		end,
	}
end

local function Map(stopped)
	local staleDoor, freshDoor = Door("stale"), Door("fresh")
	local trigger = Trigger()
	local doors = { staleDoor }
	local hooks = {}
	local mapIO = {
		Recache = function() doors = { freshDoor } end,
		Each = function(_, class, fn)
			if class == "trigger_multiple" then fn(trigger) end
			if class == "func_door*" then
				for _, door in ipairs(doors) do fn(door) end
			end
		end,
		FindByName = function() return {} end,
	}
	local env = setmetatable({
		WS = {
			require = T.require,
			MapIO = mapIO,
			KeyValues = function() return { outputs = {} } end,
			GameplayStopped = function() return stopped end,
		},
		hook = { Add = function(event, id, fn) hooks[event .. " " .. id] = fn end },
		CurTime = function() return 0 end,
		IsValid = function(ent) return ent ~= nil end,
	}, { __index = _G })
	setfenv(assert(loadfile(SOURCE)), env)()
	return { hooks = hooks, stale = staleDoor, fresh = freshDoor }
end

local function Cleanup(map)
	map.hooks["PreCleanupMap ws_world_doors"]()
	map.hooks["PostCleanupMap ws_world_doors"]()
end

T.test("a cleanup in Sandbox mode opens the doors the cleanup made", function()
	local map = Map(true)
	Cleanup(map)
	T.eq(table.concat(map.fresh.fired, " "), "Unlock Open", "the new door")
	T.eq(#map.stale.fired, 0, "the one the cleanup removed")
end)

T.test("a cleanup in a game being played leaves the doors shut", function()
	local map = Map(false)
	Cleanup(map)
	T.eq(#map.fresh.fired, 0, "for the round to open")
end)

T.finish()
