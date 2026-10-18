-- ws/sh_nav_progress.lua on the server: every client is told the progress
-- of mp_nav_generate (its stage, and the areas made once done), nothing
-- else; each client keeps its own time. A client that loads while it runs
-- is told the stage it missed, so a player joining mid-run sees the box
-- too. Run against a fake of WS.Events.
local T = dofile("tests/harness.lua")
local P = T.require("foundation.nav_progress")

local SOURCE = "addons/sandcastle/gamemodes/sandcastle/gamemode/ws/sh_nav_progress.lua"

local function Run(s)
	local env = setmetatable({ WS = s.ws, SERVER = true }, { __index = _G })
	setfenv(assert(loadfile(SOURCE)), env)()
end

local function load()
	local s = { fired = {}, listeners = {}, defined = {} }
	local E = {
		UInt = function() return "uint" end,
		Float = function() return "float" end,
		Define = function(name, fields) s.defined[name] = fields end,
		Fire = function(name, fields, to) s.fired[#s.fired + 1] = { name = name, fields = fields, to = to } end,
		Listen = function(name, id, fn) s.listeners[name] = fn end,
	}
	s.ws = { Events = E, require = T.require }
	Run(s)
	return s
end

T.test("the event carries the progress alone, no time", function()
	local fields = {}
	for name in pairs(load().defined.game_nav_progress) do fields[#fields + 1] = name end
	table.sort(fields)
	T.eq(table.concat(fields, ","), "areas,stage")
end)

T.test("a client that loads mid-run is told the stage it missed", function()
	local s = load()
	s.ws.NavProgress(P.GENERATING)
	local joiner = {}
	s.listeners.system_client_ready({}, joiner)
	local last = s.fired[#s.fired]
	T.eq(last.to, joiner, "to the joiner alone")
	T.eq(last.fields.stage, P.GENERATING)
end)

T.test("a Lua refresh mid-run keeps the stage to tell", function()
	local s = load()
	s.ws.NavProgress(P.GENERATING)
	Run(s)
	local joiner = {}
	s.listeners.system_client_ready({}, joiner)
	T.eq(s.fired[#s.fired].to, joiner, "told after the refresh")
end)

T.test("a client that loads with nothing running, or after it is done, is told nothing", function()
	local s = load()
	s.listeners.system_client_ready({}, {})
	T.eq(#s.fired, 0, "nothing ran")
	s.ws.NavProgress(P.GENERATING)
	s.ws.NavProgress(P.DONE, 2426)
	s.listeners.system_client_ready({}, {})
	T.eq(#s.fired, 2, "only the two broadcasts")
	T.eq(s.fired[2].fields.areas, 2426)
end)

T.finish()
