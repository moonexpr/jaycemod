-- Loadouts: a player's five weapon slots (primary, secondary, melee and two
-- support), the weapons they own, and the store's catalog both are filled
-- from. A catalog entry has a kind, and a slot takes only its own kind; the
-- two support slots take the same kind, and a weapon sits in one slot at a
-- time. A loadout is a value: Buy, Equip and Clear return a new one, or
-- raise a refusal of a named kind (foundation.transaction; Refused tells the
-- player's from our own bugs). Paying for a weapon is the controller's,
-- through the economy. Weapons are compared and kept by class, never by
-- table identity, so a catalog rebuilt from the same list still matches a
-- loadout made from the old one.
local floor, format, ipairs, pairs, setmetatable, tostring, type =
	math.floor, string.format, ipairs, pairs, setmetatable, tostring, type
local Transaction = require("foundation.transaction")
local Sets = require("foundation.world.sets")
module(...)

PRICE = 10
RESERVE_CLIPS = 3 -- reserve ammo given with each weapon at spawn, in clips

KIND_PRIMARY, KIND_SECONDARY, KIND_MELEE, KIND_SUPPORT = 1, 2, 3, 4
SLOT_PRIMARY, SLOT_SECONDARY, SLOT_MELEE, SLOT_SUPPORT1, SLOT_SUPPORT2 = 1, 2, 3, 4, 5

KINDS = {
	{
		kind = KIND_PRIMARY,
		name = "Primary",
	},
	{
		kind = KIND_SECONDARY,
		name = "Secondary",
	},
	{
		kind = KIND_MELEE,
		name = "Melee",
	},
	{
		kind = KIND_SUPPORT,
		name = "Support",
	},
}

SLOTS = {
	{
		slot = SLOT_PRIMARY,
		kind = KIND_PRIMARY,
		name = "Primary",
	},
	{
		slot = SLOT_SECONDARY,
		kind = KIND_SECONDARY,
		name = "Secondary",
	},
	{
		slot = SLOT_MELEE,
		kind = KIND_MELEE,
		name = "Melee",
	},
	{
		slot = SLOT_SUPPORT1,
		kind = KIND_SUPPORT,
		name = "Support 1",
	},
	{
		slot = SLOT_SUPPORT2,
		kind = KIND_SUPPORT,
		name = "Support 2",
	},
}

-- Refusal kinds, each read by the player as "<kind>: <detail>".
-- BAD_CATALOG is the content's mistake; the rest are the player's.
BAD_CATALOG = "bad catalog"
UNKNOWN_WEAPON = "unknown weapon"
UNKNOWN_SLOT = "unknown slot"
ALREADY_OWNED = "already owned"
NOT_OWNED = "not owned"
WRONG_SLOT = "wrong slot"

PLAYER = {
	[UNKNOWN_WEAPON] = true,
	[UNKNOWN_SLOT] = true,
	[ALREADY_OWNED] = true,
	[NOT_OWNED] = true,
	[WRONG_SLOT] = true,
}

local Raise = Transaction.Refuse

-- Whether an error is one of the player's refusals.
function Refused(err)
	return Transaction.IsRefusal(err, PLAYER)
end

local KIND_NUMBERS = {}
for i, k in ipairs(KINDS) do KIND_NUMBERS[i] = k.kind end
local KIND = Sets.Named("loadout kind", KIND_NUMBERS)

local function SlotOf(slot)
	local s = SLOTS[slot]
	if s == nil then Raise(UNKNOWN_SLOT, tostring(slot)) end
	return s
end

-------------------------------------------------------------------------------
-- Catalog

-- The class tables live on the module, so a live reload refills them and
-- catalogs and loadouts made before it run the new methods.
CatalogClass = CatalogClass or {}
local Catalog = CatalogClass
Catalog.__index = Catalog

local function Entry(e)
	if type(e.class) ~= "string" or e.class == "" then Raise(BAD_CATALOG, "an entry without a class") end
	if type(e.name) ~= "string" then Raise(BAD_CATALOG, e.class .. " has no name") end
	if not KIND:Has(e.kind) then Raise(BAD_CATALOG, e.class .. " has no known kind") end
	if type(e.price) ~= "number" or e.price < 0 or e.price ~= floor(e.price) then
		Raise(BAD_CATALOG, e.class .. " has no whole, non-negative price")
	end
	return {
		class = e.class,
		name = e.name,
		kind = e.kind,
		price = e.price,
		starter = e.starter == true,
	}
end

-- entries: { class, name, kind, price, starter }, in the store's order.
function NewCatalog(entries)
	local catalog = setmetatable({
		list = {},
		byClass = {},
	}, Catalog)
	for i, e in ipairs(entries) do
		local weapon = Entry(e)
		if catalog.byClass[weapon.class] then Raise(BAD_CATALOG, weapon.class .. " is listed twice") end
		catalog.list[i] = weapon
		catalog.byClass[weapon.class] = weapon
	end
	return catalog
end

function Catalog:Weapon(class)
	local weapon = self.byClass[class]
	if weapon == nil then Raise(UNKNOWN_WEAPON, tostring(class)) end
	return weapon
end

function Catalog:Weapons()
	return self.list
end

function Catalog:OfKind(kind)
	local found = {}
	for _, weapon in ipairs(self.list) do
		if weapon.kind == kind then found[#found + 1] = weapon end
	end
	return found
end

-------------------------------------------------------------------------------
-- Loadout

LoadoutClass = LoadoutClass or {}
local Loadout = LoadoutClass
Loadout.__index = Loadout

local function Copy(t)
	local c = {}
	for k, v in pairs(t) do c[k] = v end
	return c
end

local function New(catalog, owned, equipped)
	return setmetatable({
		catalog = catalog,
		owned = owned,
		equipped = equipped,
	}, Loadout)
end

function Fits(slot, weapon)
	return SlotOf(slot).kind == weapon.kind
end

function Loadout:Owns(weapon)
	return self.owned[weapon.class] == true
end

-- The catalog entry in the slot, or nil.
function Loadout:Equipped(slot)
	SlotOf(slot)
	local class = self.equipped[slot]
	return class and self.catalog:Weapon(class)
end

-- Whether the slot holds the weapon, matched by class; for nil, whether it
-- is empty.
function Loadout:Holds(slot, weapon)
	SlotOf(slot)
	return self.equipped[slot] == (weapon and weapon.class)
end

-- The weapons owned that the slot takes, in catalog order.
function Loadout:Choices(slot)
	local kind = SlotOf(slot).kind
	local found = {}
	for _, weapon in ipairs(self.catalog:OfKind(kind)) do
		if self:Owns(weapon) then found[#found + 1] = weapon end
	end
	return found
end

-- Where a weapon goes when no slot is named: the slot already holding it,
-- else the first empty one that takes it, else the first that takes it.
function Loadout:SlotFor(weapon)
	local empty, first
	for _, s in ipairs(SLOTS) do
		if s.kind == weapon.kind then
			if self.equipped[s.slot] == weapon.class then return s.slot end
			if empty == nil and self.equipped[s.slot] == nil then empty = s.slot end
			first = first or s.slot
		end
	end
	return empty or first
end

function Loadout:Equip(slot, weapon)
	if not Fits(slot, weapon) then Raise(WRONG_SLOT, format("%s in slot %d", weapon.class, slot)) end
	if not self:Owns(weapon) then Raise(NOT_OWNED, weapon.class) end
	local equipped = Copy(self.equipped)
	for s, held in pairs(equipped) do
		if held == weapon.class then equipped[s] = nil end
	end
	equipped[slot] = weapon.class
	return New(self.catalog, self.owned, equipped)
end

function Loadout:Clear(slot)
	SlotOf(slot)
	local equipped = Copy(self.equipped)
	equipped[slot] = nil
	return New(self.catalog, self.owned, equipped)
end

-- Owns the weapon, and puts it in the first empty slot that takes it.
function Loadout:Buy(weapon)
	if self:Owns(weapon) then Raise(ALREADY_OWNED, weapon.class) end
	local owned = Copy(self.owned)
	owned[weapon.class] = true
	local bought = New(self.catalog, owned, self.equipped)
	for _, s in ipairs(SLOTS) do
		if s.kind == weapon.kind and bought.equipped[s.slot] == nil then return bought:Equip(s.slot, weapon) end
	end
	return bought
end

-- Owns the weapon and puts it in the slot named, whatever the slot held:
-- the Loadout tab's buy on a picked slot. Refused whole, buying nothing,
-- if the slot does not take it or it is already owned.
function Loadout:BuyInto(slot, weapon)
	if not Fits(slot, weapon) then Raise(WRONG_SLOT, format("%s in slot %d", weapon.class, slot)) end
	if self:Owns(weapon) then Raise(ALREADY_OWNED, weapon.class) end
	local owned = Copy(self.owned)
	owned[weapon.class] = true
	return New(self.catalog, owned, self.equipped):Equip(slot, weapon)
end

-- A new player's: the catalog's starters, owned and in their slots.
-- A resupply (TF2's locker takes a loadout changed since spawning): held is
-- the classes a player holds now. strip is the store's weapons among them
-- that no slot holds any more; give is each equipped weapon not held, in
-- slot order. A class the catalog does not list is never touched.
function Loadout:Restock(held)
	local holding, equipped = {}, {}
	for _, class in ipairs(held) do holding[class] = true end
	local give = {}
	for _, s in ipairs(SLOTS) do
		local class = self.equipped[s.slot]
		if class then
			equipped[class] = true
			if not holding[class] then give[#give + 1] = class end
		end
	end
	local strip = {}
	for _, class in ipairs(held) do
		if self.catalog.byClass[class] and not equipped[class] then strip[#strip + 1] = class end
	end
	return strip, give
end

function Starting(catalog)
	local loadout = New(catalog, {}, {})
	for _, weapon in ipairs(catalog:Weapons()) do
		if weapon.starter then loadout = loadout:Buy(weapon) end
	end
	return loadout
end

-- owned: the classes owned, in catalog order; equipped: { slot, weapon }
-- for each filled slot, weapon a class.
function Loadout:State()
	local owned, equipped = {}, {}
	for _, weapon in ipairs(self.catalog:Weapons()) do
		if self:Owns(weapon) then owned[#owned + 1] = weapon.class end
	end
	for _, s in ipairs(SLOTS) do
		local class = self.equipped[s.slot]
		if class then
			equipped[#equipped + 1] = {
				slot = s.slot,
				weapon = class,
			}
		end
	end
	return owned, equipped
end

-- The loadout a State describes, held to the same rules.
function FromState(catalog, owned, equipped)
	local classes = {}
	for _, class in ipairs(owned) do classes[catalog:Weapon(class).class] = true end
	local loadout = New(catalog, classes, {})
	for _, e in ipairs(equipped) do loadout = loadout:Equip(e.slot, catalog:Weapon(e.weapon)) end
	return loadout
end
