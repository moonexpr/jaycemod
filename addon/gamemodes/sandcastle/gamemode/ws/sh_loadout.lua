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

E.Define("loadout_buy", { weapon = E.String() }, {
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
