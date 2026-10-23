-- NPC death ragdolls are made only on clients, never as serverside
-- prop_ragdolls: each costs server physics while it lies there and is an
-- entity sent to every client. This file is always loaded, on every map
-- (Sandbox too), because NPCs die everywhere: it is an engine behaviour, not
-- a mode's content. Its client half is ws/cl_npc_ragdolls.lua, its
-- rules ws/ragdoll.lua.
--
-- One game event, game_npc_ragdoll_create (ws/sh_npc_ragdolls.lua), tells
-- the clients that can see a body to build its ragdoll, in one of two ways:
--  * a body the server still has (WS.SendClientRagdoll: an AI war
--    soldier, ws/sh_drg_soldier.lua): clients take the pose from their
--    own copy of it and hide it; its owner removes it Ragdoll.HANDOFF later.
--  * a serverside ragdoll the engine or an addon made for a dead NPC or
--    NextBot: its pose and velocities travel in the message and it is
--    removed at once.
local Ragdoll = WS.require("ws.ragdoll")

-- The body's looks, the force to push it with, and the pose if the
-- clients are to take it from the event, to the players whose PVS holds it.
local function Fire(body, force, pose)
	local groups = {}
	for id = 0, body:GetNumBodyGroups() - 1 do groups[id + 1] = body:GetBodygroup(id) end
	WS.Events.Fire("game_npc_ragdoll_create", {
		body = body,
		model = body:GetModel(),
		skin = body:GetSkin(),
		bodygroups = groups,
		force = force,
		pose = pose,
	}, body:GetPos())
end

-- A dead body the server keeps for now: clients ragdoll their copy of it,
-- pushed by force (the killing blow's).
function WS.SendClientRagdoll(body, force)
	Fire(body, force, nil)
end

-- A serverside ragdoll: its physics objects' poses and velocities (the
-- killing blow already in them) go to clients, and it goes.
local function HandOff(ragdoll)
	ragdoll.wsHandedOff = true
	local pose = {}
	for i = 0, ragdoll:GetPhysicsObjectCount() - 1 do
		local phys = ragdoll:GetPhysicsObjectNum(i)
		pose[i + 1] = {
			pos = phys:GetPos(),
			ang = phys:GetAngles(),
			vel = phys:GetVelocity(),
		}
	end
	Fire(ragdoll, vector_origin, pose)
	ragdoll:Remove()
end

local function SpawnedByPlayer(ragdoll)
	return IsValid(ragdoll:GetCreator())
end

-- The engine's serverside ragdolls (an engine NPC while ai_serverragdolls
-- is 1; a NextBot's own BecomeRagdoll makes a clientside one while it is 0).
hook.Add("CreateEntityRagdoll", "ws_npc_ragdolls", function(owner, ragdoll)
	local kind = Ragdoll.OwnerKind(owner:IsPlayer(), owner:IsNPC() or owner:IsNextBot())
	if Ragdoll.HandsOff(kind, SpawnedByPlayer(ragdoll), false) then HandOff(ragdoll) end
end)

-- A DrGBase grab (GrabRagdoll) holds the ragdoll through a point_drg_ragdoll.
local function Held(ragdoll)
	for _, attachment in ipairs(ents.FindByClass("point_drg_ragdoll")) do
		if attachment:GetRagdoll() == ragdoll then return true end
	end
	return false
end

-- Ragdolls an addon makes itself, which the engine's hook never hears of:
-- DrGBase's NextBots die into ents.Create("prop_ragdoll"), and DrGBase
-- records on it the class of the entity it replaced (EntityClass). Checked
-- a tick later, once the maker has set it up.
hook.Add("OnEntityCreated", "ws_npc_ragdolls", function(ent)
	if ent:GetClass() ~= "prop_ragdoll" then return end
	timer.Simple(0, function()
		if not IsValid(ent) or ent.wsHandedOff then return end
		if Ragdoll.HandsOff(Ragdoll.OwnerOfClass(ent.EntityClass), SpawnedByPlayer(ent), Held(ent)) then HandOff(ent) end
	end)
end)

-- Sandcastle's defaults for DrGBase's ragdoll convars: its serverside death
-- ragdolls (the few left: held ones) start fading 10 s after they are made,
-- over 0.3 s. DrGBase creates these convars with its entities, after the
-- gamemode loads, so they are set once the map has; only when DrGBase is
-- installed. An operator can still change them in the console afterwards.
local DRGBASE_DEFAULTS = {
	drgbase_remove_ragdolls = "10",
	drgbase_ragdoll_fadeout = "0.3",
}

hook.Add("InitPostEntity", "ws_drgbase_ragdoll_defaults", function()
	for name, value in pairs(DRGBASE_DEFAULTS) do
		if ConVarExists(name) then RunConsoleCommand(name, value) end
	end
end)
