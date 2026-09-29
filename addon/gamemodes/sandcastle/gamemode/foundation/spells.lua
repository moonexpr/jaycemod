-- The spells system. A SpellBook ports CTFSpellBook's state: the selected
-- spell, its charges, the roll that picks it and the cast cooldown. The
-- Library holds the books of the players who may cast and grants and
-- revokes them. A Shot is one spell projectile or spawner in flight.
--
-- A spell set is a part (foundation.spells.tf2) providing COUNT,
-- Definition(index) -> { name, charges, kind, castSound, speedScale, icon },
-- Roll(tier, random) -> index, Strategy(index) -> part name, TIER_COMMON,
-- TIER_RARE, ROLL_TIME and CAST_COOLDOWN.
--
-- A spell is a strategy part, loaded on first use, providing INDEX and
-- Cast(caster) -> bool (whether anything was cast). A spell that throws
-- something also provides PROJECTILE (the class it launches) and
-- Impact(caster, impact) -> nil | REFUND, and may provide
-- NewShot(class, config, now) -> state and
-- Tick(caster, state, where, now) -> nil | DONE for what it does in flight.
-- Spells act only through the caster port (foundation.spells.caster).
--
-- impact = { class, position (pulled off the surface), hitPosition, normal,
-- team (the shot's), projectile (its handle), config (its launch config),
-- state (its shot state) }; where = { position, team, projectile }.
local require = require
local Teams = require("foundation.teams")
local ipairs, pairs, setmetatable = ipairs, pairs, setmetatable
module(...)

-- SPELL_EMPTY and SPELL_UNKNOWN (tf_weapon_spellbook.cpp)
EMPTY, UNKNOWN = -1, -2

ROLLED = "rolled" -- a book's roll finished
REFUND = "refund" -- a spell failed and is given back (the spawn boss's)
DONE = "done" -- a shot has nothing more to do

DENY_INTERVAL = 0.5 -- m_flTimeNextErrorSound

-------------------------------------------------------------------------------
-- SpellBook

SpellBook = {}
SpellBook.__index = SpellBook

function SpellBook.New(set)
	return setmetatable({
		set = set,
		selected = EMPTY,
		charges = 0,
		nextSpell = EMPTY,
		rollingUntil = nil,
		nextCastAt = 0,
		nextDenyAt = 0,
	}, SpellBook)
end

function SpellBook:Strategy(index)
	return require(self.set.Strategy(index))
end

-- SetSelectedSpell: a spell comes with its full charges; EMPTY and UNKNOWN
-- have none.
function SpellBook:Select(index)
	self.selected = index
	self.charges = 0
	if index >= 0 then self.charges = self.set.Definition(index).charges end
end

function SpellBook:HasASpellWithCharges()
	return self.charges > 0 or self.selected == UNKNOWN
end

-- CSpellPickup::ItemCanBeTouchedByPlayer and RollNewSpell: a common pickup
-- is refused while a spell with charges is held or rolling; otherwise the
-- book shows UNKNOWN until the roll finishes ROLL_TIME later. random(lo, hi)
-- draws an integer.
function SpellBook:Pickup(tier, now, random)
	if tier == self.set.TIER_COMMON and self:HasASpellWithCharges() then return false end
	self.nextSpell = self.set.Roll(tier, random)
	self:Select(UNKNOWN)
	self.rollingUntil = now + self.set.ROLL_TIME
	return true
end

-- RollNewSpellFinish
function SpellBook:Tick(now)
	if self.rollingUntil == nil or now < self.rollingUntil then return nil end
	self.rollingUntil = nil
	self:Select(self.nextSpell)
	return ROLLED
end

-- CanCastSpell, and PrimaryAttack's wait for m_flTimeNextSpell.
function SpellBook:CanCast(now)
	return self.charges > 0 and self.selected >= 0 and self.selected < self.set.COUNT and now >= self.nextCastAt
end

-- CastSpell and PaySpellCost: the charge is spent before the spell runs, so
-- a spell that finds no room to throw is spent all the same.
function SpellBook:Cast(caster, now)
	if not self:CanCast(now) then return false end
	self.charges = self.charges - 1
	self.nextCastAt = now + self.set.CAST_COOLDOWN
	self:Strategy(self.selected).Cast(caster)
	return true
end

-- Whether a refused cast plays the deny sound: not during the cooldown
-- (PrimaryAttack returns first), and at most every DENY_INTERVAL.
function SpellBook:Deny(now)
	if now < self.nextCastAt or now < self.nextDenyAt then return false end
	self.nextDenyAt = now + DENY_INTERVAL
	return true
end

function SpellBook:State()
	return {
		selected = self.selected,
		charges = self.charges,
		rollingUntil = self.rollingUntil,
	}
end

-------------------------------------------------------------------------------
-- Shot

Shot = {}
Shot.__index = Shot

function Shot.New(strategy, class, config, now)
	local state = {}
	if strategy.NewShot then state = strategy.NewShot(class, config, now) end
	return setmetatable({
		strategy = strategy,
		class = class,
		config = config,
		state = state,
	}, Shot)
end

function Shot:Index()
	return self.strategy.INDEX
end

function Shot:Tick(caster, where, now)
	if not self.strategy.Tick then return nil end
	return self.strategy.Tick(caster, self.state, where, now)
end

function Shot:Impact(caster, impact)
	impact.class = self.class
	impact.config = self.config
	impact.state = self.state
	return self.strategy.Impact(caster, impact)
end

-------------------------------------------------------------------------------
-- Library

Library = {}
Library.__index = Library

function Library.New(set)
	return setmetatable({
		set = set,
		books = {},
	}, Library)
end

function Library:BookOf(holder)
	return self.books[holder]
end

-- While spells are on, each living RED or BLU player holds a book.
-- candidate = { holder, team, alive }.
local function MayHold(on, candidate)
	return on and candidate.alive and (candidate.team == Teams.RED or candidate.team == Teams.BLUE)
end

-- Grants and revokes books to match; returns the holders granted and those
-- revoked, in the candidates' order. Holders missing from the candidates
-- (gone from the game) lose their books too.
function Library:Sync(on, candidates)
	local granted, revoked, present = {}, {}, {}
	for _, candidate in ipairs(candidates) do
		local holder = candidate.holder
		present[holder] = true
		local holds, may = self.books[holder] ~= nil, MayHold(on, candidate)
		if may and not holds then
			self.books[holder] = SpellBook.New(self.set)
			granted[#granted + 1] = holder
		elseif holds and not may then
			self.books[holder] = nil
			revoked[#revoked + 1] = holder
		end
	end
	for holder in pairs(self.books) do
		if not present[holder] then self.books[holder] = nil end
	end
	return granted, revoked
end

-- A new life: TF2 regenerates the player's items, so any book starts over.
-- Returns whether the player holds one.
function Library:Respawn(on, candidate)
	self.books[candidate.holder] = nil
	if not MayHold(on, candidate) then return false end
	self.books[candidate.holder] = SpellBook.New(self.set)
	return true
end

-- CSpellPickup: returns whether the pickup is taken and whether a spell is
-- rolling for it. A common pickup needs a book; a rare one is taken even by
-- a player without one, who gets nothing (MyTouch returns true).
function Library:Pickup(holder, tier, now, random)
	local book = self.books[holder]
	if book == nil then return tier ~= self.set.TIER_COMMON, false end
	local rolled = book:Pickup(tier, now, random)
	return rolled, rolled
end

-- Ticks every book; returns the holders whose roll finished.
function Library:Tick(now)
	local rolled = {}
	for holder, book in pairs(self.books) do
		if book:Tick(now) == ROLLED then rolled[#rolled + 1] = holder end
	end
	return rolled
end

-- The Shot for a projectile or spawner of spell `index`.
function Library:Shot(index, class, config, now)
	return Shot.New(require(self.set.Strategy(index)), class, config, now)
end

-- A shot lands. A refunded spell goes back into the thrower's current book
-- (the spawn boss's SetSelectedSpell), whatever it holds by then.
function Library:Impact(holder, shot, caster, impact)
	if shot:Impact(caster, impact) ~= REFUND then return end
	local book = self.books[holder]
	if book then book:Select(shot:Index()) end
end
