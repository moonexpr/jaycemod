-- The superadmins' switches, the C menu's Economy and Gameplay menus
-- (ws/cl_menubar.lua; foundation.settings names who may flip them):
-- - mp_economy_enabled: 0 closes the store and hides the Loadout and Store
--   tabs; everyone spawns with the starter loadout and money stops counting
--   (ws/sv_economy.lua, ws/sv_loadout.lua, ws/cl_economy_tabs.lua).
-- - mp_economy_credit_enabled: 1 lets purchases go below $0 in every mode,
--   as Sandbox mode always does (WS.Affords, foundation.economy's Floor).
-- - ns_soldiers_enabled: 0 keeps the AI war from starting, and ends one
--   that runs (features/aiwar).
-- - tf_weapon_criticals: 0 takes the crit from every blast and projectile;
--   Sandcastle has no random crits, so this removes the map-set and boss
--   ones (features/combat).
-- - tf_use_fixed_weaponspreads: 1 puts a multi-pellet shot's pellets in
--   TF2's fixed pattern (foundation.combat.fixed_spread), here on both
--   realms so prediction agrees.
-- - mp_friendlyfire: 1 lets a player or soldier hurt its teammates, by
--   any weapon or blast (ws/sv_hits.lua, features/combat).
-- mp_tampering_enabled, sv_gameplay_disable_sandbox and sv_gameplay_enabled
-- live with what they switch (ws/sh_permissions.lua, ws/sh_gameplay.lua).
local Economy = WS.require("foundation.economy")
local PlayMode = WS.require("foundation.play_mode")
local FixedSpread = WS.require("foundation.combat.fixed_spread")
local BulletSteps = WS.require("foundation.combat.bullet_steps")

local FLAGS = { FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY }
local ECONOMY = CreateConVar("mp_economy_enabled", "1", FLAGS,
	"0: no money and no store; everyone spawns with the starter loadout", 0, 1)
local CREDIT = CreateConVar("mp_economy_credit_enabled", "0", FLAGS,
	"1: purchases may go below $0 in every mode, as they always may in Sandbox mode", 0, 1)
local SOLDIERS = CreateConVar("ns_soldiers_enabled", "1", FLAGS,
	"0: no NextSoldier soldiers; the AI war cannot start, and one running ends", 0, 1)
local CRITS = CreateConVar("tf_weapon_criticals", "1", FLAGS,
	"0: no critical hits from any blast or projectile", 0, 1)
local FRIENDLY_FIRE = CreateConVar("mp_friendlyfire", "0", FLAGS,
	"1: players and soldiers can hurt their teammates", 0, 1)
local FIXED = CreateConVar("tf_use_fixed_weaponspreads", "0", FLAGS,
	"1: a multi-pellet shot's pellets land in a fixed pattern, not at random", 0, 1)

function WS.EconomyEnabled()
	return ECONOMY:GetBool()
end

function WS.SoldiersEnabled()
	return SOLDIERS:GetBool()
end

function WS.FriendlyFire()
	return FRIENDLY_FIRE:GetBool()
end

function WS.CritsEnabled()
	return CRITS:GetBool()
end

-- How far below zero a purchase may take a balance now.
function WS.CreditFloor()
	return Economy.Floor(CREDIT:GetBool(), PlayMode.IsSandbox(WS.PlayMode()))
end

-- Whether balance covers price with the credit allowed now.
function WS.Affords(balance, price)
	return Economy.Affords(balance, price, WS.CreditFloor())
end

-- The pellets of a player's multi-pellet shot, fired one by one along the
-- fixed pattern, past the bullet steps (ws/sh_bullets.lua); the original
-- shot is suppressed.
WS.BulletSteps:Add("ws_fixed_spread", BulletSteps.PELLETS, function(ent, data)
	if not FIXED:GetBool() or not ent:IsPlayer() or (data.Num or 1) <= 1 then return end
	local spread = data.Spread or vector_origin
	local ang = data.Dir:Angle()
	local right, up = ang:Right(), ang:Up()
	for i = 1, data.Num do
		local x, y = FixedSpread.Offset(i)
		local pellet = table.Copy(data)
		pellet.Num = 1
		pellet.Spread = vector_origin
		pellet.Dir = (data.Dir + right * (x * spread.x) + up * (y * spread.y)):GetNormalized()
		WS.FireBulletsAgain(ent, pellet)
	end
	return BulletSteps.SUPPRESSED
end)

if SERVER then
	cvars.AddChangeCallback("ns_soldiers_enabled", function(_, _, new)
		if new == "0" and WS.AiWarActive() then
			local ok, why = WS.Feature("aiwar"):End()
			if not ok then print("NextSoldier: " .. why) end
		end
	end, "ws_toggles")
end
