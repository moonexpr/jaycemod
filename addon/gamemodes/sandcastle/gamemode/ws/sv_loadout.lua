-- Loadouts' controller: every player's loadout (foundation.loadout), from
-- the catalog's starters as they join until they leave, so a respawn or a
-- team change keeps it. A buy is paid through the economy
-- (ws/sv_economy.lua) only once the loadout takes the weapon. The player
-- hears their loadout (loadout_state) as their client loads and after each
-- change, or why a request was refused (loadout_refused). On TF2 maps the
-- equipped weapons are what a player spawns with (GM:PlayerLoadout, init.lua).
local Economy = WS.require("foundation.economy")
local Loadout = WS.require("foundation.loadout")
local Refusal = WS.require("foundation.refusal")
local E = WS.Events

local CATALOG = WS.LoadoutCatalog
local RESERVE_CLIPS = Loadout.RESERVE_CLIPS

-- Kept across a Lua refresh of this file.
WS.Loadouts = WS.Loadouts or {}
local loadouts = WS.Loadouts

local function Of(ply)
	if loadouts[ply] == nil then loadouts[ply] = Loadout.Starting(CATALOG) end
	return loadouts[ply]
end

local function Publish(ply)
	local owned, equipped = Of(ply):State()
	E.Fire("loadout_state", {
		owned = owned,
		equipped = equipped,
	}, ply)
end

-- The refusals that are the player's mistake, the loadout's and the
-- economy's; they go back to the player, and anything else, our bug, is
-- rethrown (Refusal.Explain).
local REFUSED = {}
for kind in pairs(Loadout.PLAYER) do REFUSED[kind] = true end
for kind in pairs(Economy.PLAYER) do REFUSED[kind] = true end

local function Change(ply, change)
	local ok, result = pcall(change, Of(ply))
	if not ok then
		E.Fire("loadout_refused", { reason = Refusal.Explain(result, REFUSED) }, ply)
		return
	end
	loadouts[ply] = result
	Publish(ply)
end

E.Listen("loadout_buy", "ws_loadout", function(fields, ply)
	Change(ply, function(loadout)
		local weapon = CATALOG:Weapon(fields.weapon)
		local bought = loadout:Buy(weapon)
		WS.SpendMoney(ply, weapon.price)
		return bought
	end)
end)

E.Listen("loadout_equip", "ws_loadout", function(fields, ply)
	Change(ply, function(loadout) return loadout:Equip(fields.slot, CATALOG:Weapon(fields.weapon)) end)
end)

E.Listen("loadout_clear", "ws_loadout", function(fields, ply)
	Change(ply, function(loadout) return loadout:Clear(fields.slot) end)
end)

-- Each weapon's damage on this server's skill, for the Store's tooltips; a
-- weapon with no damage, or whose skill convars this server lacks, sends none.
local function Stats()
	local stats = {}
	for class, details in SortedPairs(WS.WeaponDetails) do
		local damage = details.damage and GetConVar(details.damage)
		local pellets = details.pellets and GetConVar(details.pellets)
		if damage and (pellets or not details.pellets) then
			stats[#stats + 1] = {
				class = class,
				damage = damage:GetInt(),
				pellets = pellets and pellets:GetInt() or 1, -- one pellet: a weapon without a pellet convar
			}
		end
	end
	return stats
end

E.Listen("client_ready", "ws_loadout", function(_, ply)
	Publish(ply)
	E.Fire("loadout_stats", { weapons = Stats() }, ply)
end)

-- The equipped weapons, slot by slot, with reserve ammo; the first is drawn.
function WS.GiveLoadout(ply)
	local first
	for _, s in ipairs(Loadout.SLOTS) do
		local weapon = Of(ply):Equipped(s.slot)
		if weapon then
			local given = ply:Give(weapon.class)
			if IsValid(given) and given:GetPrimaryAmmoType() >= 0 then
				ply:GiveAmmo(math.max(given:GetMaxClip1(), 1) * RESERVE_CLIPS, given:GetPrimaryAmmoType(), true)
			end
			first = first or weapon.class
		end
	end
	if first then ply:SelectWeapon(first) end
end

hook.Add("EntityRemoved", "ws_loadout", function(ent) loadouts[ent] = nil end)

-- A reload of this file tells the players already here.
for _, ply in player.Iterator() do
	if WS.IsReady(ply) then Publish(ply) end
end
