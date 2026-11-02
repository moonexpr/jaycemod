-- The NPC death ragdoll's game event, for its server half
-- (ws/sv_npc_ragdolls.lua, which fires it to the players whose PVS
-- holds the body) and its client half (ws/cl_npc_ragdolls.lua, which
-- builds the ragdoll). Always loaded, as both halves are.
local E = WS.Events
local BYTE_BITS = 8 -- skins, bodygroups, their values, physics objects: each under 256

-- The dead body and its looks (bodygroups: each group's value, from group
-- 0), the force to push it with, and the pose of each physics object when
-- the server's ragdoll is gone (absent: the client takes it from its own
-- copy of the body).
E.Define("game_npc_ragdoll_create", {
	body = E.Entity(),
	model = E.String(),
	skin = E.UInt(BYTE_BITS),
	bodygroups = E.List(E.UInt(BYTE_BITS), BYTE_BITS),
	force = E.Vector(),
	pose = E.Optional(E.List(E.Record({
		pos = E.Vector(),
		ang = E.Angle(),
		vel = E.Vector(),
	}), BYTE_BITS)),
})
