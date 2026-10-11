-- foundation.loadout: a player's five weapon slots, the weapons they own,
-- and the store's catalog the slots are filled from.
local T = dofile("tests/harness.lua")
local Loadout = T.require("foundation.loadout")

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
	return getmetatable(err)
end

T.test("the price is a tuning value", function()
	T.defined(Loadout.PRICE, "Loadout.PRICE")
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
	T.eq(Refusal(catalog.Weapon, catalog, "bfg"), Loadout.UnknownWeapon)
end)

T.test("a catalog refuses a bad entry", function()
	T.eq(Refusal(Loadout.NewCatalog, { { class = "x", name = "X", kind = 99, price = 1 } }), Loadout.BadCatalog, "unknown kind")
	T.eq(Refusal(Loadout.NewCatalog, { { class = "x", name = "X", kind = Loadout.KIND_MELEE, price = -1 } }), Loadout.BadCatalog, "negative price")
	local twice = {
		class = "x",
		name = "X",
		kind = Loadout.KIND_MELEE,
		price = 1,
	}
	T.eq(Refusal(Loadout.NewCatalog, { twice, twice }), Loadout.BadCatalog, "a class twice")
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
	T.eq(Refusal(loadout.Buy, loadout, catalog:Weapon("smg")), Loadout.AlreadyOwned)
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
	T.eq(Refusal(loadout.Equip, loadout, Loadout.SLOT_PRIMARY, catalog:Weapon("shotgun")), Loadout.NotOwned)
end)

T.test("equipping into a slot of another kind is refused", function()
	local catalog = Catalog()
	local loadout = Loadout.Starting(catalog)
	T.eq(Refusal(loadout.Equip, loadout, Loadout.SLOT_MELEE, catalog:Weapon("pistol")), Loadout.WrongSlot)
end)

T.test("a slot that does not exist is refused", function()
	local catalog = Catalog()
	local loadout = Loadout.Starting(catalog)
	T.eq(Refusal(loadout.Equip, loadout, 6, catalog:Weapon("smg")), Loadout.UnknownSlot)
	T.eq(Refusal(loadout.Clear, loadout, 0), Loadout.UnknownSlot)
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
	T.eq(Refusal(Loadout.FromState, catalog, { "smg" }, equipped), Loadout.NotOwned)
	T.eq(Refusal(Loadout.FromState, catalog, { "bfg" }, {}), Loadout.UnknownWeapon)
end)

T.test("only the model's own refusals count as the player's mistake", function()
	local catalog = Catalog()
	local loadout = Loadout.Starting(catalog)
	local _, refusal = pcall(loadout.Buy, loadout, catalog:Weapon("smg"))
	T.eq(Loadout.Refused(refusal), true)
	T.eq(Loadout.Refused("attempt to index a nil value"), false)
end)

T.finish()
