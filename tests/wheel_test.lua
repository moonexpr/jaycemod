local T = dofile("tests/harness.lua")
local FakeActor = dofile("tests/fake_actor.lua")
local Wheel = T.require("foundation.holiday.wheel")
local Players = T.require("foundation.players")
local Attributes = T.require("foundation.players.attributes")
local Teams = T.require("foundation.teams")

local V = FakeActor.Vector
local COND = Players.COND
local TICK = 0.015
local EPSILON = 1e-6
local DURATION = 20 -- the map's effect_duration

-- The wheel's world, as the wheel controller gives it, logging what it is
-- asked.
local function World(t)
	t = t or {}
	local world = {
		clock = FakeActor.Clock(t.now or 100),
		random = FakeActor.Random(t.random or { 0 }),
		players = t.players or {},
		spots = t.spots or {},
		calls = {},
		skin = Wheel.BLANK,
		visible = false,
		gravity = 1,
		status = nil,
		dancers = {},
	}
	local function Record(name, ...) world.calls[#world.calls + 1] = { name, ... } end
	function world:Now() return self.clock:Now() end
	function world:RandomInt(lo, hi) return self.random:Int(lo, hi) end
	function world:Vector(x, y, z) return V(x, y, z) end
	function world:Players() return self.players end
	function world:LivingPlayers()
		local living = {}
		for _, p in ipairs(self.players) do
			if p.alive ~= false then living[#living + 1] = p end
		end
		return living
	end
	function world:TeamOf(p) return p.team end
	function world:IsTargetValid(p) return p.valid ~= false end
	function world:AddCond(p, cond, duration)
		p.conds[cond] = duration
		Record("AddCond", p, cond, duration)
	end
	function world:RemoveCond(p, cond)
		p.conds[cond] = nil
		Record("RemoveCond", p, cond)
	end
	function world:SetAttribute(p, name, value) p.attrs[name] = value end
	function world:RemoveAttribute(p, name) p.attrs[name] = nil end
	function world:SetGravityMultiplier(m) self.gravity = m end
	function world:OtherWheels() return t.others or {} end
	function world:SetSkin(wheels, n)
		self.skin = n
		Record("SetSkin", wheels, n)
	end
	function world:SetScale(wheels, s)
		self.scale = s
		Record("SetScale", wheels, s)
	end
	function world:SetVisible(on) self.visible = on end
	function world:GrowSpirals(wheels) Record("GrowSpirals", wheels) end
	function world:ShrinkSpirals(wheels) Record("ShrinkSpirals", wheels) end
	function world:BroadcastSound(name) Record("BroadcastSound", name) end
	function world:Announce(name) Record("Announce", name) end
	function world:SetEffectStatus(skin, duration)
		self.status = {
			skin = skin,
			duration = duration,
		}
	end
	function world:ClearEffectStatus() self.status = nil end
	function world:FireOutput(name) Record("FireOutput", name) end
	function world:DanceSpot(teamName, n) return self.spots[teamName .. n] end
	function world:Teleport(p, pos, yaw)
		p.origin = pos
		p.yaw = yaw
		Record("Teleport", p, pos, yaw)
	end
	function world:Taunt(p) Record("Taunt", p) end
	function world:SpawnDancer(pos, yaw)
		local dancer = {
			pos = pos,
			yaw = yaw,
		}
		self.dancers[#self.dancers + 1] = dancer
		return dancer
	end
	function world:DancerVanish(d) d.vanished = true end
	function world:DancerBlastOff(d) d.blasted = true end
	return world
end

local function Player(team)
	return {
		team = team,
		conds = {},
		attrs = {},
	}
end

local function Called(world, name)
	local found = {}
	for _, call in ipairs(world.calls) do
		if call[1] == name then found[#found + 1] = call end
	end
	return found
end

local function Run(wheel, world, seconds)
	local steps = math.floor(seconds / TICK + 0.5)
	for _ = 1, steps do
		world.clock:Advance(TICK)
		wheel:Think(world)
	end
end

local function NewWheel(t)
	return Wheel.New({
		duration = (t and t.duration) or DURATION,
		hasSpiral = t and t.hasSpiral or false,
	})
end

-- Spin, and run to the moment the effect lands.
local function Landed(wheel, world)
	wheel:Spin(world)
	Run(wheel, world, Wheel.SPIN_TIME + Wheel.APPLY_DELAY + 2 * TICK)
end

local function EffectNamed(name)
	for i, effect in ipairs(Wheel.EFFECTS) do
		if effect.name == name then return i end
	end
	error("no effect " .. name)
end

-- Random draws that make the wheel choose the named effect: the choice
-- list holds the buffs in reverse order of registration, then the whammies;
-- each draw lands in the middle of its slot.
local function Choosing(name)
	local good, whammies = {}, {}
	for _, effect in ipairs(Wheel.EFFECTS) do
		if effect.whammy then whammies[#whammies + 1] = effect.name else table.insert(good, 1, effect.name) end
	end
	for i, n in ipairs(good) do
		if n == name then return { (i - 0.5) / (#good + 1) } end
	end
	for i, n in ipairs(whammies) do
		if n == name then return { (#good + 0.5) / (#good + 1), (i - 0.5) / #whammies } end
	end
	error("no effect " .. name)
end

-------------------------------------------------------------------------------
-- What it is (CWheelOfDoom)

T.test("the wheel keeps TF2's effects in TF2's order, with their skins, lines and flags", function()
	local names = {}
	for i, effect in ipairs(Wheel.EFFECTS) do names[i] = effect.name end
	T.eq(table.concat(names, ","), "Uber,Crits,Super Speed,Super Jump,Big Head,Small Head,Low Gravity,Dance,Burn", "registered")
	local burn = Wheel.EFFECTS[EffectNamed("Burn")]
	T.eq(burn.whammy, true, "a whammy")
	T.eq(burn.skin, Wheel.EFFECT_WHAMMY, "the whammy screen")
	T.eq(burn.sound, "Halloween.MerasmusWheelBurn", "its line")
	T.eq(burn.reapplies, false, "not on respawn")
	local uber = Wheel.EFFECTS[EffectNamed("Uber")]
	T.eq(uber.skin, Wheel.EFFECT_UBER, "uber skin")
	T.eq(uber.reapplies, true, "again for whoever respawns")
	T.eq(Wheel.EFFECTS[EffectNamed("Dance")].reapplies, false, "a dance is not rejoined")
	T.eq(Wheel.MODEL, "models/props_lakeside_event/buff_plane.mdl", "the screen")
	T.eq(Wheel.SPIRAL_MODEL, "models/props_lakeside_event/wof_plane2.mdl", "the spiral")
end)

-- GetRandomEffectWithFlags
T.test("a spin lands on a buff, or one time in buffs + 1 on a whammy", function()
	local world = World({ random = { 0 } })
	local wheel = NewWheel()
	wheel:Spin(world)
	T.eq(wheel.chosen.name, "Dance", "the first in the list: the last buff registered")
	world.random = FakeActor.Random({ 7.5 / 9 })
	wheel:Spin(world)
	T.eq(wheel.chosen.name, "Uber", "the last buff")
	world.random = FakeActor.Random(Choosing("Burn"))
	wheel:Spin(world)
	T.eq(wheel.chosen.name, "Burn", "the whammy")
end)

-------------------------------------------------------------------------------
-- The spin (StartSpin, SpinThink)

T.test("a spin shows the screen, plays the Wheel of Fate, ticks faster then slower, and lands after 6.75 s", function()
	local others = { "other wheel" }
	local world = World({
		random = Choosing("Crits"),
		players = { Player(Teams.RED) },
		others = others,
	})
	local wheel = NewWheel({ hasSpiral = true })
	wheel:Spin(world)
	T.eq(world.visible, true, "seen")
	T.eq(Called(world, "BroadcastSound")[1][2], "Halloween.WheelofFate", "the wheel's music for everyone")
	T.eq(Called(world, "GrowSpirals")[1][2], others, "the spirals grow")
	T.eq(wheel:IsDoneBroadcastingEffectSound(world:Now()), false, "busy")
	Run(wheel, world, 1.5)
	T.eq(#Called(world, "Announce"), 0, "no line yet")
	Run(wheel, world, 0.2)
	T.eq(Called(world, "Announce")[1][2], "Halloween.MerasmusWheelSpin", "Merasmus at 1.6 s")
	local ticks = Called(world, "SetSkin")
	T.eq(#ticks > 5, true, "the screen flicks through the faces: " .. #ticks)
	T.eq(ticks[1][2], others, "on every wheel")
	for _, tick in ipairs(ticks) do T.eq(tick[3] >= Wheel.EFFECT_WHAMMY and tick[3] < Wheel.EFFECT_COUNT, true, "a face") end
	Run(wheel, world, Wheel.SPIN_TIME - 1.7 + 0.5)
	T.eq(world.status, nil, "still spinning a second past the stop")
	Run(wheel, world, 0.6)
	T.eq(world.skin, Wheel.EFFECT_CRITS, "lands on crits")
	T.eq(world.scale, 1, "full size")
	T.eq(Called(world, "FireOutput")[1][2], Wheel.OUTPUT_APPLIED, "OnEffectApplied")
	T.eq(world.status.skin, Wheel.EFFECT_CRITS, "the HUD shows it")
	T.near(world.status.duration, DURATION, EPSILON, "for its time")
	T.eq(Called(world, "Announce")[2][2], "Halloween.MerasmusWheelCrits", "Merasmus names it")
end)

-- Bias( x, 0.3 ) on the spin's progress: 0.1 s apart at first, 0.55 at the end.
T.test("the screen ticks every 0.1 s at first and every 0.55 s at the end", function()
	T.near(Wheel.TickInterval(0), 0.1, EPSILON, "fast")
	T.near(Wheel.TickInterval(1), 0.55, EPSILON, "slow")
	T.near(Wheel.TickInterval(0.5), 0.1 + 0.45 * 0.5 ^ (math.log(0.3) / math.log(0.5)), EPSILON, "biased")
end)

T.test("a tick never shows the face already up, and wraps past the last to the first", function()
	T.eq(Wheel.NextFace(3, 3), 4, "skips the same")
	T.eq(Wheel.NextFace(Wheel.EFFECT_COUNT - 1, Wheel.EFFECT_COUNT - 1), Wheel.EFFECT_WHAMMY, "wraps over the blank")
	T.eq(Wheel.NextFace(5, 3), 5, "a different one stays")
end)

-------------------------------------------------------------------------------
-- Effects and their end (EffectManager, IdleThink)

T.test("crits and uber go to every player; uber lasts at most 10 s", function()
	local red, blue = Player(Teams.RED), Player(Teams.BLUE)
	local world = World({
		random = Choosing("Uber"),
		players = { red, blue },
	})
	local wheel = NewWheel()
	Landed(wheel, world)
	T.near(red.conds[COND.INVULNERABLE], 10, EPSILON, "red, 10 s")
	T.near(blue.conds[COND.INVULNERABLE], 10, EPSILON, "blue")
	T.near(world.status.duration, 10, EPSILON, "the HUD's 10 s")
	world.random = FakeActor.Random(Choosing("Crits"))
	Landed(wheel, world)
	T.near(red.conds[COND.CRITBOOSTED_PUMPKIN], DURATION, EPSILON, "pumpkin crits")
end)

T.test("speed, jump and heads are attributes until the effect ends; low gravity quarters it", function()
	local red = Player(Teams.RED)
	local world = World({ players = { red } })
	local wheel = NewWheel()
	local cases = {
		{
			name = "Super Speed",
			attrs = {
				[Attributes.MOVE_SPEED_BONUS] = 2,
			},
		},
		{
			name = "Super Jump",
			attrs = {
				[Attributes.JUMP_HEIGHT_BONUS] = 3,
				[Attributes.CANCEL_FALL_DAMAGE] = 1,
			},
		},
		{
			name = "Big Head",
			attrs = {
				[Attributes.HEAD_SCALE] = 3,
				[Attributes.VOICE_PITCH_SCALE] = 0.85,
			},
		},
		{
			name = "Small Head",
			attrs = {
				[Attributes.HEAD_SCALE] = 0.5,
				[Attributes.VOICE_PITCH_SCALE] = 1.3,
			},
		},
	}
	for _, case in ipairs(cases) do
		world.random = FakeActor.Random(Choosing(case.name))
		Landed(wheel, world)
		for name, value in pairs(case.attrs) do T.eq(red.attrs[name], value, case.name .. ": " .. name) end
		Run(wheel, world, DURATION + 0.2)
		T.eq(next(red.attrs), nil, case.name .. " ends")
	end
	world.random = FakeActor.Random(Choosing("Low Gravity"))
	Landed(wheel, world)
	T.eq(world.gravity, Wheel.LOW_GRAVITY, "a quarter")
	Run(wheel, world, DURATION + 0.2)
	T.eq(world.gravity, 1, "back")
end)

T.test("when an effect runs out the screen blanks and hides, OnEffectExpired fires and the HUD clears", function()
	local world = World({
		random = Choosing("Crits"),
		players = { Player(Teams.RED) },
		others = { "other" },
	})
	local wheel = NewWheel({ hasSpiral = true })
	Landed(wheel, world)
	world.calls = {}
	Run(wheel, world, DURATION - 0.5)
	T.eq(#Called(world, "FireOutput"), 0, "not yet")
	Run(wheel, world, 1)
	T.eq(Called(world, "FireOutput")[1][2], Wheel.OUTPUT_EXPIRED, "OnEffectExpired")
	T.eq(world.skin, Wheel.BLANK, "blank")
	T.eq(world.visible, false, "hidden")
	T.eq(world.status, nil, "the HUD clears")
	T.eq(Called(world, "ShrinkSpirals")[1][2][1], "other", "the spirals shrink")
end)

T.test("burn sets everyone alight for 10 s at most", function()
	local red = Player(Teams.RED)
	local world = World({
		random = Choosing("Burn"),
		players = { red },
	})
	local wheel = NewWheel()
	Landed(wheel, world)
	T.near(red.conds[COND.BURNING], 10, EPSILON, "10 s")
	T.near(world.status.duration, 10, EPSILON, "the HUD's 10 s")
	T.eq(world.status.skin, Wheel.EFFECT_WHAMMY, "the whammy face")
	local short = NewWheel({ duration = 4 })
	red.conds = {}
	world.random = FakeActor.Random(Choosing("Burn"))
	Landed(short, world)
	T.near(red.conds[COND.BURNING], 4, EPSILON, "the wheel's own duration when shorter")
end)

T.test("a player who respawns gets the effects that reapply, not burn or the dance", function()
	local red = Player(Teams.RED)
	local world = World({
		random = Choosing("Crits"),
		players = { red },
	})
	local wheel = NewWheel()
	Landed(wheel, world)
	Run(wheel, world, 5)
	local late = Player(Teams.BLUE)
	wheel:PlayerSpawned(world, late)
	T.near(late.conds[COND.CRITBOOSTED_PUMPKIN], DURATION - 5, 0.05, "crits for what is left")
	world.random = FakeActor.Random(Choosing("Burn"))
	Landed(wheel, world)
	local later = Player(Teams.RED)
	wheel:PlayerSpawned(world, later)
	T.eq(later.conds[COND.BURNING], nil, "no burn")
end)

T.test("ClearAllEffects ends what is running at once", function()
	local red = Player(Teams.RED)
	local world = World({
		random = Choosing("Super Speed"),
		players = { red },
	})
	local wheel = NewWheel()
	Landed(wheel, world)
	wheel:ClearAllEffects(world)
	T.eq(red.attrs[Attributes.MOVE_SPEED_BONUS], nil, "speed gone")
	T.eq(#Called(world, "FireOutput"), 1, "only OnEffectApplied: clearing fires nothing")
end)

T.test("the wheel is busy until 10 s after it stops", function()
	local world = World({ random = Choosing("Crits") })
	local wheel = NewWheel()
	T.eq(wheel:IsDoneBroadcastingEffectSound(world:Now()), true, "idle")
	wheel:Spin(world)
	Run(wheel, world, Wheel.SPIN_TIME + 9.9)
	T.eq(wheel:IsDoneBroadcastingEffectSound(world:Now()), false, "announcing")
	Run(wheel, world, 0.2)
	T.eq(wheel:IsDoneBroadcastingEffectSound(world:Now()), true, "done")
end)

-------------------------------------------------------------------------------
-- The dance (WOD_Dance)

local function DanceScene()
	local red1, red2, blue1 = Player(Teams.RED), Player(Teams.RED), Player(Teams.BLUE)
	local spots = {
		red0 = {
			pos = V(0, 0, 10),
			yaw = 0,
		},
		red1 = {
			pos = V(100, 50, 10),
			yaw = 0,
		},
		blue0 = {
			pos = V(200, -50, 10),
			yaw = 180,
		},
	}
	local world = World({
		random = Choosing("Dance"),
		players = { red1, red2, blue1 },
		spots = spots,
	})
	return world, red1, red2, blue1
end

T.test("the dance takes everyone alive to their team's dance spots, frozen in the thriller", function()
	local world, red1, red2, blue1 = DanceScene()
	local wheel = NewWheel()
	world.random = FakeActor.Random({ Choosing("Dance")[1], 0 })
	Landed(wheel, world)
	T.eq(red1.origin, V(0, 0, 10), "red's first spot")
	T.eq(red2.origin, V(100, 50, 10), "red's second")
	T.eq(blue1.origin, V(200, -50, 10), "blue's first")
	T.eq(blue1.yaw, 180, "facing as the spot")
	T.eq(red1.conds[COND.HALLOWEEN_THRILLER], Players.PERMANENT, "the thriller")
	T.near(world.status.duration, Wheel.DANCE_TIME, EPSILON, "8 s, whatever the wheel says")
end)

T.test("every 3.5 s they dance and a Merasmus pops up at one end of the floor, then the other", function()
	local world, red1 = DanceScene()
	local wheel = NewWheel()
	world.random = FakeActor.Random({ Choosing("Dance")[1], 0 })
	Landed(wheel, world)
	world.calls = {}
	Run(wheel, world, 1.4)
	T.eq(#Called(world, "Taunt"), 0, "not yet")
	Run(wheel, world, 0.2)
	T.eq(#Called(world, "Taunt"), 3, "everyone dances at 1.5 s")
	local first = world.dancers[1]
	T.eq(first.pos, V(100, -50, 10), "at the floor's middle x, its lowest y")
	T.eq(first.yaw, 90, "facing in")
	red1.origin = V(999, 999, 999)
	Run(wheel, world, Wheel.DANCE_INTERVAL + 2 * Wheel.IDLE_INTERVAL) -- the idle think runs every 0.1 s
	T.eq(red1.origin, V(0, 0, 10), "slammed back to the spot")
	T.eq(first.vanished, true, "the first Merasmus vanishes")
	T.eq(world.dancers[2].pos, V(100, 50, 10), "the next at the other end")
	T.eq(world.dancers[2].yaw, -90, "facing in")
	Run(wheel, world, Wheel.DANCE_TIME)
	T.eq(red1.conds[COND.HALLOWEEN_THRILLER], nil, "free")
	T.eq(world.dancers[#world.dancers].blasted, true, "the last Merasmus blasts off")
end)

T.test("with no dance spots nobody moves and no Merasmus dances", function()
	local red = Player(Teams.RED)
	local world = World({
		random = Choosing("Dance"),
		players = { red },
	})
	local wheel = NewWheel()
	Landed(wheel, world)
	Run(wheel, world, 2)
	T.eq(#world.dancers, 0, "no Merasmus")
	T.eq(red.conds[COND.HALLOWEEN_THRILLER], nil, "free")
end)

-- CTFHudPlayerHealth::UpdateHalloweenStatus
T.test("the HUD shows the effect's icon, blinking every 0.25 s in its last 3 s", function()
	T.eq(Wheel.HudIcon(Wheel.EFFECT_WHAMMY), "hud/death_wheel_whammy", "a whammy")
	T.eq(Wheel.HudIcon(Wheel.EFFECT_CRITS), "hud/death_wheel_7", "a buff: its face less one")
	T.eq(Wheel.HudVisible(10), true, "steady")
	T.eq(Wheel.HudVisible(2.9), true, "11 quarters left: an odd count shows")
	T.eq(Wheel.HudVisible(2.6), false, "10 quarters: an even count hides")
end)

-------------------------------------------------------------------------------
-- The port and the bindings

local ROOT = "addon/gamemodes/sandcastle/"

local function ReadFile(path)
	local f = assert(io.open(path, "r"))
	local text = f:read("*a")
	f:close()
	return text
end

T.test("the fake and the wheel controller implement every world method", function()
	local world = World()
	local controller = ReadFile(ROOT .. "gamemode/features/wheel/sv.lua")
	for _, name in ipairs(Wheel.METHODS) do
		T.eq(type(world[name]), "function", "fake " .. name)
		T.eq(controller:find("function world:" .. name .. "(", 1, true) ~= nil, true, "controller " .. name)
	end
end)

T.test("the wheel's entities load nothing at top level", function()
	for _, file in ipairs({ "wheel_of_doom.lua", "merasmus_dancer.lua" }) do
		for line in ReadFile(ROOT .. "entities/entities/" .. file):gmatch("[^\n]+") do
			local top = not (line:match("^%s") or line:match("^function "))
			local loads = line:find("WETSAND.require", 1, true) ~= nil or line:find("WETSAND.Feature", 1, true) ~= nil
			T.eq(top and loads, false, file .. ": " .. line)
		end
	end
end)

T.finish()
