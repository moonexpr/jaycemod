-- features.spells.model: the SpellBook's pickup, roll, cast and cooldown rules,
-- the Library that grants and revokes books, and a shot's refund, driven
-- through whole scenarios with the TF2 set and a fake caster.
local T = dofile("tests/harness.lua")
local Fake = dofile("tests/fake_caster.lua")
local Spells = T.require("features.spells.model")
local SpellSet = T.require("features.spells.halloween")
local Teams = gameplay.teams

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
	local book = Spells.SpellBook.New(SpellSet)
	T.eq(book:State().selected, Spells.EMPTY, "a new book is empty")
	T.eq(book:HasASpellWithCharges(), false, "empty")

	T.eq(book:Pickup(SpellSet.TIER_COMMON, 10, Landing(FIRST)), true, "taken")
	local rolling = book:State()
	T.eq(rolling.selected, Spells.UNKNOWN, "unknown while rolling")
	T.eq(rolling.charges, 0, "no charges while rolling")
	T.eq(rolling.rollingUntil, 10 + SpellSet.ROLL_TIME, "rolls for ROLL_TIME")
	T.eq(book:HasASpellWithCharges(), true, "a roll counts as a spell")
	T.eq(book:CanCast(11), false, "nothing to cast while rolling")

	T.eq(book:Tick(11.9), nil, "still rolling")
	T.eq(book:Tick(12), Spells.ROLLED, "rolled at 2 s")
	local rolled = book:State()
	T.eq(rolled.selected, SpellSet.SPELL_FIREBALL, "the first common entry")
	T.eq(rolled.charges, SpellSet.Definition(SpellSet.SPELL_FIREBALL).charges, "fireball's charges")
	T.eq(rolled.rollingUntil, nil, "done rolling")
	T.eq(book:Tick(13), nil, "rolls once")
end)

T.test("a second common pickup is refused while charges remain or a roll runs, a rare one is taken", function()
	local book = Spells.SpellBook.New(SpellSet)
	book:Pickup(SpellSet.TIER_COMMON, 0, Landing(FIRST))
	T.eq(book:Pickup(SpellSet.TIER_COMMON, 1, Landing(FIRST)), false, "refused while rolling")
	book:Tick(2)
	T.eq(book:Pickup(SpellSet.TIER_COMMON, 3, Landing(FIRST)), false, "refused while charges remain")
	T.eq(book:State().selected, SpellSet.SPELL_FIREBALL, "kept")

	T.eq(book:Pickup(SpellSet.TIER_RARE, 3, Landing(LAST)), true, "rare always rolls")
	T.eq(book:State().selected, Spells.UNKNOWN, "rolling again")
	book:Tick(3 + SpellSet.ROLL_TIME)
	T.eq(book:State().selected, SpellSet.SPELL_SKELETON_HORDE, "the last rare spell")
	T.eq(book:State().charges, 1, "horde has one charge")
end)

T.test("pickup -> roll -> cast spends charges under a 0.5 s cooldown until empty", function()
	local owner = Player()
	local caster = NewCaster(owner)
	local book = Spells.SpellBook.New(SpellSet)
	book:Pickup(SpellSet.TIER_COMMON, 0, Landing(FIRST))
	book:Tick(SpellSet.ROLL_TIME)

	T.eq(book:Cast(caster, 5), true, "first cast")
	T.eq(book:State().charges, 1, "a charge spent")
	T.eq(#caster:Calls("LaunchProjectile"), 1, "the fireball flew")

	T.eq(book:CanCast(5.4), false, "cooling down")
	T.eq(book:Cast(caster, 5.4), false, "no cast during the cooldown")
	T.eq(book:Deny(5.4), false, "no deny sound during the cooldown")
	T.eq(book:State().charges, 1, "nothing spent")

	T.eq(book:Cast(caster, 5 + SpellSet.CAST_COOLDOWN), true, "second cast")
	T.eq(book:State().charges, 0, "empty")
	T.eq(book:State().selected, SpellSet.SPELL_FIREBALL, "the spell stays selected with no charges")
	T.eq(book:HasASpellWithCharges(), false, "no spell with charges")
	T.eq(#caster:Calls("LaunchProjectile"), 2, "two fireballs")

	T.eq(book:Cast(caster, 7), false, "an empty book casts nothing")
	T.eq(book:Deny(7), true, "the deny sound plays")
	T.eq(book:Deny(7.2), false, "at most every DENY_INTERVAL")
	T.eq(book:Deny(7 + Spells.DENY_INTERVAL), true, "and again after it")

	T.eq(book:Pickup(SpellSet.TIER_COMMON, 8, Landing(FIRST)), true, "an empty book takes a common pickup")
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
	local book = Spells.SpellBook.New(SpellSet)
	book:Select(SpellSet.SPELL_BATS)
	T.eq(book:Cast(caster, 0), true, "cast")
	T.eq(book:State().charges, 1, "spent")
	T.eq(#caster:Calls("LaunchProjectile"), 0, "nothing thrown")
end)

T.test("the library grants books to living RED and BLU players while spells are on", function()
	local library = Spells.Library.New(SpellSet)
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

	library:BookOf(red):Select(SpellSet.SPELL_METEOR)
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

T.test("a caster who left keeps no book; Sync leaves casters it was not given alone", function()
	local library = Spells.Library.New(SpellSet)
	local gone, npc = {}, {}
	library:Sync(true, { Candidate(gone, Teams.RED) })
	library:Grant(npc)
	library:Sync(true, {})
	T.eq(library:BookOf(gone) ~= nil, true, "Sync only judges its candidates")
	T.eq(library:BookOf(npc) ~= nil, true, "a book granted directly stays")
	library:Forget(gone)
	T.eq(library:BookOf(gone), nil, "forgotten")
	T.eq(library:Grant(npc), library:BookOf(npc), "granting again keeps the same book")
	library:Revoke(npc)
	T.eq(library:BookOf(npc), nil, "revoked")
end)

T.test("a book armed by the weapon outlasts the rules until the weapon goes", function()
	local library = Spells.Library.New(SpellSet)
	local holder = {}
	T.eq(library:Arm(holder), true, "a holder with no book is armed with one")
	T.eq(library:BookOf(holder) ~= nil, true, "it holds a book while spells are off")
	local granted, revoked = library:Sync(false, { Candidate(holder, Teams.RED) })
	T.eq(#granted + #revoked, 0, "spells off take nothing from it")
	granted, revoked = library:Sync(true, { Candidate(holder, Teams.SPECTATOR) })
	T.eq(#revoked, 0, "nor does leaving RED and BLU")
	local taken = library:Pickup(holder, SpellSet.TIER_COMMON, 0, Landing(FIRST))
	T.eq(taken, true, "it collects pickups")
	T.eq(library:Respawn(false, Candidate(holder, Teams.RED)), true, "a respawn keeps a book")
	T.eq(library:BookOf(holder):State().selected, Spells.EMPTY, "starting over")
	library:Disarm(holder)
	T.eq(library:BookOf(holder), nil, "the weapon gone, the book goes")
end)

T.test("arming a holder of the rules' book changes nothing, and the rules still take it back", function()
	local library = Spells.Library.New(SpellSet)
	local holder = {}
	local players = { Candidate(holder, Teams.BLUE) }
	library:Sync(true, players)
	local book = library:BookOf(holder)
	T.eq(library:Arm(holder), false, "already holds one")
	T.eq(library:BookOf(holder), book, "the same book")
	library:Disarm(holder)
	T.eq(library:BookOf(holder), book, "disarming leaves the rules' book")
	local _, revoked = library:Sync(false, players)
	T.eq(revoked[1], holder, "spells off revoke it")
end)

T.test("revoking or forgetting an armed holder ends its arming", function()
	local library = Spells.Library.New(SpellSet)
	local revoked, forgotten = {}, {}
	library:Arm(revoked)
	library:Arm(forgotten)
	library:Revoke(revoked)
	library:Forget(forgotten)
	local players = {
		Candidate(revoked, Teams.RED),
		Candidate(forgotten, Teams.RED),
	}
	library:Sync(true, players)
	local _, taken = library:Sync(false, players)
	T.eq(#taken, 2, "the rules' books, revoked as usual")
end)

T.test("pickups through the library: only a caster holding a book collects one", function()
	local library = Spells.Library.New(SpellSet)
	local holder = {}
	local taken, rolled = library:Pickup(holder, SpellSet.TIER_COMMON, 0, Landing(FIRST))
	T.eq(taken, false, "no book: a common pickup stays")
	taken, rolled = library:Pickup(holder, SpellSet.TIER_RARE, 0, Landing(FIRST))
	T.eq(taken, false, "no book: a rare pickup stays too")
	T.eq(rolled, false, "and rolls nothing")

	library:Sync(true, { Candidate(holder, Teams.BLUE) })
	taken, rolled = library:Pickup(holder, SpellSet.TIER_COMMON, 0, Landing(FIRST))
	T.eq(taken and rolled, true, "a book rolls")
	T.eq(#library:Tick(1), 0, "nothing rolled yet")
	local done = library:Tick(SpellSet.ROLL_TIME)
	T.eq(#done, 1, "one book rolled")
	T.eq(done[1], holder, "the holder's")
end)

T.test("an NPC caster holds a book, picks up, rolls and casts through the same port", function()
	local npc = Fake.Target({
		name = "soldier",
		team = Teams.BLUE,
		origin = V(0, 0, 0),
		player = false,
	})
	local caster = NewCaster(npc, { shoot = V(0, 0, 50) })
	local library = Spells.Library.New(SpellSet)
	library:Grant(npc)
	local taken = library:Pickup(npc, SpellSet.TIER_RARE, 0, Landing(FIRST))
	T.eq(taken, true, "the NPC collects a pickup")
	library:Tick(SpellSet.ROLL_TIME)
	local book = library:BookOf(npc)
	T.eq(book:State().selected, SpellSet.SPELL_LIGHTNING, "a rare spell")
	T.eq(book:Cast(caster, SpellSet.ROLL_TIME), true, "cast")
	local launch = caster:Calls("LaunchProjectile")[1]
	T.eq(launch.class, "tf_projectile_lightningorb", "the orb flies")
	T.eq(launch.config.team, Teams.BLUE, "on the NPC's team")
	T.eq(caster:Calls("Particle")[1].name, "spell_cast_wheel_blue", "BLU's cast wheel")

	book:Select(SpellSet.SPELL_ATHLETIC)
	book:Cast(caster, 10)
	T.eq(npc.conds[SpellSet.COND.HALLOWEEN_SPEED_BOOST], 20, "a movement spell works on the NPC")
	book:Select(SpellSet.SPELL_OVERHEAL)
	npc.health = 100
	book:Cast(caster, 20)
	T.eq(npc.health, 150, "and a heal")
end)

T.test("a spawn_boss spell with no room for the eyeball is given back", function()
	local owner = Player(Teams.BLUE)
	local library = Spells.Library.New(SpellSet)
	library:Sync(true, { Candidate(owner, Teams.BLUE) })
	local book = library:BookOf(owner)
	book:Select(SpellSet.SPELL_SPAWN_BOSS)
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
	T.eq(book:State().selected, SpellSet.SPELL_SPAWN_BOSS, "the spell is back")
	T.eq(book:State().charges, 1, "with its charge")

	local roomy = NewCaster(owner)
	book:Cast(roomy, 1)
	shot = library:Shot(SpellSet.SPELL_SPAWN_BOSS, launch.class, launch.config, 1)
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

-------------------------------------------------------------------------------
-- The flights spell projectiles bind to (games.gameplay.projectile variants)

local Projectile = gameplay.projectile
local Jar = T.require("games.gameplay.projectile.jar")
local Orb = T.require("features.spells.orb")

local WORLD = {
	world = true,
	enemy = false,
}
local ENEMY = {
	world = false,
	enemy = true,
}
local FRIEND = {
	world = false,
	enemy = false,
}

T.test("a jar falls and breaks on the world or an enemy, or when its fuse runs out", function()
	T.eq(Jar.GRAVITY > 0, true, "ballistic")
	local jar = Projectile.New(Jar, SpellSet.JAR_FLIGHT, 0)
	T.eq(jar:Touch(FRIEND), Projectile.BOUNCE, "a teammate or a prop: bounces")
	T.eq(jar:Touch(ENEMY), Projectile.DETONATE, "an enemy: breaks")
	jar = Projectile.New(Jar, SpellSet.JAR_FLIGHT, 0)
	T.eq(jar:Touch(WORLD), Projectile.DETONATE, "the world: breaks")
	jar = Projectile.New(Jar, SpellSet.JAR_FLIGHT, 0)
	T.eq(jar:Tick(SpellSet.JAR_FUSE - 0.1), Projectile.NONE, "flying")
	T.eq(jar:Tick(SpellSet.JAR_FUSE), Projectile.DETONATE, "the fuse")
end)

T.test("a mirv bomblet ignores touches for its first second, then breaks on them", function()
	local bomblet = Projectile.New(Jar, {
		fuse = 2.1,
		armDelay = 1,
	}, 10)
	T.eq(bomblet:Touch(WORLD), Projectile.BOUNCE, "unarmed")
	T.eq(bomblet:Tick(10.5), Projectile.NONE, "still unarmed")
	T.eq(bomblet:Touch(ENEMY), Projectile.BOUNCE, "unarmed")
	T.eq(bomblet:Tick(11), Projectile.NONE, "armed now")
	T.eq(bomblet:Touch(WORLD), Projectile.DETONATE, "breaks")
end)

T.test("a lightning orb flies straight, bounces off the world, passes through the rest, ends after 5 s", function()
	T.eq(Orb.GRAVITY, 0, "straight")
	local orb = Projectile.New(Orb, {
		fuse = 5,
	}, 0)
	T.eq(orb:Touch(WORLD), Projectile.BOUNCE, "bounces")
	T.eq(orb:Touch(ENEMY), Projectile.NONE, "passes through players")
	T.eq(orb:Touch(FRIEND), Projectile.NONE, "and everything else")
	T.eq(orb:Tick(4.9), Projectile.NONE, "alive")
	T.eq(orb:Tick(5), Projectile.DETONATE, "its end")
end)

T.finish()
