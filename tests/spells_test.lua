-- foundation.spells: the SpellBook's pickup, roll, cast and cooldown rules,
-- the Library that grants and revokes books, and a shot's refund, driven
-- through whole scenarios with the TF2 set and a fake caster.
local T = dofile("tests/harness.lua")
local Fake = dofile("tests/fake_caster.lua")
local Spells = T.require("foundation.spells")
local Tf2 = T.require("foundation.spells.tf2")
local Teams = T.require("foundation.teams")

local V = Fake.Vector

-- A random(lo, hi) that lands at `fraction` of the range, as RandomInt does.
local function Landing(fraction)
	local random = Fake.Random({ fraction })
	return function(lo, hi) return random:Int(lo, hi) end
end
local FIRST, LAST = 0, 0.999

local function NewCaster(owner, t)
	t = t or {}
	t.owner = owner
	return Fake.Caster(t)
end

local function Player(team)
	return Fake.Target({
		name = "caster",
		team = team or Teams.RED,
		origin = V(0, 0, 0),
	})
end

local function Candidate(holder, team, alive)
	return {
		holder = holder,
		team = team,
		alive = alive ~= false,
	}
end

T.test("a common pickup rolls for 2 s, then the book holds that spell's charges", function()
	local book = Spells.SpellBook.New(Tf2)
	T.eq(book:State().selected, Spells.EMPTY, "a new book is empty")
	T.eq(book:HasASpellWithCharges(), false, "empty")

	T.eq(book:Pickup(Tf2.TIER_COMMON, 10, Landing(FIRST)), true, "taken")
	local rolling = book:State()
	T.eq(rolling.selected, Spells.UNKNOWN, "unknown while rolling")
	T.eq(rolling.charges, 0, "no charges while rolling")
	T.eq(rolling.rollingUntil, 10 + Tf2.ROLL_TIME, "rolls for ROLL_TIME")
	T.eq(book:HasASpellWithCharges(), true, "a roll counts as a spell")
	T.eq(book:CanCast(11), false, "nothing to cast while rolling")

	T.eq(book:Tick(11.9), nil, "still rolling")
	T.eq(book:Tick(12), Spells.ROLLED, "rolled at 2 s")
	local rolled = book:State()
	T.eq(rolled.selected, Tf2.SPELL_FIREBALL, "the first common entry")
	T.eq(rolled.charges, Tf2.Definition(Tf2.SPELL_FIREBALL).charges, "fireball's charges")
	T.eq(rolled.rollingUntil, nil, "done rolling")
	T.eq(book:Tick(13), nil, "rolls once")
end)

T.test("a second common pickup is refused while charges remain or a roll runs, a rare one is taken", function()
	local book = Spells.SpellBook.New(Tf2)
	book:Pickup(Tf2.TIER_COMMON, 0, Landing(FIRST))
	T.eq(book:Pickup(Tf2.TIER_COMMON, 1, Landing(FIRST)), false, "refused while rolling")
	book:Tick(2)
	T.eq(book:Pickup(Tf2.TIER_COMMON, 3, Landing(FIRST)), false, "refused while charges remain")
	T.eq(book:State().selected, Tf2.SPELL_FIREBALL, "kept")

	T.eq(book:Pickup(Tf2.TIER_RARE, 3, Landing(LAST)), true, "rare always rolls")
	T.eq(book:State().selected, Spells.UNKNOWN, "rolling again")
	book:Tick(3 + Tf2.ROLL_TIME)
	T.eq(book:State().selected, Tf2.SPELL_SKELETON_HORDE, "the last rare spell")
	T.eq(book:State().charges, 1, "horde has one charge")
end)

T.test("pickup -> roll -> cast spends charges under a 0.5 s cooldown until empty", function()
	local owner = Player()
	local caster = NewCaster(owner)
	local book = Spells.SpellBook.New(Tf2)
	book:Pickup(Tf2.TIER_COMMON, 0, Landing(FIRST))
	book:Tick(Tf2.ROLL_TIME)

	T.eq(book:Cast(caster, 5), true, "first cast")
	T.eq(book:State().charges, 1, "a charge spent")
	T.eq(#caster:Calls("LaunchProjectile"), 1, "the fireball flew")

	T.eq(book:CanCast(5.4), false, "cooling down")
	T.eq(book:Cast(caster, 5.4), false, "no cast during the cooldown")
	T.eq(book:Deny(5.4), false, "no deny sound during the cooldown")
	T.eq(book:State().charges, 1, "nothing spent")

	T.eq(book:Cast(caster, 5 + Tf2.CAST_COOLDOWN), true, "second cast")
	T.eq(book:State().charges, 0, "empty")
	T.eq(book:State().selected, Tf2.SPELL_FIREBALL, "the spell stays selected with no charges")
	T.eq(book:HasASpellWithCharges(), false, "no spell with charges")
	T.eq(#caster:Calls("LaunchProjectile"), 2, "two fireballs")

	T.eq(book:Cast(caster, 7), false, "an empty book casts nothing")
	T.eq(book:Deny(7), true, "the deny sound plays")
	T.eq(book:Deny(7.2), false, "at most every DENY_INTERVAL")
	T.eq(book:Deny(7 + Spells.DENY_INTERVAL), true, "and again after it")

	T.eq(book:Pickup(Tf2.TIER_COMMON, 8, Landing(FIRST)), true, "an empty book takes a common pickup")
end)

T.test("the charge is spent even when the toss starts in solid", function()
	local owner = Player()
	local caster = NewCaster(owner, {
		hull = function(from, to)
			return {
				startSolid = true,
				endPos = from,
			}
		end,
	})
	local book = Spells.SpellBook.New(Tf2)
	book:Select(Tf2.SPELL_BATS)
	T.eq(book:Cast(caster, 0), true, "cast")
	T.eq(book:State().charges, 1, "spent")
	T.eq(#caster:Calls("LaunchProjectile"), 0, "nothing thrown")
end)

T.test("the library grants books to living RED and BLU players while spells are on", function()
	local library = Spells.Library.New(Tf2)
	local red, blue, spectator, dead = {}, {}, {}, {}
	local players = {
		Candidate(red, Teams.RED),
		Candidate(blue, Teams.BLUE),
		Candidate(spectator, Teams.SPECTATOR),
		Candidate(dead, Teams.RED, false),
	}

	local granted, revoked = library:Sync(false, players)
	T.eq(#granted + #revoked, 0, "spells off: nothing")
	T.eq(library:BookOf(red), nil, "no book while off")

	granted, revoked = library:Sync(true, players)
	T.eq(#granted, 2, "RED and BLU get books")
	T.eq(granted[1], red, "red first")
	T.eq(granted[2], blue, "then blue")
	T.eq(#revoked, 0, "nothing revoked")
	T.eq(library:BookOf(spectator), nil, "spectators get none")
	T.eq(library:BookOf(dead), nil, "the dead get none")

	granted = library:Sync(true, players)
	T.eq(#granted, 0, "a second sync grants nothing new")

	library:BookOf(red):Select(Tf2.SPELL_METEOR)
	T.eq(library:Respawn(true, Candidate(red, Teams.RED)), true, "a respawn is granted a book")
	T.eq(library:BookOf(red):State().selected, Spells.EMPTY, "and it starts empty, as TF2 regenerates items")

	players[2] = Candidate(blue, Teams.SPECTATOR)
	granted, revoked = library:Sync(true, players)
	T.eq(#revoked, 1, "a player who left RED and BLU loses the book")
	T.eq(revoked[1], blue, "blue")

	granted, revoked = library:Sync(false, players)
	T.eq(#revoked, 1, "spells off revokes the rest")
	T.eq(library:BookOf(red), nil, "gone")
	T.eq(library:Respawn(false, Candidate(red, Teams.RED)), false, "no book on respawn while off")
end)

T.test("a player who left keeps no book", function()
	local library = Spells.Library.New(Tf2)
	local gone = {}
	library:Sync(true, { Candidate(gone, Teams.RED) })
	library:Sync(true, {})
	T.eq(library:BookOf(gone), nil, "forgotten")
end)

T.test("pickups through the library: a common one needs a book, a rare one is taken regardless", function()
	local library = Spells.Library.New(Tf2)
	local holder = {}
	local taken, rolled = library:Pickup(holder, Tf2.TIER_COMMON, 0, Landing(FIRST))
	T.eq(taken, false, "no book: a common pickup stays")
	taken, rolled = library:Pickup(holder, Tf2.TIER_RARE, 0, Landing(FIRST))
	T.eq(taken, true, "no book: a rare pickup is taken")
	T.eq(rolled, false, "but rolls nothing")

	library:Sync(true, { Candidate(holder, Teams.BLUE) })
	taken, rolled = library:Pickup(holder, Tf2.TIER_COMMON, 0, Landing(FIRST))
	T.eq(taken and rolled, true, "a book rolls")
	T.eq(#library:Tick(1), 0, "nothing rolled yet")
	local done = library:Tick(Tf2.ROLL_TIME)
	T.eq(#done, 1, "one book rolled")
	T.eq(done[1], holder, "the holder's")
end)

T.test("a spawn_boss spell with no room for the eyeball is given back", function()
	local owner = Player(Teams.BLUE)
	local library = Spells.Library.New(Tf2)
	library:Sync(true, { Candidate(owner, Teams.BLUE) })
	local book = library:BookOf(owner)
	book:Select(Tf2.SPELL_SPAWN_BOSS)
	local caster = NewCaster(owner)
	T.eq(book:Cast(caster, 0), true, "cast")
	T.eq(book:State().charges, 0, "spent")
	local launch = caster:Calls("LaunchProjectile")[1]

	local blocked = NewCaster(owner, {
		hull = function(from, to)
			return {
				startSolid = true,
				endPos = from,
			}
		end,
	})
	local shot = library:Shot(launch.config.spell, launch.class, launch.config, 0)
	library:Impact(owner, shot, blocked, {
		position = V(100, 0, 1),
		hitPosition = V(100, 0, 0),
		normal = V(0, 0, 1),
		team = Teams.BLUE,
		projectile = {},
	})
	T.eq(#blocked:Calls("SpawnNPC"), 0, "no eyeball")
	T.eq(book:State().selected, Tf2.SPELL_SPAWN_BOSS, "the spell is back")
	T.eq(book:State().charges, 1, "with its charge")

	local roomy = NewCaster(owner)
	book:Cast(roomy, 1)
	shot = library:Shot(Tf2.SPELL_SPAWN_BOSS, launch.class, launch.config, 1)
	library:Impact(owner, shot, roomy, {
		position = V(100, 0, 1),
		hitPosition = V(100, 0, 0),
		normal = V(0, 0, 1),
		team = Teams.BLUE,
		projectile = {},
	})
	T.eq(#roomy:Calls("SpawnNPC"), 1, "the eyeball spawns")
	T.eq(book:State().charges, 0, "and the spell is spent")
end)

T.finish()
