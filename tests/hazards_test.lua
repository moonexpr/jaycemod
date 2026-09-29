local T = dofile("tests/harness.lua")
local Fake = dofile("tests/fake_actor.lua")
local Hazards = T.require("foundation.hazards")
local Pumpkin = T.require("foundation.hazards.pumpkin_bomb")
local GenericBomb = T.require("foundation.hazards.generic_bomb")
local Zapper = T.require("foundation.hazards.zapper")
local Combat = T.require("foundation.combat")
local Teams = T.require("foundation.teams")
local Holiday = T.require("foundation.holiday")
local Halloween = T.require("foundation.holiday.halloween")
local Gift = T.require("foundation.holiday.gift")

local V = Fake.Vector
local NONE, EXPLODE, FIZZLE, ZAP = Hazards.NONE, Hazards.EXPLODE, Hazards.FIZZLE, Hazards.ZAP

local function Shot(team, amount)
	return {
		team = team,
		amount = amount,
	}
end

local function Touch(t)
	return {
		target = t.target,
		team = t.team or Teams.UNASSIGNED,
		projectile = t.projectile == true,
		triggerHurt = t.triggerHurt == true,
		leaving = t.leaving == true,
	}
end

local function Contains(list, value)
	for _, v in ipairs(list) do
		if v == value then return true end
	end
	return false
end

-- A field of hazards standing in the open, blown up the way the combat
-- controller does it: every other hazard within the radius takes what the
-- Explosion says, as damage from the attacker's team.
local Field = {}
Field.__index = Field

local function NewField()
	return setmetatable({
		items = {},
		log = {},
	}, Field)
end

function Field:Add(name, hazard, origin)
	self.items[#self.items + 1] = {
		name = name,
		hazard = hazard,
		origin = origin,
	}
end

function Field:Apply(item, outcome)
	if outcome.kind ~= EXPLODE then return end
	self.log[#self.log + 1] = item.name .. ":" .. outcome.team
	local explosion = Combat.Explosion.New({
		origin = item.origin,
		radius = outcome.radius,
		damage = outcome.damage,
		attackerTeam = outcome.team,
		halfFalloff = outcome.halfFalloff,
		forceFriendlyFire = outcome.forceFriendlyFire,
	})
	for _, other in ipairs(self.items) do
		local distance = (other.origin - item.origin):Length()
		if other ~= item and distance <= outcome.radius then
			local amount = explosion:DamageTo({
				team = other.hazard:Team(),
				isAttacker = false,
				distance = distance,
				visible = true,
			})
			if amount then self:Apply(other, other.hazard:Damaged(Shot(outcome.team, amount))) end
		end
	end
end

function Field:Shoot(name, team, amount)
	for _, item in ipairs(self.items) do
		if item.name == name then self:Apply(item, item.hazard:Damaged(Shot(team, amount))) end
	end
end

local function MapPumpkin(now)
	return Hazards.New(Pumpkin, {}, now or 0)
end

local function SpellPumpkin(team, now)
	return Hazards.New(Pumpkin, {
		scale = 0.6,
		damage = 80,
		radius = 200,
		team = team,
		lifetime = 40.5,
		isSpell = true,
	}, now or 0)
end

-- Pumpkin bombs

T.test("scenario: a map pumpkin shot by RED explodes as RED and sets off the pumpkins its blast reaches", function()
	local field = NewField()
	field:Add("a", MapPumpkin(), V(0, 0, 0))
	field:Add("b", MapPumpkin(), V(200, 0, 0))
	field:Add("c", MapPumpkin(), V(450, 0, 0)) -- out of a's reach, in b's
	field:Add("d", MapPumpkin(), V(1000, 0, 0))
	field:Shoot("a", Teams.RED, 1)
	T.eq(table.concat(field.log, " "), "a:2 b:2 c:2", "the chain, each exploding once, as RED")
	T.eq(field.items[4].hazard:IsFinished(), false, "the far pumpkin stands")
	T.eq(field.items[1].hazard:Damaged(Shot(Teams.BLUE, 50)).kind, NONE, "a spent pumpkin takes no more damage")
end)

T.test("a map pumpkin's blast is TF2's: 150 over 300 with half falloff, its particle and sound, then gibs", function()
	local pumpkin = MapPumpkin()
	T.eq(pumpkin:Team(), Teams.HALLOWEEN, "a map pumpkin is HALLOWEEN's")
	local body = pumpkin:Body()
	T.eq(body.model, Pumpkin.MODEL, "model")
	T.eq(body.move, Hazards.MOVE_PHYSICS, "vphysics")
	T.eq(body.scale, 1, "scale")
	local boom = pumpkin:Damaged(Shot(Teams.BLUE, 30))
	T.eq(boom.kind, EXPLODE, "any damage kills it")
	T.eq(boom.team, Teams.BLUE, "the attacker's team")
	T.eq(boom.damage, Pumpkin.DAMAGE, "damage")
	T.eq(Pumpkin.DAMAGE, 150, "tf_pumpkin_bomb damage")
	T.eq(boom.radius, 300, "radius")
	T.eq(boom.halfFalloff, true, "DMG_HALF_FALLOFF")
	T.eq(boom.forceFriendlyFire, false, "teammates spared")
	T.eq(#boom.particles, 1, "one particle")
	T.eq(boom.particles[1], "pumpkin_explode", "particle")
	T.eq(boom.sound, "Halloween.PumpkinExplode", "sound")
	T.eq(boom.gibs, true, "BreakModel")
	T.eq(boom.output, nil, "no output")
end)

T.test("a map pumpkin damaged by nothing still stands", function()
	local pumpkin = MapPumpkin()
	T.eq(pumpkin:Damaged(Shot(Teams.RED, 0)).kind, NONE, "0 damage leaves health 1")
	T.eq(pumpkin:Damaged(Shot(Teams.RED, 0.5)).kind, EXPLODE, "any fraction kills: health is an integer")
end)

T.test("a spell pumpkin explodes for its own team and fizzles into goop for any other", function()
	local red = SpellPumpkin(Teams.RED)
	T.eq(red:Team(), Teams.RED, "team")
	local body = red:Body()
	T.eq(body.model, Pumpkin.TEAM_MODEL, "team model")
	T.eq(body.skin, 1, "RED's skin")
	T.eq(body.move, Hazards.MOVE_TOSS, "falls and bounces")
	T.eq(body.scale, 0.6, "scale")
	T.eq(SpellPumpkin(Teams.BLUE):Body().skin, 2, "BLU's skin")
	local fizzle = red:Damaged(Shot(Teams.BLUE, 100))
	T.eq(fizzle.kind, FIZZLE, "an enemy's shot")
	T.eq(fizzle.particles[1], "spell_pumpkin_mirv_goop_red", "RED goop")
	T.eq(red:Damaged(Shot(Teams.RED, 100)).kind, NONE, "spent")

	local boom = SpellPumpkin(Teams.BLUE):Damaged(Shot(Teams.BLUE, 1))
	T.eq(boom.kind, EXPLODE, "its own team's shot")
	T.eq(boom.team, Teams.BLUE, "as BLU")
	T.eq(boom.damage, 80, "the spell's damage")
	T.eq(boom.radius, 200, "the spell's radius")
	T.eq(Contains(boom.particles, "spell_pumpkin_mirv_goop_blue"), true, "goop on any damage")
	T.eq(Contains(boom.particles, "pumpkin_explode"), true, "and the explosion")
end)

T.test("a spell pumpkin fizzles when its lifetime runs out", function()
	local clock = Fake.Clock(100)
	local pumpkin = SpellPumpkin(Teams.RED, clock:Now())
	clock:Advance(40.25)
	T.eq(pumpkin:Tick(clock:Now()).kind, NONE, "alive")
	clock:Advance(0.25)
	T.eq(pumpkin:Tick(clock:Now()).kind, FIZZLE, "at 40.5 s")
	T.eq(pumpkin:Tick(clock:Now() + 1).kind, NONE, "once")
	T.eq(MapPumpkin(0):Tick(1e6).kind, NONE, "a map pumpkin lives forever")
	T.eq(Hazards.New(Pumpkin, { lifetime = 0 }, 0):Tick(1e6).kind, NONE, "a lifetime of 0 is none")
end)

T.test("a pumpkin touching trigger_hurt fizzles, whatever its team", function()
	T.eq(SpellPumpkin(Teams.RED):Touch(Touch({ triggerHurt = true })).kind, FIZZLE, "spell pumpkin")
	local fizzle = MapPumpkin():Touch(Touch({ triggerHurt = true }))
	T.eq(fizzle.kind, FIZZLE, "map pumpkin (CTFPumpkinBomb::PumpkinTouch)")
	T.eq(fizzle.particles[1], "spell_pumpkin_mirv_goop_blue", "a non-RED pumpkin goops blue")
	T.eq(MapPumpkin():Touch(Touch({ team = Teams.RED })).kind, NONE, "a player's touch does nothing")
end)

T.test("a projectile touching a pumpkin is a 10-damage hit from its thrower's team", function()
	local boom = MapPumpkin():Touch(Touch({
		projectile = true,
		team = Teams.RED,
	}))
	T.eq(boom.kind, EXPLODE, "a map pumpkin")
	T.eq(boom.team, Teams.RED, "as the thrower's team")
	T.eq(SpellPumpkin(Teams.RED):Touch(Touch({
		projectile = true,
		team = Teams.BLUE,
	})).kind, FIZZLE, "an enemy projectile fizzles a spell pumpkin")
	T.eq(SpellPumpkin(Teams.RED):Touch(Touch({
		projectile = true,
		team = Teams.RED,
	})).kind, EXPLODE, "a friendly one sets it off")
end)

-- Generic bombs

-- plr_hacksaw_event's eight skull bombs.
local function HacksawBomb()
	return Hazards.New(GenericBomb, {
		damage = 0,
		radius = 100,
		health = 1,
		explodeParticle = "ghost_appearation",
		sound = "misc/halloween/merasmus_appear.wav",
		friendlyFire = GenericBomb.DAMAGE_ATTACKER_AND_ATTACKER_ENEMIES,
		passActivator = true,
		team = Teams.UNASSIGNED,
		model = "models/props_mvm/mvm_human_skull_collide.mdl",
		skin = 0,
		scale = 1,
	}, 0)
end

T.test("scenario: hacksaw's skull bomb, shot by a RED player, fires OnDetonate with the shooter as activator", function()
	local bomb = HacksawBomb()
	T.eq(bomb:CreditsOwner(), true, "an arrow's owner is the attacker")
	local body = bomb:Body()
	T.eq(body.model, "models/props_mvm/mvm_human_skull_collide.mdl", "the map's model")
	T.eq(body.move, Hazards.MOVE_PHYSICS, "vphysics")
	local boom = bomb:Damaged(Shot(Teams.RED, 40))
	T.eq(boom.kind, EXPLODE, "health 1 dies")
	T.eq(boom.team, Teams.RED, "as the attacker's team")
	T.eq(boom.damage, 0, "hacksaw's bombs hurt nobody")
	T.eq(boom.radius, 100, "radius")
	T.eq(boom.halfFalloff, true, "DMG_HALF_FALLOFF")
	T.eq(boom.forceFriendlyFire, false, "friendlyfire 0")
	T.eq(boom.particles[1], "ghost_appearation", "particle")
	T.eq(boom.attachment, GenericBomb.EXPLODE_ATTACHMENT, "at alt-origin")
	T.eq(boom.sound, "misc/halloween/merasmus_appear.wav", "sound")
	T.eq(boom.gibs, true, "BreakModel")
	T.eq(boom.output, GenericBomb.OUTPUT_DETONATE, "OnDetonate")
	T.eq(GenericBomb.OUTPUT_DETONATE, "OnDetonate", "the output's name")
	T.eq(boom.activatorIsAttacker, true, "passActivator")
	T.eq(bomb:Input(GenericBomb.INPUT_DETONATE).kind, NONE, "detonates once")
	T.eq(bomb:Damaged(Shot(Teams.RED, 40)).kind, NONE, "dead")
end)

T.test("a zero-damage blast, like hacksaw's, hurts nobody and so sets off nothing", function()
	local explosion = Combat.Explosion.New({
		origin = V(0, 0, 0),
		radius = 100,
		damage = 0,
		attackerTeam = Teams.RED,
		halfFalloff = true,
	})
	T.eq(explosion:DamageTo({
		team = Teams.HALLOWEEN,
		isAttacker = false,
		distance = 10,
		visible = true,
	}), nil, "no damage at all (CTFRadiusDamageInfo::ApplyToEntity)")
end)

T.test("Detonate explodes a bomb for its own team, with no attacker to pass", function()
	local boom = HacksawBomb():Input(GenericBomb.INPUT_DETONATE)
	T.eq(boom.kind, EXPLODE, "Detonate")
	T.eq(boom.team, Teams.UNASSIGNED, "the bomb's own team")
	T.eq(boom.activatorIsAttacker, true, "passActivator still names the (absent) attacker")
	T.eq(HacksawBomb():Input("kill").kind, NONE, "other inputs are the engine's")
end)

T.test("a generic bomb with health soaks hits until its health is gone", function()
	local bomb = Hazards.New(GenericBomb, {
		damage = 100,
		radius = 150,
		health = 50,
		explodeParticle = "",
		sound = "",
		friendlyFire = GenericBomb.DAMAGE_EVERYONE,
		passActivator = false,
		team = Teams.UNASSIGNED,
		model = "models/props_td/atom_bomb.mdl",
		skin = 0,
		scale = 1,
	}, 0)
	T.eq(bomb:Damaged(Shot(Teams.BLUE, 30)).kind, NONE, "20 left")
	T.eq(bomb:Damaged(Shot(Teams.BLUE, 0)).kind, NONE, "nothing taken")
	local boom = bomb:Damaged(Shot(Teams.RED, 19.5))
	T.eq(boom.kind, EXPLODE, "0.5 left is 0 as an integer: dead")
	T.eq(boom.team, Teams.RED, "credited to the last attacker")
	T.eq(boom.forceFriendlyFire, true, "friendlyfire 1 hurts everyone")
	T.eq(boom.activatorIsAttacker, false, "without passActivator the bomb is the activator")
	T.eq(#boom.particles, 0, "no particle")
	T.eq(boom.sound, nil, "no sound")
end)

-- The zapper

local function NewZapper(type)
	return Hazards.New(Zapper, {
		type = type,
		particle = "merasmus_zap",
	}, 0)
end

local function Targets(outcome)
	if outcome.kind ~= ZAP then return outcome.kind end
	return table.concat(outcome.targets, ",")
end

T.test("scenario: an ON_TOUCH zapper zaps whoever is inside every 0.25 s, and stops when they leave", function()
	local zapper = NewZapper(Zapper.ZAP_ON_TOUCH)
	local clock = Fake.Clock(0)
	local log = {}
	local function Step(dt, touches)
		clock:Advance(dt)
		for _, t in ipairs(touches or {}) do zapper:Touch(Touch(t)) end
		local outcome = zapper:Tick(clock:Now())
		if outcome.kind ~= NONE then log[#log + 1] = string.format("%.3f=%s", clock:Now(), Targets(outcome)) end
	end
	Step(0.25)
	Step(0.25, { { target = "scout" } })
	Step(0.125)
	Step(0.125)
	Step(0.125, { { target = "heavy" } })
	Step(0.125)
	Step(0.125)
	Step(0.125, { {
		target = "scout",
		leaving = true,
	} })
	Step(0.125)
	Step(0.125, { {
		target = "heavy",
		leaving = true,
	} })
	Step(0.5)
	T.eq(table.concat(log, " "), "0.500=scout 0.750=scout 0.875=scout,heavy 1.125=scout,heavy 1.375=heavy", "zaps")
	T.eq(zapper:Team(), Teams.UNASSIGNED, "no team")
	T.eq(zapper:Body(), nil, "a point entity")
	T.eq(zapper:Damaged(Shot(Teams.RED, 100)).kind, NONE, "no damage")
end)

T.test("the zap is only a beam: its outcome names the particle", function()
	local zapper = NewZapper(Zapper.ZAP_ON_TOUCH)
	zapper:Touch(Touch({ target = "scout" }))
	local zap = zapper:Tick(0)
	T.eq(zap.kind, ZAP, "zap")
	T.eq(zap.particle, "merasmus_zap", "ParticleEffect")
	T.eq(zap.damage, nil, "no damage")
end)

T.test("ZapTouching zaps everyone inside at once, in either mode", function()
	local zapper = NewZapper(Zapper.ZAP_ON_TEST)
	T.eq(zapper:Input(Zapper.INPUT_ZAP_TOUCHING).kind, NONE, "nobody inside")
	zapper:Touch(Touch({ target = "scout" }))
	zapper:Touch(Touch({ target = "pyro" }))
	T.eq(zapper:Tick(0).kind, NONE, "ON_TEST never zaps by itself")
	T.eq(zapper:Tick(10).kind, NONE, "still not")
	T.eq(Targets(zapper:Input(Zapper.INPUT_ZAP_TOUCHING)), "scout,pyro", "ZapTouching")
	T.eq(Zapper.ZAP_ON_TOUCH, 0, "EZapperType")
	T.eq(Zapper.ZAP_ON_TEST, 1, "EZapperType")

	local touching = NewZapper(Zapper.ZAP_ON_TOUCH)
	touching:Touch(Touch({ target = "scout" }))
	T.eq(Targets(touching:Input(Zapper.INPUT_ZAP_TOUCHING)), "scout", "ON_TOUCH too")
	T.eq(Targets(touching:Tick(0)), "scout", "and its own cadence goes on")
end)

T.test("Disable stops the zapping; Enable resumes it while someone is inside", function()
	local zapper = NewZapper(Zapper.ZAP_ON_TOUCH)
	zapper:Touch(Touch({ target = "scout" }))
	T.eq(Targets(zapper:Tick(0)), "scout", "zapping")
	zapper:Input(Zapper.INPUT_DISABLE)
	T.eq(zapper:Tick(0.25).kind, NONE, "disabled")
	T.eq(zapper:Tick(5).kind, NONE, "still")
	T.eq(Targets(zapper:Input(Zapper.INPUT_ZAP_TOUCHING)), "scout", "ZapTouching ignores Disable")
	zapper:Input(Zapper.INPUT_ENABLE)
	T.eq(Targets(zapper:Tick(5)), "scout", "enabled: at once")
	T.eq(zapper:Tick(5.1).kind, NONE, "then every 0.25 s")
	T.eq(Targets(zapper:Tick(5.25)), "scout", "again")
	T.eq(zapper:Input("addoutput").kind, NONE, "other inputs are the engine's")
end)

T.test("a disabled ON_TOUCH zapper starts zapping again when someone new walks in (CTFHellZap::StartTouch)", function()
	local zapper = NewZapper(Zapper.ZAP_ON_TOUCH)
	zapper:Input(Zapper.INPUT_DISABLE)
	zapper:Touch(Touch({ target = "scout" }))
	T.eq(Targets(zapper:Tick(1)), "scout", "StartTouch schedules the think regardless")
end)

T.test("Enable with nobody inside starts nothing", function()
	local zapper = NewZapper(Zapper.ZAP_ON_TOUCH)
	zapper:Input(Zapper.INPUT_DISABLE)
	zapper:Input(Zapper.INPUT_ENABLE)
	T.eq(zapper:Tick(1).kind, NONE, "nobody")
end)

T.test("a hazard accepts only its own inputs, leaving Kill and AddOutput to the engine", function()
	T.eq(HacksawBomb():Accepts(GenericBomb.INPUT_DETONATE), true, "Detonate")
	T.eq(HacksawBomb():Accepts("kill"), false, "Kill")
	local zapper = NewZapper(Zapper.ZAP_ON_TEST)
	T.eq(zapper:Accepts(Zapper.INPUT_ENABLE), true, "Enable")
	T.eq(zapper:Accepts(Zapper.INPUT_DISABLE), true, "Disable")
	T.eq(zapper:Accepts(Zapper.INPUT_ZAP_TOUCHING), true, "ZapTouching")
	T.eq(zapper:Accepts("addoutput"), false, "AddOutput")
	T.eq(MapPumpkin():Accepts("kill"), false, "a pumpkin has no inputs")
end)

-- Gifts

T.test("gift spawn locations belong to Halloween", function()
	T.eq(Gift.HOLIDAY, Holiday.HALLOWEEN, "only while Halloween is on")
end)

T.test("scenario: a gift appears for each player, only its player can take it, and it despawns after 240 s", function()
	local draws = { 7, 1, 2, 12 }
	local schedule = Halloween.GiftSchedule(function()
		return table.remove(draws, 1)
	end)
	local locations = { V(0, 0, 0), V(100, 0, 0) }
	local players = { "scout", "soldier" }
	T.eq(#schedule:Tick(0, players, locations), 0, "the clock starts")
	T.eq(#schedule:Tick(419, players, locations), 0, "7 minutes not yet up")
	local spawned = schedule:Tick(420, players, locations)
	T.eq(#spawned, 2, "one gift per player")

	local now = 420
	local gifts = {}
	for i, g in ipairs(spawned) do
		gifts[i] = Gift.New({
			player = g.player,
			lifetime = Halloween.LIFETIME,
		}, now)
	end
	local scouts, soldiers = gifts[1], gifts[2]
	T.eq(scouts:Target(), "scout", "the scout's gift")
	T.eq(scouts:Touch("soldier"), false, "the soldier cannot take the scout's gift")
	T.eq(scouts:Touch("scout"), true, "the scout takes it")
	T.eq(scouts:Touch("scout"), false, "once")
	T.eq(scouts:Tick(now + 1000), Gift.NONE, "a taken gift is gone")

	T.eq(soldiers:Tick(now + 239), Gift.NONE, "still up")
	T.eq(soldiers:Tick(now + 240), Gift.DESPAWN, "240 s: tf_halloween_gift_lifetime")
	T.eq(soldiers:Target(), nil, "a despawned gift belongs to nobody")
	T.eq(soldiers:Touch("soldier"), false, "and nobody can take it")
	T.eq(soldiers:Tick(now + 240.5), Gift.NONE, "shown gone for a second")
	T.eq(soldiers:Tick(now + 241), Gift.REMOVE, "then removed")
	T.eq(soldiers:Tick(now + 242), Gift.NONE, "once")
end)

-- The bindings

local ENTITIES = "addon/gamemodes/sandcastle/entities/entities/"
local BINDINGS = {
	"tf_pumpkin_bomb.lua",
	"tf_generic_bomb.lua",
	"halloween_zapper.lua",
	"tf_halloween_gift_spawn_location.lua",
	"tf_halloween_gift_pickup.lua",
}

local function ReadFile(path)
	local f = assert(io.open(path, "r"))
	local text = f:read("*a")
	f:close()
	return text
end

-- A load inside a function is indented or on a one-line function.
local function LoadsAtTopLevel(line)
	if line:match("^%s") or line:match("^function ") then return false end
	return line:find("WETSAND.require", 1, true) ~= nil or line:find("WETSAND.Feature", 1, true) ~= nil
end

T.test("the hazard and gift bindings load nothing at top level", function()
	for _, file in ipairs(BINDINGS) do
		for line in ReadFile(ENTITIES .. file):gmatch("[^\n]+") do
			T.eq(LoadsAtTopLevel(line), false, file .. ": " .. line)
		end
	end
end)

T.finish()
