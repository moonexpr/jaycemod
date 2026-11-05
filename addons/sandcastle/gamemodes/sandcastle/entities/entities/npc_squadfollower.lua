-- npc_squadfollower: a probe of the war's squads. An npc_pathfollower that the Tactical Behavior
-- Tool enlists in the running AI war (a bench war it starts, when none is), so the war's own
-- orders steer it as a soldier (its hooks, WS.WarSoldier's), its feet held: its path to where
-- they send it is planned and drawn, not walked, until the tool lets it walk.
AddCSLuaFile()

ENT.Base = "npc_pathfollower"
ENT.Type = "nextbot"
ENT.PrintName = "Squad Follower"
ENT.Category = "Sandcastle"
ENT.Spawnable = false

if CLIENT then return end

local Soldier = baseclass.Get("base_nextsoldier")

-- The base's intention, which the path follower's bench sets aside: its looks, then its idle
-- or fighting hooks, which the war's orders answer.
ENT.IntentionUpdate = Soldier.IntentionUpdate

-- No bench of its own: the war's orders are its behaviour.
function ENT:NSInitialAction() end

-- A bench war the tool started for squad followers ends with the last of them.
function ENT:OnRemove()
	Soldier.OnRemove(self)
	WS.Feature("aiwar"):EndBenchWhenEmpty(self)
end
