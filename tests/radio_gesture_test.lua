-- ws/sh_radio_gesture.lua: GMod's chat gesture (base GM:GrabEarAnimation, a
-- hand to the ear) is a radio call, so only a player dressed as the Combine
-- (foundation.npc.voices: its soldiers and metrocops) makes it. Run against a
-- fake gamemode.
local T = dofile("tests/harness.lua")

local function Load()
	local grabbed = {}
	local GM = { BaseClass = {} }
	function GM.BaseClass:GrabEarAnimation(ply, plyTable)
		grabbed[#grabbed + 1] = { ply = ply, plyTable = plyTable }
	end
	local env = setmetatable({ GM = GM, WS = { require = T.require } }, { __index = _G })
	setfenv(assert(loadfile("addons/sandcastle/gamemodes/sandcastle/gamemode/ws/sh_radio_gesture.lua")), env)()
	return GM, grabbed
end

local function Player(model)
	return { GetModel = function() return model end }
end

T.test("a Combine soldier or a metrocop puts a hand to the ear, as GMod's gesture does", function()
	local GM, grabbed = Load()
	local soldier, cop, state = Player("models/player/combine_soldier.mdl"), Player("models/player/police.mdl"), {}
	GM:GrabEarAnimation(soldier, state)
	GM:GrabEarAnimation(cop)
	T.eq(#grabbed, 2)
	T.eq(grabbed[1].ply, soldier)
	T.eq(grabbed[1].plyTable, state, "the player's table passed on")
	T.eq(grabbed[2].ply, cop)
end)

T.test("a rebel, or a model with no voice, never does", function()
	local GM, grabbed = Load()
	GM:GrabEarAnimation(Player("models/player/group03/male_07.mdl"))
	GM:GrabEarAnimation(Player("models/player/alyx.mdl"))
	GM:GrabEarAnimation(Player("models/player/kleiner.mdl"))
	T.eq(#grabbed, 0)
end)

T.finish()
