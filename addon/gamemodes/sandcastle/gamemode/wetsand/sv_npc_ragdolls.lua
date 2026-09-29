-- NPC death ragdolls are made only on clients, never as serverside
-- prop_ragdolls: each costs server physics while it lies there and is an
-- entity sent to every client. This file is always loaded, on every map
-- (Sandbox too), because NPCs die everywhere: it is an engine behaviour, not
-- a mode's content. Its client half is wetsand/cl_npc_ragdolls.lua, its
-- rules foundation/npc/ragdoll.lua.
--
-- One message, wetsand_npc_ragdoll_create, tells the clients that can see a
-- body to build its ragdoll, in one of two ways:
--  * a body the server still has (WETSAND.SendClientRagdoll: an AI war
--    soldier, wetsand/sh_drg_soldier.lua): clients take the pose from their
--    own copy of it and hide it; its owner removes it Ragdoll.HANDOFF later.
--  * a serverside ragdoll the engine or an addon made for a dead NPC or
--    NextBot: its pose and velocities travel in the message and it is
--    removed at once.
local Ragdoll = WETSAND.require("foundation.npc.ragdoll")

local NET = "wetsand_npc_ragdoll_create"
local BYTE_BITS = 8 -- skins, bodygroups, their values, physics objects: each under 256

util.AddNetworkString(NET)

-- The body's looks, then the force to push it with, then where the pose is.
local function Start(body, force, poseInMessage)
	net.Start(NET)
	net.WriteEntity(body)
	net.WriteString(body:GetModel())
	net.WriteUInt(body:GetSkin(), BYTE_BITS)
	local groups = body:GetNumBodyGroups()
	net.WriteUInt(groups, BYTE_BITS)
	for id = 0, groups - 1 do net.WriteUInt(body:GetBodygroup(id), BYTE_BITS) end
	net.WriteVector(force)
	net.WriteBool(poseInMessage)
end

-- A dead body the server keeps for now: clients ragdoll their copy of it,
-- pushed by force (the killing blow's).
function WETSAND.SendClientRagdoll(body, force)
	Start(body, force, false)
	net.SendPVS(body:GetPos())
end

-- A serverside ragdoll: its physics objects' poses and velocities (the
-- killing blow already in them) go to clients, and it goes.
local function HandOff(ragdoll)
	ragdoll.wetsandHandedOff = true
	local count = ragdoll:GetPhysicsObjectCount()
	Start(ragdoll, vector_origin, true)
	net.WriteUInt(count, BYTE_BITS)
	for i = 0, count - 1 do
		local phys = ragdoll:GetPhysicsObjectNum(i)
		net.WriteVector(phys:GetPos())
		net.WriteAngle(phys:GetAngles())
		net.WriteVector(phys:GetVelocity())
	end
	net.SendPVS(ragdoll:GetPos())
	ragdoll:Remove()
end

local function SpawnedByPlayer(ragdoll)
	return IsValid(ragdoll:GetCreator())
end

-- The engine's serverside ragdolls (an engine NPC while ai_serverragdolls
-- is 1; a NextBot's own BecomeRagdoll makes a clientside one while it is 0).
hook.Add("CreateEntityRagdoll", "wetsand_npc_ragdolls", function(owner, ragdoll)
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
hook.Add("OnEntityCreated", "wetsand_npc_ragdolls", function(ent)
	if ent:GetClass() ~= "prop_ragdoll" then return end
	timer.Simple(0, function()
		if not IsValid(ent) or ent.wetsandHandedOff then return end
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

hook.Add("InitPostEntity", "wetsand_drgbase_ragdoll_defaults", function()
	for name, value in pairs(DRGBASE_DEFAULTS) do
		if ConVarExists(name) then RunConsoleCommand(name, value) end
	end
end)
