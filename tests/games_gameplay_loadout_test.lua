-- games.gameplay.loadout: a player's five weapon slots, the weapons they own,
-- and the store's catalog the slots are filled from.
local T = dofile("tests/harness.lua")
local Loadout = T.require("games.gameplay.loadout")
local Transaction = T.require("foundation.transaction")

local function Catalog()
	return Loadout.NewCatalog({
		{
			class = "smg",
			name = "SMG",
			kind = Loadout.KIND_PRIMARY,
			price = Loadout.PRICE,
			starter = true,
		},
		{
			class = "shotgun",
			name = "Shotgun",
			kind = Loadout.KIND_PRIMARY,
			price = Loadout.PRICE,
		},
		{
			class = "pistol",
			name = "Pistol",
			kind = Loadout.KIND_SECONDARY,
			price = Loadout.PRICE,
			starter = true,
		},
		{
			class = "crowbar",
			name = "Crowbar",
			kind = Loadout.KIND_MELEE,
			price = Loadout.PRICE,
			starter = true,
		},
		{
			class = "grenade",
			name = "Grenade",
			kind = Loadout.KIND_SUPPORT,
			price = Loadout.PRICE,
			starter = true,
		},
		{
			class = "slam",
			name = "SLAM",
			kind = Loadout.KIND_SUPPORT,
			price = Loadout.PRICE,
		},
		{
			class = "rpg",
			name = "RPG",
			kind = Loadout.KIND_SUPPORT,
			price = Loadout.PRICE,
		},
	})
end

local function Refusal(fn, ...)
	local ok, err = pcall(fn, ...)
	T.eq(ok, false, "refused")
	T.eq(type(err) == "table" and type(err.kind), "string", "a refusal has a kind")
	return err.kind
end

T.test("the price and the reserve ammo are tuning values", function()
	T.defined(Loadout.PRICE, "Loadout.PRICE")
	T.defined(Loadout.RESERVE_CLIPS, "Loadout.RESERVE_CLIPS")
end)

T.test("there are five slots, in order, each taking one kind", function()
	T.eq(#Loadout.SLOTS, 5)
	local order = { Loadout.SLOT_PRIMARY, Loadout.SLOT_SECONDARY, Loadout.SLOT_MELEE, Loadout.SLOT_SUPPORT1, Loadout.SLOT_SUPPORT2 }
	for i, slot in ipairs(order) do T.eq(Loadout.SLOTS[i].slot, slot, "slot " .. i) end
	T.eq(Loadout.SLOTS[Loadout.SLOT_SUPPORT1].kind, Loadout.KIND_SUPPORT)
	T.eq(Loadout.SLOTS[Loadout.SLOT_SUPPORT2].kind, Loadout.KIND_SUPPORT)
end)

T.test("the catalog finds weapons by class and lists them by kind, in order", function()
	local catalog = Catalog()
	T.eq(catalog:Weapon("shotgun").name, "Shotgun")
	local support = catalog:OfKind(Loadout.KIND_SUPPORT)
	T.eq(#support, 3)
	T.eq(support[1].class, "grenade")
	T.eq(support[3].class, "rpg")
	T.eq(Refusal(catalog.Weapon, catalog, "bfg"), Loadout.UNKNOWN_WEAPON)
end)

T.test("a catalog refuses a bad entry", function()
	T.eq(Refusal(Loadout.NewCatalog, { { class = "x", name = "X", kind = 99, price = 1 } }), Loadout.BAD_CATALOG, "unknown kind")
	T.eq(Refusal(Loadout.NewCatalog, { { class = "x", name = "X", kind = Loadout.KIND_MELEE, price = -1 } }), Loadout.BAD_CATALOG, "negative price")
	local twice = {
		class = "x",
		name = "X",
		kind = Loadout.KIND_MELEE,
		price = 1,
	}
	T.eq(Refusal(Loadout.NewCatalog, { twice, twice }), Loadout.BAD_CATALOG, "a class twice")
end)

T.test("a new player owns the starters, each in a slot that takes it", function()
	local catalog = Catalog()
	local loadout = Loadout.Starting(catalog)
	T.eq(loadout:Owns(catalog:Weapon("smg")), true)
	T.eq(loadout:Owns(catalog:Weapon("shotgun")), false)
	T.eq(loadout:Equipped(Loadout.SLOT_PRIMARY).class, "smg")
	T.eq(loadout:Equipped(Loadout.SLOT_SECONDARY).class, "pistol")
	T.eq(loadout:Equipped(Loadout.SLOT_MELEE).class, "crowbar")
	T.eq(loadout:Equipped(Loadout.SLOT_SUPPORT1).class, "grenade")
	T.eq(loadout:Equipped(Loadout.SLOT_SUPPORT2), nil, "one support starter leaves the second slot empty")
end)

T.test("buying a weapon owns it and fills the first empty slot that takes it", function()
	local catalog = Catalog()
	local before = Loadout.Starting(catalog)
	local after = before:Buy(catalog:Weapon("slam"))
	T.eq(after:Owns(catalog:Weapon("slam")), true)
	T.eq(after:Equipped(Loadout.SLOT_SUPPORT2).class, "slam")
	T.eq(before:Owns(catalog:Weapon("slam")), false, "a loadout is a value: buying returns a new one")
end)

T.test("buying into a full slot owns the weapon and leaves the slot alone", function()
	local catalog = Catalog()
	local after = Loadout.Starting(catalog):Buy(catalog:Weapon("shotgun"))
	T.eq(after:Owns(catalog:Weapon("shotgun")), true)
	T.eq(after:Equipped(Loadout.SLOT_PRIMARY).class, "smg")
end)

T.test("buying a weapon already owned is refused", function()
	local catalog = Catalog()
	local loadout = Loadout.Starting(catalog)
	T.eq(Refusal(loadout.Buy, loadout, catalog:Weapon("smg")), Loadout.ALREADY_OWNED)
end)

T.test("buying into a slot owns the weapon and puts it in that slot, even a full one", function()
	local catalog = Catalog()
	local after = Loadout.Starting(catalog):BuyInto(Loadout.SLOT_PRIMARY, catalog:Weapon("shotgun"))
	T.eq(after:Owns(catalog:Weapon("shotgun")), true)
	T.eq(after:Equipped(Loadout.SLOT_PRIMARY).class, "shotgun")
	T.eq(after:Owns(catalog:Weapon("smg")), true, "the weapon it replaced is still owned")
end)

T.test("buying into the second support slot leaves the first alone", function()
	local catalog = Catalog()
	local after = Loadout.Starting(catalog):BuyInto(Loadout.SLOT_SUPPORT2, catalog:Weapon("rpg"))
	T.eq(after:Equipped(Loadout.SLOT_SUPPORT1).class, "grenade")
	T.eq(after:Equipped(Loadout.SLOT_SUPPORT2).class, "rpg")
end)

T.test("buying into a slot that does not take the weapon is refused and buys nothing", function()
	local catalog = Catalog()
	local loadout = Loadout.Starting(catalog)
	T.eq(Refusal(loadout.BuyInto, loadout, Loadout.SLOT_MELEE, catalog:Weapon("shotgun")), Loadout.WRONG_SLOT)
	T.eq(loadout:Owns(catalog:Weapon("shotgun")), false)
	T.eq(Refusal(loadout.BuyInto, loadout, Loadout.SLOT_PRIMARY, catalog:Weapon("smg")), Loadout.ALREADY_OWNED)
end)

T.test("equipping puts an owned weapon in a slot that takes it", function()
	local catalog = Catalog()
	local loadout = Loadout.Starting(catalog):Buy(catalog:Weapon("shotgun")):Equip(Loadout.SLOT_PRIMARY, catalog:Weapon("shotgun"))
	T.eq(loadout:Equipped(Loadout.SLOT_PRIMARY).class, "shotgun")
	T.eq(loadout:Owns(catalog:Weapon("smg")), true, "the weapon it replaced is still owned")
end)

T.test("equipping a weapon not owned is refused", function()
	local catalog = Catalog()
	local loadout = Loadout.Starting(catalog)
	T.eq(Refusal(loadout.Equip, loadout, Loadout.SLOT_PRIMARY, catalog:Weapon("shotgun")), Loadout.NOT_OWNED)
end)

T.test("equipping into a slot of another kind is refused", function()
	local catalog = Catalog()
	local loadout = Loadout.Starting(catalog)
	T.eq(Refusal(loadout.Equip, loadout, Loadout.SLOT_MELEE, catalog:Weapon("pistol")), Loadout.WRONG_SLOT)
end)

T.test("a slot that does not exist is refused", function()
	local catalog = Catalog()
	local loadout = Loadout.Starting(catalog)
	T.eq(Refusal(loadout.Equip, loadout, 6, catalog:Weapon("smg")), Loadout.UNKNOWN_SLOT)
	T.eq(Refusal(loadout.Clear, loadout, 0), Loadout.UNKNOWN_SLOT)
end)

T.test("a support weapon moves between the support slots, never held twice", function()
	local catalog = Catalog()
	local grenade = catalog:Weapon("grenade")
	local loadout = Loadout.Starting(catalog):Equip(Loadout.SLOT_SUPPORT2, grenade)
	T.eq(loadout:Equipped(Loadout.SLOT_SUPPORT2), grenade)
	T.eq(loadout:Equipped(Loadout.SLOT_SUPPORT1), nil)
end)

T.test("clearing a slot empties it and keeps the weapon owned", function()
	local catalog = Catalog()
	local loadout = Loadout.Starting(catalog):Clear(Loadout.SLOT_MELEE)
	T.eq(loadout:Equipped(Loadout.SLOT_MELEE), nil)
	T.eq(loadout:Owns(catalog:Weapon("crowbar")), true)
end)

T.test("the weapons for a slot are the owned ones that fit it, in catalog order", function()
	local catalog = Catalog()
	local loadout = Loadout.Starting(catalog):Buy(catalog:Weapon("rpg")):Buy(catalog:Weapon("shotgun"))
	local support = loadout:Choices(Loadout.SLOT_SUPPORT2)
	T.eq(#support, 2)
	T.eq(support[1].class, "grenade")
	T.eq(support[2].class, "rpg")
	T.eq(#loadout:Choices(Loadout.SLOT_PRIMARY), 2)
end)

T.test("a weapon picked with no slot goes to the first empty slot that takes it", function()
	local catalog = Catalog()
	local loadout = Loadout.Starting(catalog):Buy(catalog:Weapon("rpg")):Clear(Loadout.SLOT_SUPPORT1)
	T.eq(loadout:SlotFor(catalog:Weapon("rpg")), Loadout.SLOT_SUPPORT2, "it already holds the rpg")
	loadout = loadout:Clear(Loadout.SLOT_SUPPORT2)
	T.eq(loadout:SlotFor(catalog:Weapon("grenade")), Loadout.SLOT_SUPPORT1, "the first empty")
end)

T.test("a weapon picked with no slot replaces the first that takes it when all are full", function()
	local catalog = Catalog()
	local loadout = Loadout.Starting(catalog):Buy(catalog:Weapon("shotgun"))
	T.eq(loadout:SlotFor(catalog:Weapon("shotgun")), Loadout.SLOT_PRIMARY)
	loadout = loadout:Buy(catalog:Weapon("slam")):Buy(catalog:Weapon("rpg"))
	T.eq(loadout:SlotFor(catalog:Weapon("rpg")), Loadout.SLOT_SUPPORT1, "both support slots full")
end)

T.test("a loadout survives its state round trip", function()
	local catalog = Catalog()
	local loadout = Loadout.Starting(catalog):Buy(catalog:Weapon("rpg")):Equip(Loadout.SLOT_SUPPORT1, catalog:Weapon("rpg"))
	local owned, equipped = loadout:State()
	local back = Loadout.FromState(catalog, owned, equipped)
	for _, s in ipairs(Loadout.SLOTS) do
		T.eq(back:Equipped(s.slot), loadout:Equipped(s.slot), "slot " .. s.slot)
	end
	T.eq(back:Owns(catalog:Weapon("rpg")), true)
	T.eq(back:Owns(catalog:Weapon("slam")), false)
end)

T.test("a state that breaks the rules is refused", function()
	local catalog = Catalog()
	local equipped = { {
		slot = Loadout.SLOT_PRIMARY,
		weapon = "shotgun",
	} }
	T.eq(Refusal(Loadout.FromState, catalog, { "smg" }, equipped), Loadout.NOT_OWNED)
	T.eq(Refusal(Loadout.FromState, catalog, { "bfg" }, {}), Loadout.UNKNOWN_WEAPON)
end)

T.test("only the model's own refusals count as the player's mistake", function()
	local catalog = Catalog()
	local loadout = Loadout.Starting(catalog)
	local _, refusal = pcall(loadout.Buy, loadout, catalog:Weapon("smg"))
	T.eq(refusal.kind, Loadout.ALREADY_OWNED)
	T.eq(Loadout.Refused(refusal), true)
	T.eq(Loadout.Refused("attempt to index a nil value"), false)
end)

T.test("an events-style error, or any table without the refusal marker, is our bug", function()
	T.eq(Loadout.Refused({
		kind = Loadout.UNKNOWN_WEAPON,
		message = "bfg",
	}), false, "an events.lua error with a player's kind")
	T.eq(Loadout.Refused({
		kind = Loadout.UNKNOWN_WEAPON,
		detail = "bfg",
	}), false, "no marker")
end)

T.test("a bad catalog is the content's mistake, not the player's", function()
	local _, err = pcall(Loadout.NewCatalog, { { class = "x", name = "X", kind = 99, price = 1 } })
	T.eq(err.kind, Loadout.BAD_CATALOG)
	T.eq(Loadout.Refused(err), false)
end)

T.test("a refusal reads as it did: its kind, then its detail", function()
	local catalog = Catalog()
	local _, err = pcall(catalog.Weapon, catalog, "bfg")
	T.eq(Transaction.Message(err), "unknown weapon: bfg")
	local loadout = Loadout.Starting(catalog)
	_, err = pcall(loadout.Equip, loadout, Loadout.SLOT_MELEE, catalog:Weapon("pistol"))
	T.eq(Transaction.Message(err), "wrong slot: pistol in slot 3")
end)

T.test("a slot holds a weapon by class", function()
	local catalog = Catalog()
	local loadout = Loadout.Starting(catalog)
	T.eq(loadout:Holds(Loadout.SLOT_PRIMARY, catalog:Weapon("smg")), true)
	T.eq(loadout:Holds(Loadout.SLOT_PRIMARY, Catalog():Weapon("smg")), true, "an entry of a rebuilt catalog")
	T.eq(loadout:Holds(Loadout.SLOT_PRIMARY, catalog:Weapon("shotgun")), false)
	T.eq(loadout:Holds(Loadout.SLOT_SUPPORT2, catalog:Weapon("grenade")), false, "an empty slot")
	T.eq(loadout:Holds(Loadout.SLOT_SUPPORT2, nil), true, "nothing, in an empty slot")
	T.eq(loadout:Holds(Loadout.SLOT_PRIMARY, nil), false, "nothing, in a filled slot")
end)

T.test("a catalog rebuilt from the same weapons still matches an old loadout by class", function()
	local old = Loadout.Starting(Catalog())
	local catalog = Catalog()
	local grenade = catalog:Weapon("grenade")
	T.eq(old:SlotFor(grenade), Loadout.SLOT_SUPPORT1, "the slot already holding it")
	local moved = old:Equip(Loadout.SLOT_SUPPORT2, grenade)
	T.eq(moved:Equipped(Loadout.SLOT_SUPPORT1), nil, "never held twice")
	T.eq(moved:Equipped(Loadout.SLOT_SUPPORT2).class, "grenade")
	T.eq(Transaction.IsRefusal(select(2, pcall(old.Buy, old, catalog:Weapon("smg"))), Loadout.PLAYER), true, "an old purchase refused")
end)

T.test("a loadout made before a rerun of the model still has its refusals recognised", function()
	local catalog = Catalog()
	local before = Loadout.Starting(catalog)
	package.loaded["games.gameplay.loadout"] = nil
	local Rerun = T.require("games.gameplay.loadout")
	local _, owned = pcall(before.Buy, before, catalog:Weapon("smg"))
	T.eq(Rerun.Refused(owned), true, "already owned")
	local _, slot = pcall(before.Equip, before, 6, catalog:Weapon("smg"))
	T.eq(Rerun.Refused(slot), true, "unknown slot")
	local _, unknown = pcall(catalog.Weapon, catalog, "bfg")
	T.eq(Rerun.Refused(unknown), true, "unknown weapon, from a catalog made before the rerun")
end)

-- A live reload (never a restart) reruns the model in its table: loadouts
-- and catalogs made before it run the rerun's methods from then on.
T.test("a loadout and a catalog made before a rerun of the model run its new methods", function()
	local catalog = Catalog()
	local before = Loadout.Starting(catalog)
	package.loaded["games.gameplay.loadout"] = nil
	local Rerun = T.require("games.gameplay.loadout")
	local fresh = Rerun.Starting(Catalog())
	T.eq(before.Buy, fresh.Buy, "the loadout's methods")
	T.eq(catalog.Weapon, Rerun.NewCatalog({}).Weapon, "the catalog's methods")
end)

T.test("a resupply swaps the store weapons held for the ones equipped now", function()
	local catalog = Catalog()
	local shotgun = catalog:Weapon("shotgun")
	local loadout = Loadout.Starting(catalog):Buy(shotgun):Equip(Loadout.SLOT_PRIMARY, shotgun)
	local strip, give = loadout:Restock({ "smg", "pistol", "crowbar", "grenade", "weapon_physgun" })
	T.eq(table.concat(strip, ","), "smg", "the primary no longer equipped")
	T.eq(table.concat(give, ","), "shotgun", "the primary equipped since")
end)

T.test("a resupply leaves a loadout already held, and anything outside the store, alone", function()
	local loadout = Loadout.Starting(Catalog())
	local strip, give = loadout:Restock({ "gmod_tool", "smg", "pistol", "crowbar", "grenade", "weapon_frag" })
	T.eq(#strip, 0, "nothing to strip")
	T.eq(#give, 0, "nothing to give")
end)

T.test("a resupply gives back a weapon the player lost, in slot order", function()
	local strip, give = Loadout.Starting(Catalog()):Restock({ "crowbar" })
	T.eq(#strip, 0)
	T.eq(table.concat(give, ","), "smg,pistol,grenade", "primary, secondary, support")
end)

T.test("a resupply strips a store weapon owned but cleared from its slot", function()
	local loadout = Loadout.Starting(Catalog()):Clear(Loadout.SLOT_SUPPORT1)
	local strip, give = loadout:Restock({ "smg", "pistol", "crowbar", "grenade" })
	T.eq(table.concat(strip, ","), "grenade")
	T.eq(#give, 0)
end)

T.finish()
