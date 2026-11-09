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
ENT.DefaultRelationship = D_HT

local PlayerModels = WS.PlayerModels

-- Every model a kind may wear.
local function KindModels(kind, profile)
	local category = Profiles.MODEL_CATEGORIES[kind]
	if not category then return { profile.Model } end

	local models = PlayerModels.For(category)
	if #models == 0 then error("NextSoldier profile " .. kind .. " has no models in category " .. category, 2) end
	return models
end

-- Loaded with the map, in both realms, so the first to spawn does not hang the game.
local precached = {}
local function Precache(models)
	for _, model in ipairs(models) do
		if not precached[model] then
			util.PrecacheModel(model)
			precached[model] = true
		end
	end
end
for kind, profile in pairs(Profiles.PROFILES) do
	Precache(KindModels(kind, profile))
end
Precache(PlayerModels.For(PlayerModels.TERRORIST))
Precache(PlayerModels.For(PlayerModels.COUNTER_TERRORISTS))

if SERVER then
	-- Before it spawns: its kind's profile over the base's fields, and its
	-- kind for clients too (WS.SoldierKind).
	function ENT:NSProfile(kind)
		local profile = Profiles.PROFILES[kind]
		if not profile then error("no NextSoldier profile " .. tostring(kind), 2) end
		for key, value in pairs(profile) do self[key] = value end
		local category = Profiles.MODEL_CATEGORIES[kind]
		if category then self.Model = PlayerModels.Pick(category) end
		self:SetNW2String("NSKind", kind)
	end
end

WS.WarSoldier(ENT)
