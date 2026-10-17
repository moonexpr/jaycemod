-- Loadouts (foundation.loadout): the store's catalog, Half-Life 2's
-- weapons by slot kind, and the events between a player's spawn menu (the
-- Player and Inventory tabs, ws/cl_loadout.lua) and the server
-- (ws/sv_loadout.lua). The server owns every loadout; a client asks to buy,
-- equip or clear, and hears its loadout back (loadout_state) or why it was
-- refused (loadout_refused).
local Loadout = WS.require("foundation.loadout")
local E = WS.Events

local PRICE = Loadout.PRICE

WS.LoadoutCatalog = Loadout.NewCatalog({
	{
		class = "weapon_smg1",
		name = "SMG",
		kind = Loadout.KIND_PRIMARY,
		price = PRICE,
		starter = true,
	},
	{
		class = "weapon_ar2",
		name = "Pulse Rifle",
		kind = Loadout.KIND_PRIMARY,
		price = PRICE,
	},
	{
		class = "weapon_shotgun",
		name = "Shotgun",
		kind = Loadout.KIND_PRIMARY,
		price = PRICE,
	},
	{
		class = "weapon_crossbow",
		name = "Crossbow",
		kind = Loadout.KIND_PRIMARY,
		price = PRICE,
	},
	{
		class = "weapon_pistol",
		name = "Pistol",
		kind = Loadout.KIND_SECONDARY,
		price = PRICE,
		starter = true,
	},
	{
		class = "weapon_357",
		name = ".357 Magnum",
		kind = Loadout.KIND_SECONDARY,
		price = PRICE,
	},
	{
		class = "weapon_crowbar",
		name = "Crowbar",
		kind = Loadout.KIND_MELEE,
		price = PRICE,
		starter = true,
	},
	{
		class = "weapon_stunstick",
		name = "Stunstick",
		kind = Loadout.KIND_MELEE,
		price = PRICE,
	},
	{
		class = "weapon_frag",
		name = "Grenade",
		kind = Loadout.KIND_SUPPORT,
		price = PRICE,
		starter = true,
	},
	{
		class = "weapon_slam",
		name = "S.L.A.M.",
		kind = Loadout.KIND_SUPPORT,
		price = PRICE,
	},
	{
		class = "weapon_rpg",
		name = "RPG",
		kind = Loadout.KIND_SUPPORT,
		price = PRICE,
	},
	{
		class = "weapon_bugbait",
		name = "Bugbait",
		kind = Loadout.KIND_SUPPORT,
		price = PRICE,
	},
})

-- What the Store's tooltip says of each weapon: its description, the skill
-- convar its damage comes from (read by the server, sent as loadout_stats),
-- and its clip, Half-Life 2's own (scripts/weapon_*.txt clip_size; nil for
-- a weapon carried one at a time). Shotgun damage is per pellet.
WS.WeaponDetails = {
	weapon_smg1 = {
		description = "Fast-firing, with a grenade launcher.",
		damage = "sk_plr_dmg_smg1",
		clip = 45,
	},
	weapon_ar2 = {
		description = "Accurate, with heavy rounds and an energy ball.",
		damage = "sk_plr_dmg_ar2",
		clip = 30,
	},
	weapon_shotgun = {
		description = "Close range. Fire both barrels at once.",
		damage = "sk_plr_dmg_buckshot",
		pellets = "sk_plr_num_shotgun_pellets",
		clip = 6,
	},
	weapon_crossbow = {
		description = "Long-range bolts. Slow to reload.",
		damage = "sk_plr_dmg_crossbow",
		clip = 1,
	},
	weapon_pistol = {
		description = "A light sidearm.",
		damage = "sk_plr_dmg_pistol",
		clip = 18,
	},
	weapon_357 = {
		description = "A hard-hitting sidearm.",
		damage = "sk_plr_dmg_357",
		clip = 6,
	},
	weapon_crowbar = {
		description = "Swings fast.",
		damage = "sk_plr_dmg_crowbar",
	},
	weapon_stunstick = {
		description = "An electrified baton.",
		damage = "sk_plr_dmg_stunstick",
	},
	weapon_frag = {
		description = "Throw it or roll it.",
		damage = "sk_plr_dmg_fraggrenade",
	},
	weapon_slam = {
		description = "A tripmine or a satchel charge.",
		damage = "sk_plr_dmg_satchel",
	},
	weapon_rpg = {
		description = "Laser-guided rockets.",
		damage = "sk_plr_dmg_rpg_round",
	},
	weapon_bugbait = {
		description = "Squeeze to call antlions; throw it to send them.",
	},
}

local WEAPON_COUNT_BITS = 6
local SLOT_BITS = 3
local REQUEST_RATE = {
	count = 10,
	seconds = 5,
}

E.Define("loadout_state", {
	owned = E.List(E.String(), WEAPON_COUNT_BITS),
	equipped = E.List(E.Record({
		slot = E.UInt(SLOT_BITS),
		weapon = E.String(),
	}), SLOT_BITS),
})

E.Define("loadout_refused", { reason = E.String() })

-- Each weapon's damage on this server's skill (WS.WeaponDetails), per hit
-- and in pellets per shot (1 but for the shotgun). Sent as a player loads.
local STAT_BITS = 12
E.Define("loadout_stats", {
	weapons = E.List(E.Record({
		class = E.String(),
		damage = E.UInt(STAT_BITS),
		pellets = E.UInt(STAT_BITS),
	}), WEAPON_COUNT_BITS),
})

E.Define("loadout_buy", { weapon = E.String() }, {
	clientSendable = true,
	rate = REQUEST_RATE,
})

-- The Loadout tab's buy on a picked slot: owns the weapon and puts it there.
E.Define("loadout_buy_into", {
	slot = E.UInt(SLOT_BITS),
	weapon = E.String(),
}, {
	clientSendable = true,
	rate = REQUEST_RATE,
})

E.Define("loadout_equip", {
	slot = E.UInt(SLOT_BITS),
	weapon = E.String(),
}, {
	clientSendable = true,
	rate = REQUEST_RATE,
})

E.Define("loadout_clear", { slot = E.UInt(SLOT_BITS) }, {
	clientSendable = true,
	rate = REQUEST_RATE,
})
