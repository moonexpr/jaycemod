-- base_nextbot2's SetupProfile: each bot's profile tables read through its class's to each
-- base class's, and the walk up the bases ends. GMod's base_entity is its own base
-- (ENT.Base = "base_entity"), which once held a spawn in that walk for good.
local T = dofile ("tests/harness.lua")
local FOLDER = "addons/nextsoldier/lua/entities/base_nextbot2/"

-- shared.lua as GMod runs it, ENT global, under stubs for what it reads at load.
local function LoadShared ()
	local ENT = {}
	local env = setmetatable (
		{
			ENT           = ENT,
			Vector        = function (x, y, z) return { x = x, y = y, z = z } end,
			FindMetaTable = function () return {} end,
			AddCSLuaFile  = function () end
		},
		{ __index = _G }
	)
	env.include = function (file)
		local chunk = assert (loadfile (FOLDER .. file))
		setfenv (chunk, env)
		chunk ()
	end
	env.include ("shared.lua")
	return ENT
end

local Base = LoadShared ()

-- Classes as scripted_ents stores them, GMod's own bases among them.
local classes =
{
	base_entity   = { Base = "base_entity" },
	base_nextbot2 = Base,
	npc_middle    = { Base = "base_nextbot2", LocomotionDefaults = { WalkSpeed = 75 } },
	npc_top       = { Base = "npc_middle", LocomotionDefaults = { RunSpeed = 400 } }
}
scripted_ents =
{
	GetStored = function (class)
		local t = classes [class]
		return t and { t = t }
	end
}

local function Bot (class)
	return setmetatable ({ GetClass = function () return class end }, { __index = Base })
end

T.test ("the walk ends at base_entity, its own base", function ()
	local bot = Bot ("base_nextbot2")
	bot:SetupProfile ()
	T.eq (bot.LocomotionDefaults.WalkSpeed, Base.LocomotionDefaults.WalkSpeed)
end)

T.test ("a bot's table reads its class's, then each base's", function ()
	local bot = Bot ("npc_top")
	bot:SetupProfile ()
	T.eq (bot.LocomotionDefaults.RunSpeed,  400)
	T.eq (bot.LocomotionDefaults.WalkSpeed, 75)
	T.eq (bot.NextBotDefaults.SpawnHealth,  Base.NextBotDefaults.SpawnHealth)
end)

T.test ("a change to a bot's own table leaves its class's alone", function ()
	local bot = Bot ("npc_top")
	bot:SetupProfile ()
	bot.LocomotionDefaults.RunSpeed = 1
	T.eq (classes.npc_top.LocomotionDefaults.RunSpeed, 400)
end)

T.test ("a cycle among the bases ends too", function ()
	classes.npc_loop_a = { Base = "npc_loop_b", LocomotionDefaults = { WalkSpeed = 10 } }
	classes.npc_loop_b = { Base = "npc_loop_a" }
	local bot = Bot ("npc_loop_a")
	bot:SetupProfile ()
	T.eq (bot.LocomotionDefaults.WalkSpeed, 10)
end)

T.finish ()
