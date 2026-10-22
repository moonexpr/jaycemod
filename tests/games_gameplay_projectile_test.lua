local T = dofile("tests/harness.lua")
local Fake = dofile("tests/fake_actor.lua")
local Projectile = T.require("games.gameplay.projectile")
local Grenade = T.require("games.gameplay.projectile.grenade")

local NONE, DETONATE, BOUNCE, EXPIRE = Projectile.NONE, Projectile.DETONATE, Projectile.BOUNCE, Projectile.EXPIRE

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

local function Throw(config, now)
	return Projectile.New(Grenade, config, now)
end

T.test("scenario: a timed grenade bounces about and detonates once when its fuse runs out", function()
	local clock = Fake.Clock(10)
	local g = Throw({ fuse = 2.5 }, clock:Now())
	T.eq(g:Gravity(), Grenade.GRAVITY, "a grenade falls")
	T.eq(Grenade.GRAVITY > 0, true, "ballistic")
	local outcomes = {}
	for step = 1, 20 do
		clock:Advance(0.25) -- exact in binary, so the fuse ends on a step
		if step == 2 then outcomes[#outcomes + 1] = g:Touch(WORLD) end
		if step == 4 then outcomes[#outcomes + 1] = g:Touch(ENEMY) end
		local o = g:Tick(clock:Now())
		if o ~= NONE then outcomes[#outcomes + 1] = o .. "@" .. string.format("%.2f", clock:Now()) end
	end
	T.eq(table.concat(outcomes, " "), BOUNCE .. " " .. BOUNCE .. " " .. DETONATE .. "@12.50", "outcomes")
	T.eq(g:IsFinished(), true, "finished")
	T.eq(g:Touch(ENEMY), NONE, "nothing after detonating")
end)

T.test("a grenade that explodes on touch does so on an enemy before it first hits the world", function()
	local g = Throw({
		fuse = 2,
		explodeOnTouch = true,
	}, 0)
	T.eq(g:Touch(FRIEND), BOUNCE, "a friend")
	T.eq(g:Touch(ENEMY), DETONATE, "an enemy")
	T.eq(g:Tick(5), NONE, "detonates once")
	g = Throw({
		fuse = 2,
		explodeOnTouch = true,
	}, 0)
	T.eq(g:Touch(WORLD), BOUNCE, "the world")
	T.eq(g:Touch(ENEMY), BOUNCE, "an enemy after a bounce off the world")
	T.eq(g:Tick(2), DETONATE, "the fuse still runs")
end)

T.test("a grenade without explodeOnTouch never detonates on touch", function()
	local g = Throw({ fuse = 2 }, 0)
	T.eq(g:Touch(ENEMY), BOUNCE, "enemy")
	T.eq(g:Tick(1.99), NONE, "before the fuse")
end)

T.test("a projectile past its lifetime expires, unless its fuse ran out first", function()
	local g = Throw({
		fuse = 10,
		lifetime = 5,
	}, 0)
	T.eq(g:Tick(4.9), NONE, "alive")
	T.eq(g:Tick(5), EXPIRE, "expired")
	T.eq(g:Tick(10), NONE, "once")
	g = Throw({
		fuse = 1,
		lifetime = 1,
	}, 0)
	T.eq(g:Tick(1), DETONATE, "the fuse wins a tie")
end)

T.finish()
