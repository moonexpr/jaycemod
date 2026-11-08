-- luadev_show (ulx_luadev's): what !print of one of easylua's relative names (this, we, there, trace...)
-- draws for its caller: a box and lines for each entity, a line to each position.
local T = dofile("tests/harness.lua")
-- GMod's AddCSLuaFile, which the module calls for itself as it loads.
AddCSLuaFile = function() end
local Show = T.require("luadev_show")

local function V(x, y, z) return { x = x, y = y, z = z } end

-- An entity as its methods answer: a prop unless t says it is a player, an NPC or a NextBot.
local function Entity(t)
	local e = { t = t }
	function e:IsValid() return true end
	function e:IsPlayer() return t.nick ~= nil end
	function e:Nick() return t.nick end
	function e:GetName() return t.name or "" end
	function e:GetClass() return t.class or "prop_physics" end
	function e:EntIndex() return t.index or 7 end
	function e:GetPos() return t.pos or V(10.4, -20.6, 30) end
	function e:GetAngles() return t.ang or { p = 0, y = 89.6, r = 0 } end
	function e:OBBMins() return V(-16, -16, 0) end
	function e:OBBMaxs() return V(16, 16, 72) end
	function e:IsNPC() return t.npc == true end
	function e:IsNextBot() return t.nextbot == true end
	function e:GetSequence() return 3 end
	function e:GetSequenceName() return "run_all" end
	function e:GetSequenceActivityName() return "ACT_RUN" end
	function e:GetEnemy() return t.enemy end
	function e:GetCurrentSchedule() return t.schedule end
	e.CurrentSchedule = t.snpcSchedule
	return e
end

local function Joined(lines) return table.concat(lines, "\n") end

T.defined(Show.DIR_LENGTH, "DIR_LENGTH")

T.test("an entity is described by its name, class, rounded position and angles", function()
	local text = Joined(Show.Describe(Entity({ name = "door_1", class = "func_door" }), {}))
	T.eq(text, "name: door_1\nclass: func_door\npos: 10 -21 30\nang: 0 90 0", "four lines")
end)

T.test("a player is named by its nick, an unnamed entity by its class and index", function()
	T.eq(Show.Describe(Entity({ nick = "bob", class = "player" }), {})[1], "name: bob", "a player")
	T.eq(Show.Describe(Entity({}), {})[1], "name: prop_physics#7", "unnamed")
end)

T.test("an NPC adds its activity, animation, target and engine schedule", function()
	local enemy = Entity({ nick = "bob", index = 1 })
	local text = Joined(Show.Describe(Entity({ npc = true, class = "npc_combine_s", enemy = enemy, schedule = 22 }),
		{ schedules = { [22] = "SCHED_CHASE_ENEMY" } }))
	T.eq(text:find("activity: ACT_RUN", 1, true) ~= nil, true, "activity")
	T.eq(text:find("animation: run_all", 1, true) ~= nil, true, "animation")
	T.eq(text:find("target: bob", 1, true) ~= nil, true, "target")
	T.eq(text:find("schedule: SCHED_CHASE_ENEMY", 1, true) ~= nil, true, "schedule by name")
end)

T.test("a scripted NPC's schedule is its own, and no target is none", function()
	local text = Joined(Show.Describe(Entity({ npc = true, snpcSchedule = { DebugName = "Patrol" } }), {}))
	T.eq(text:find("schedule: Patrol", 1, true) ~= nil, true, "its own")
	T.eq(text:find("target: none", 1, true) ~= nil, true, "none")
end)

T.test("a NextBot adds its activity, animation and target, and others add their own lines", function()
	local text = Joined(Show.Describe(Entity({ nextbot = true }), {
		more = function(ent, lines) lines[#lines + 1] = "behavior: Root > Idle" end,
	}))
	T.eq(text:find("activity: ACT_RUN", 1, true) ~= nil, true, "activity")
	T.eq(text:find("schedule", 1, true), nil, "no schedule")
	T.eq(text:find("behavior: Root > Idle", 1, true) ~= nil, true, "another's line")
end)

T.test("only easylua's relative names are shown", function()
	for _, name in ipairs({ "me", "this", "we", "there", "here", "trace", "dir", "wep", "veh", "phys" }) do
		T.eq(Show.RELATIVES[name], true, name)
	end
	T.eq(Show.RELATIVES["me:GetPos()"], nil, "an expression is not")
end)

local EYE = V(0, 0, 64)

T.test("an entity is a box around it with its lines", function()
	local shapes = Show.Shapes("this", Entity({ name = "x" }), EYE, {})
	T.eq(#shapes, 1, "one")
	T.eq(shapes[1].kind, "box", "a box")
	T.eq(shapes[1].mins.z .. " " .. shapes[1].maxs.z, "0 72", "its bounds")
	T.eq(shapes[1].lines[1], "name: x", "its lines")
end)

T.test("we is a box for each", function()
	T.eq(#Show.Shapes("we", { Entity({}), Entity({}) }, EYE, {}), 2, "two")
end)

T.test("a position is a line from the caller's eye to it, with where it is and how far", function()
	local shapes = Show.Shapes("there", V(300, 400, 64), EYE, {})
	T.eq(shapes[1].kind, "line", "a line")
	T.eq(shapes[1].from, EYE, "from the eye")
	T.eq(shapes[1].to.x, 300, "to it")
	T.eq(Joined(shapes[1].lines), "there: 300 400 64\ndistance: 500", "where and how far")
end)

T.test("dir is a line along the aim", function()
	local shapes = Show.Shapes("dir", V(1, 0, 0), EYE, {})
	T.eq(shapes[1].to.x, Show.DIR_LENGTH, "the aim's length")
end)

T.test("a trace is its line, and a box around what it hit", function()
	local hit = Entity({ class = "prop_physics" })
	local shapes = Show.Shapes("trace", { StartPos = EYE, HitPos = V(0, 0, 0), Entity = hit, Hit = true }, EYE, {})
	T.eq(shapes[1].kind .. " " .. shapes[2].kind, "line box", "its line and a box")
	T.eq(shapes[1].from, EYE, "from its start")
	local missed = Show.Shapes("trace", { StartPos = EYE, HitPos = V(0, 0, 0), Hit = false }, EYE, {})
	T.eq(#missed, 1, "only its line when it hit no entity")
end)

T.test("phys is a box around its entity", function()
	local ent = Entity({ name = "crate" })
	local shapes = Show.Shapes("phys", { GetEntity = function() return ent end }, EYE, {})
	T.eq(shapes[1].lines[1], "name: crate", "its entity's")
end)

T.test("nothing to show is no shapes", function()
	T.eq(#Show.Shapes("this", nil, EYE, {}), 0, "none")
end)

-- The module as a server loads it, the one side with Show, and the seconds each send carried.
local function ServerShow()
	local seconds = {}
	local saved = package.loaded.luadev_show
	package.loaded.luadev_show = nil
	local env = setmetatable({
		SERVER = true,
		IsValid = function(v) return v ~= nil and v.valid ~= false end,
		util = { AddNetworkString = function() end },
		hook = { Run = function() end },
		net = {
			Start = function() end,
			WriteFloat = function(s) seconds[#seconds + 1] = s end,
			WriteTable = function() end,
			Send = function() end,
		},
	}, { __index = _G })
	setfenv(assert(loadfile("addons/ulx_luadev/lua/includes/modules/luadev_show.lua")), env)()
	local server = package.loaded.luadev_show
	package.loaded.luadev_show = saved
	return server, seconds
end

-- A caller whose client's overlay preference is seconds.
local function Caller(seconds)
	local ply = {}
	function ply:EyePos() return EYE end
	function ply:GetInfoNum(name, default)
		if name == "cl_luadev_output_overlay" and seconds then return seconds end
		return default
	end
	return ply
end

T.test("the overlay stays as long as its caller's cl_luadev_output_overlay", function()
	local server, seconds = ServerShow()
	server.Show(Caller(7), "this", nil)
	T.eq(seconds[1], 7, "7 seconds")
end)

T.test("a caller whose overlay is 0 is sent nothing", function()
	local server, seconds = ServerShow()
	server.Show(Caller(0), "this", nil)
	T.eq(#seconds, 0, "nothing")
end)

T.test("a caller with no such preference is sent nothing", function()
	local server, seconds = ServerShow()
	server.Show(Caller(nil), "this", nil)
	T.eq(#seconds, 0, "nothing")
end)

T.test("the console is sent nothing", function()
	local server, seconds = ServerShow()
	server.Show({ valid = false }, "this", nil)
	T.eq(#seconds, 0, "nothing")
end)

T.finish()
