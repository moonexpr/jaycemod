-- NextSoldier: the soldier itself, beside the gamemode on foundation, which
-- runs without the war's tactics engine (addons/wartactics). It loads itself
-- whole, and what it exports is its collections:
--   world       the map as a walker meets it: doors, portals, nav gaps, clips
--   body        gaze, gestures, noise, a player's body, weapons, voice
--   locomotion  routes walked, ladders, leaps, rappels, corners, detours
--   senses      sight and hearing
--   behavior    the contract behaviours keep, relations, intention, monitors
-- The mode hosting it gives what it needs through nextsoldier.host. One line a
-- file, never a loop; a collection comes after the ones its files read.
nextsoldier = nextsoldier or {}

-- The engine's own statechart, where the server has the binary (addons/nextsoldier/native):
-- nextsoldier.engine, and player.CreateNextSoldier.
if SERVER and util.IsBinaryModuleInstalled("nextsoldier") then require("nextsoldier") end

-- The live bots on this base, which others' noises reach.
nextsoldier.bots = nextsoldier.bots or setmetatable({}, { __mode = "k" })

local function Load(path)
	if SERVER then AddCSLuaFile(path) end
	include(path)
end

if SERVER then AddCSLuaFile("nextsoldier/sh_init.lua") end

Load("nextsoldier/base.lua")
Load("nextsoldier/host.lua")

Load("nextsoldier/world.lua")
Load("nextsoldier/world/doors.lua")
Load("nextsoldier/world/portal.lua")
Load("nextsoldier/world/nav_gaps.lua")
Load("nextsoldier/world/nav_stairs.lua")

Load("nextsoldier/body/gaze.lua")
Load("nextsoldier/body/gestures.lua")
Load("nextsoldier/body/jump.lua")
Load("nextsoldier/body/noise.lua")
Load("nextsoldier/body/player_body.lua")
Load("nextsoldier/body/responserules.lua")
Load("nextsoldier/body/weapons.lua")

Load("nextsoldier/locomotion.lua")
Load("nextsoldier/locomotion/ladder.lua")
Load("nextsoldier/locomotion/leap.lua")
Load("nextsoldier/locomotion/probe.lua")
Load("nextsoldier/locomotion/reach_memo.lua")
Load("nextsoldier/locomotion/route_record.lua")
Load("nextsoldier/locomotion/route_walk.lua")

Load("nextsoldier/senses.lua")
Load("nextsoldier/senses/vision.lua")

Load("nextsoldier/behavior.lua")
Load("nextsoldier/behavior/intention.lua")
Load("nextsoldier/behavior/monitor.lua")
Load("nextsoldier/behavior/registry.lua")
Load("nextsoldier/behavior/action.lua")
Load("nextsoldier/behavior/ctfbot.lua")
Load("nextsoldier/behavior/pathfollower.lua")
-- the squad above the leggings: the seam they look up its kinds of order in first, then its radio,
-- interactions and behaviours, each registering what it adds
Load("nextsoldier/squad/orders.lua")
Load("nextsoldier/behavior/group_identity.lua")
Load("nextsoldier/behavior/gib_behaviors.lua")
Load("nextsoldier/squad/comms/radio.lua")
Load("nextsoldier/squad/interactions/director.lua")
Load("nextsoldier/squad/interactions/command.lua")
Load("nextsoldier/squad/behaviors/legs.lua")
Load("nextsoldier/squad/behaviors/assault.lua")
Load("nextsoldier/squad/behaviors/ambush.lua")
Load("nextsoldier/squad/behaviors/occupy.lua")
Load("nextsoldier/squad/behaviors/fortify.lua")
Load("nextsoldier/squad/behaviors/member.lua")
