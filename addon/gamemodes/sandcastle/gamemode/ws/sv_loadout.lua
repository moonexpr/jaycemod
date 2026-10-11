-- Loadouts' controller: every player's loadout (foundation.loadout), from
-- the catalog's starters as they join until they leave, so a respawn or a
-- team change keeps it. A buy is paid through the economy
-- (ws/sv_economy.lua) only once the loadout takes the weapon. The player
-- hears their loadout (loadout_state) as their client loads and after each
-- change, or why a request was refused (loadout_refused). On TF2 maps the
-- equipped weapons are what a player spawns with (GM:PlayerLoadout, init.lua).
local Economy = WS.require("foundation.economy")
local Loadout = WS.require("foundation.loadout")
local E = WS.Events

local CATALOG = WS.LoadoutCatalog
local RESERVE_CLIPS = 3 -- reserve ammo given with each weapon, in clips

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

-- The player's refusals go back to them; anything else is our bug.
local function Refused(err)
	return Loadout.Refused(err) or getmetatable(err) == Economy.InsufficientFunds
end

local function Change(ply, change)
	local ok, result = pcall(change, Of(ply))
	if not ok then
		if not Refused(result) then error(result, 0) end
		E.Fire("loadout_refused", { reason = tostring(result) }, ply)
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

E.Listen("client_ready", "ws_loadout", function(_, ply) Publish(ply) end)

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
