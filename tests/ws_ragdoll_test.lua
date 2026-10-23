local T = dofile("tests/harness.lua")
local Ragdoll = T.require("ws.ragdoll")

T.test("an NPC's or NextBot's death ragdoll goes to clients", function()
	local owner = Ragdoll.OwnerKind(false, true)
	T.eq(owner, Ragdoll.OWNER_NPC, "an NPC or NextBot")
	T.eq(Ragdoll.HandsOff(owner, false, false), true, "handed off")
end)

T.test("players' ragdolls are left to the engine", function()
	local owner = Ragdoll.OwnerKind(true, false)
	T.eq(owner, Ragdoll.OWNER_PLAYER, "a player")
	T.eq(Ragdoll.HandsOff(owner, false, false), false, "left")
end)

T.test("a ragdoll with no NPC behind it is left", function()
	T.eq(Ragdoll.HandsOff(Ragdoll.OwnerKind(false, false), false, false), false, "a prop's or the world's")
end)

T.test("a ragdoll a player spawned is no death ragdoll", function()
	T.eq(Ragdoll.HandsOff(Ragdoll.OWNER_NPC, true, false), false, "spawned from the menu")
end)

T.test("a ragdoll something holds stays on the server", function()
	T.eq(Ragdoll.HandsOff(Ragdoll.OWNER_NPC, false, true), false, "held by a monster")
end)

-- DrGBase records on each ragdoll it makes the class of what it replaced.
T.test("the class an addon recorded names the owner", function()
	T.eq(Ragdoll.OwnerOfClass("npc_drg_zombie"), Ragdoll.OWNER_NPC, "a NextBot's class")
	T.eq(Ragdoll.OwnerOfClass("player"), Ragdoll.OWNER_PLAYER, "a player")
	T.eq(Ragdoll.OwnerOfClass(nil), Ragdoll.OWNER_NONE, "nothing recorded")
	T.eq(Ragdoll.OwnerOfClass(""), Ragdoll.OWNER_NONE, "an empty record")
end)

T.test("a body leaves a ragdoll unless it dissolves or the damage forbids one", function()
	T.eq(Ragdoll.LeavesBody(false, false), true, "an ordinary death")
	T.eq(Ragdoll.LeavesBody(true, false), false, "dissolving")
	T.eq(Ragdoll.LeavesBody(false, true), false, "DMG_REMOVENORAGDOLL")
end)

T.finish()
