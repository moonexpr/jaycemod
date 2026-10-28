-- npc_nextsoldier: the AI war's soldier on NextSoldier's own base
-- (base_nextsoldier): one class, as TF2's CTFBot is, each kind of soldier a
-- profile (features.aiwar.profiles) given before it spawns, steered for the
-- war by its hooks (WS.WarSoldier).
AddCSLuaFile()

local Profiles = WS.require("features.aiwar.profiles")

ENT.Base = "base_nextsoldier"
ENT.Type = "nextbot"
ENT.PrintName = "NextSoldier"
ENT.Category = "Sandcastle"
ENT.Spawnable = false
ENT.RagdollOnDeath = false -- dies into clientside ragdolls (WS.WarSoldier)

-- Loaded with the map, in both realms, so the first to spawn does not hang the game.
for _, profile in pairs(Profiles.PROFILES) do
	for _, model in ipairs(profile.Models) do util.PrecacheModel(model) end
end

if SERVER then
	-- Before it spawns: its kind's profile over the base's fields, and its
	-- kind for clients too (WS.SoldierKind).
	function ENT:NSProfile(kind)
		local profile = Profiles.PROFILES[kind]
		if not profile then error("no NextSoldier profile " .. tostring(kind), 2) end
		for key, value in pairs(profile) do self[key] = value end
		self:SetNW2String("NSKind", kind)
	end
end

WS.WarSoldier(ENT)
