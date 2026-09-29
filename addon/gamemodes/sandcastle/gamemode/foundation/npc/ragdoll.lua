-- Which NPC bodies become ragdolls, and where: Sandcastle makes an NPC's
-- death ragdoll only on clients, never as a serverside prop_ragdoll (server
-- physics for every corpse, and an entity every client is sent). A dead NPC
-- or NextBot's body is handed to the clients that can see it, each building
-- its own ragdoll from the body's pose; a player's ragdoll, and any ragdoll
-- a player spawned or something holds, is left as it is.
module(...)

-- Whose body a ragdoll is.
OWNER_NONE, OWNER_NPC, OWNER_PLAYER = 0, 1, 2

-- The class DrGBase records on a ragdoll it made from a player
-- (ragdoll.EntityClass).
PLAYER_CLASS = "player"

-- Seconds a dead body the server still has (an AI war soldier) stays, hidden
-- on clients, once they are told to ragdoll it: long enough for the message
-- to reach them while they still have the body to take the pose from.
HANDOFF = 0.3

function OwnerKind(isPlayer, isNpcOrNextBot)
	if isPlayer then return OWNER_PLAYER end
	if isNpcOrNextBot then return OWNER_NPC end
	return OWNER_NONE
end

-- The owner of a ragdoll an addon made itself (not the engine), from the
-- class it recorded for the entity the ragdoll replaced; nil or "" when it
-- recorded none.
function OwnerOfClass(class)
	if class == nil or class == "" then return OWNER_NONE end
	if class == PLAYER_CLASS then return OWNER_PLAYER end
	return OWNER_NPC
end

-- Whether a serverside ragdoll is handed to clients (and removed from the
-- server): an NPC's or NextBot's, not spawned by a player, and not held (a
-- monster carrying it needs the server's physics).
function HandsOff(owner, spawnedByPlayer, held)
	return owner == OWNER_NPC and not spawnedByPlayer and not held
end

-- Whether a dying body leaves a ragdoll at all: not when it dissolves, or
-- when the damage says none (DMG_REMOVENORAGDOLL), as the engine decides.
function LeavesBody(dissolving, noRagdollDamage)
	return not dissolving and not noRagdollDamage
end
