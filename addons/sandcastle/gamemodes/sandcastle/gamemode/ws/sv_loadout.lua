-- Loadouts' controller: every player's loadout (games.gameplay.loadout), from
-- the catalog's starters as they join until they leave, so a respawn or a
-- team change keeps it. A buy is paid through the economy
-- (ws/sv_economy.lua) only once the loadout takes the weapon. The player
-- hears their loadout (game_loadout_state) as their client loads and after each
-- change; each request is a transaction (WS.Events.Serve) whose decline goes
-- back with its refusal. On TF2 maps the
-- equipped weapons are what a player spawns with (GM:PlayerLoadout, init.lua).
local Economy = gameplay.economy
local Loadout = gameplay.loadout
local Balance = WS.require("games.gameplay.combat.weapon_balance")
local Sets = world.sets
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
	E.Fire("game_loadout_state", {
		owned = owned,
		equipped = equipped,
	}, ply)
end

-- The refusals that are the player's mistake, the loadout's and the
-- economy's; they go back to the player, and any other, our bug, is logged.
local REFUSED = Sets.Union(Loadout.PLAYER, Economy.PLAYER)

-- Serves a request as a transaction: change(work, loadout, fields, ply)
-- gives the new loadout, which is kept and published; every step done is
-- undone if a later one declines or fails.
local function Serve(name, change)
	E.Serve(name, "ws_loadout", REFUSED, function(work, fields, ply)
		local changed = change(work, Of(ply), fields, ply)
		local before = loadouts[ply]
		loadouts[ply] = changed
		work:Undo(function() loadouts[ply] = before end)
		Publish(ply)
	end)
end

-- A buy is paid only once the loadout takes the weapon, and refunded if
-- anything after the payment fails.
local function Pay(work, ply, weapon)
	WS.SpendMoney(ply, weapon.price)
	work:Undo(function() WS.RefundMoney(ply, weapon.price) end)
end

Serve("game_loadout_buy", function(work, loadout, fields, ply)
	local weapon = CATALOG:Weapon(fields.weapon)
	local bought = loadout:Buy(weapon)
	Pay(work, ply, weapon)
	return bought
end)

Serve("game_loadout_buy_into", function(work, loadout, fields, ply)
	local weapon = CATALOG:Weapon(fields.weapon)
	local bought = loadout:BuyInto(fields.slot, weapon)
	Pay(work, ply, weapon)
	return bought
end)

Serve("game_loadout_equip", function(work, loadout, fields)
	return loadout:Equip(fields.slot, CATALOG:Weapon(fields.weapon))
end)

Serve("game_loadout_clear", function(work, loadout, fields)
	return loadout:Clear(fields.slot)
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
				damage = math.Round(Balance.Damage(class, damage:GetInt())),
				pellets = pellets and pellets:GetInt() or 1, -- one pellet: a weapon without a pellet convar
			}
		end
	end
	return stats
end

E.Listen("system_client_ready", "ws_loadout", function(_, ply)
	Publish(ply)
	E.Fire("game_loadout_stats", { weapons = Stats() }, ply)
end)

-- With the economy off, everyone has the starter loadout.
local function Carried(ply)
	return WS.EconomyEnabled() and Of(ply) or Loadout.Starting(CATALOG)
end

-- A weapon with its reserve ammo.
local function Give(ply, class)
	local given = ply:Give(class)
	if IsValid(given) and given:GetPrimaryAmmoType() >= 0 then
		ply:GiveAmmo(math.max(given:GetMaxClip1(), 1) * RESERVE_CLIPS, given:GetPrimaryAmmoType(), true)
	end
end

-- The equipped weapons, slot by slot; the first is drawn.
function WS.GiveLoadout(ply)
	local first
	local loadout = Carried(ply)
	for _, s in ipairs(Loadout.SLOTS) do
		local weapon = loadout:Equipped(s.slot)
		if weapon then
			Give(ply, weapon.class)
			first = first or weapon.class
		end
	end
	if first then ply:SelectWeapon(first) end
end

-- A resupply locker's touch (func_regenerate): the store's weapons the
-- player holds become the loadout equipped now (Loadout:Restock), so a
-- change made since spawning takes effect without dying. The weapon in hand
-- stays drawn if it is still equipped, else the first equipped is.
function WS.RestockLoadout(ply)
	if not WS.EconomyEnabled() then
		GM:PlayerLoadout(ply)
		return
	end

	local held = {}
	for _, wep in ipairs(ply:GetWeapons()) do held[#held + 1] = wep:GetClass() end
	local loadout = Carried(ply)
	local strip, give = loadout:Restock(held)
	if #strip == 0 and #give == 0 then return end
	local active = ply:GetActiveWeapon()
	local activeClass = IsValid(active) and active:GetClass() or nil
	for _, class in ipairs(strip) do ply:StripWeapon(class) end
	for _, class in ipairs(give) do Give(ply, class) end
	if activeClass and ply:HasWeapon(activeClass) then return end
	for _, s in ipairs(Loadout.SLOTS) do
		local weapon = loadout:Equipped(s.slot)
		if weapon then return ply:SelectWeapon(weapon.class) end
	end
end

hook.Add("EntityRemoved", "ws_loadout", function(ent) loadouts[ent] = nil end)

-- A reload of this file tells the players already here.
for _, ply in player.Iterator() do
	if WS.IsReady(ply) then Publish(ply) end
end
