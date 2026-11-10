-- The dev workbench's running of a Lua file again, now (sandcastle_dev_run), which dev.run and
-- dev.reload's push to clients use: where a file is in the LUA path, which realms run it, and its
-- text as a chunk that runs as the gamemode ran it.
local T = dofile("tests/harness.lua")
local Run = T.require("sandcastle_dev_run")

T.test("a repo path is its LUA path; a LUA path stays one", function()
	T.eq(Run.LuaPath("addons/sandcastle/gamemodes/wetsands/gamemode/sh_traces.lua"), "wetsands/gamemode/sh_traces.lua", "the gamemode's")
	T.eq(Run.LuaPath("addons/sandcastle/gamemodes/sandcastle/gamemode/rounds.lua"), "sandcastle/gamemode/rounds.lua", "its base's")
	T.eq(Run.LuaPath("addons/nextsoldier/lua/nextsoldier/behavior/gib_behaviors.lua"), "nextsoldier/behavior/gib_behaviors.lua", "an addon's")
	T.eq(Run.LuaPath("sandcastle/gamemode/sh_traces.lua"), "sandcastle/gamemode/sh_traces.lua", "already one")
end)

T.test("a file's realms are its name's: sv_ the server's, cl_ the clients', sh_ both", function()
	T.eq(Run.Realm("sandcastle/gamemode/sv_world.lua"), "sv", "sv_")
	T.eq(Run.Realm("sandcastle/gamemode/features/aiwar/sv.lua"), "sv", "a feature's sv")
	T.eq(Run.Realm("sandcastle/gamemode/init.lua"), "sv", "init")
	T.eq(Run.Realm("sandcastle/gamemode/cl_hud.lua"), "cl", "cl_")
	T.eq(Run.Realm("sandcastle/gamemode/features/flag/cl.lua"), "cl", "a feature's cl")
	T.eq(Run.Realm("sandcastle/gamemode/sh_traces.lua"), "sh", "sh_")
	T.eq(Run.Realm("sandcastle/gamemode/shared.lua"), "sh", "shared")
end)

T.test("an entity's, a weapon's and a module's are both realms'", function()
	T.eq(Run.Realm("sandcastle/entities/entities/npc_pathfollower.lua"), "sh", "an entity")
	T.eq(Run.Realm("sandcastle/entities/weapons/weapon_cs_ak47.lua"), "sh", "a weapon")
	T.eq(Run.Realm("sandcastle/gamemode/foundation/math/box.lua"), "sh", "foundation's")
	T.eq(Run.Realm("nextsoldier/behavior/gib_behaviors.lua"), "sh", "NextSoldier's")
	T.eq(Run.Realm("sandcastle/gamemode/features/aiwar/model.lua"), "sv", "anything else, the server's")
end)

T.test("an entity or weapon file is a script to register, by its class", function()
	local entity = Run.Script("sandcastle/entities/entities/npc_pathfollower.lua")
	T.eq(entity.kind .. " " .. entity.class, "entity npc_pathfollower", "an entity")
	local weapon = Run.Script("weapons/weapon_cs_ak47.lua")
	T.eq(weapon.kind .. " " .. weapon.class, "weapon weapon_cs_ak47", "a weapon")
	T.eq(Run.Script("sandcastle/gamemode/sh_traces.lua"), nil, "a plain file")
end)

-- Runs a wrapped chunk in an environment holding env's names, returning that environment.
local function RunIn(code, env)
	local chunk = assert(loadstring(code))
	env = setmetatable(env or {}, { __index = _G })
	setfenv(chunk, env)()
	return env
end

T.test("a file runs with GM the gamemode, as when the gamemode loaded it, and GM gone after", function()
	local env = RunIn(Run.Wrapped("SEEN = GM.Name"), { GAMEMODE = { Name = "Sandcastle" } })
	T.eq(env.SEEN, "Sandcastle", "GM was the gamemode")
	T.eq(rawget(env, "GM"), nil, "and is gone")
end)

T.test("a file's lines keep their numbers, and its error reaches the caller", function()
	local ok, err = pcall(RunIn, Run.Wrapped("local a = 1\nerror('broke here')"), { GAMEMODE = {} })
	T.eq(ok, false, "it failed")
	T.eq(err:find(":2:", 1, true) ~= nil, true, "on its own line 2: " .. tostring(err))
end)

T.test("a file that returns early still leaves GM gone", function()
	local env = RunIn(Run.Wrapped("if true then return end\nLATE = true"), { GAMEMODE = {} })
	T.eq(rawget(env, "LATE"), nil, "returned")
	T.eq(rawget(env, "GM"), nil, "GM gone")
end)

T.test("an entity file is run on a fresh ENT and registered as its class", function()
	local registered = {}
	local env = RunIn(Run.Wrapped("ENT.Base = 'base_anim'", { kind = "entity", class = "ent_probe" }), {
		GAMEMODE = {},
		scripted_ents = { Register = function(t, class) registered[class] = t end },
	})
	T.eq(registered.ent_probe.Base, "base_anim", "registered with what it set")
	T.eq(registered.ent_probe.Folder, "entities/ent_probe", "its folder")
	T.eq(rawget(env, "ENT"), nil, "ENT gone")
end)

T.test("a weapon file is run on a fresh SWEP and registered as its class", function()
	local registered = {}
	RunIn(Run.Wrapped("SWEP.PrintName = 'AK'", { kind = "weapon", class = "weapon_probe" }), {
		GAMEMODE = {},
		weapons = { Register = function(t, class) registered[class] = t end },
	})
	T.eq(registered.weapon_probe.PrintName, "AK", "registered")
	T.eq(registered.weapon_probe.Folder, "weapons/weapon_probe", "its folder")
end)

T.finish()
