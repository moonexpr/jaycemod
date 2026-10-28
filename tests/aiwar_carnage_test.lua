-- Post-round carnage: wartactics.hunt (the winners' board of
-- sightings, where they hunt and where the losers hide), and the orders'
-- humiliation phase, driven as scenarios against tests/fake_soldier.lua.
local T = dofile("tests/harness.lua")
local FS = dofile("tests/fake_soldier.lua")
local Hunt = wartactics.hunt
local Teams = gameplay.teams

local RED, BLUE = Teams.RED, Teams.BLUE
local P = FS.Point

local function Near(p, q, what)
	T.eq(FS.Distance(p, q) < 1e-6, true, string.format("%s: (%g, %g) vs (%g, %g)", what, p.x, p.y, q.x, q.y))
end

-- The hunt's board -----------------------------------------------------------

T.test("a sighting is kept for HUNT_MEMORY, newest first, one per enemy, for its team only", function()
	local board = Hunt.Board.New()
	board:Report(BLUE, "red1", P(100, 0), 10)
	board:Report(BLUE, "red2", P(200, 0), 12)
	board:Report(BLUE, "red1", P(150, 0), 13)
	local seen = board:Sightings(BLUE, 14)
	T.eq(#seen, 2, "two enemies seen")
	T.eq(seen[1].subject, "red1", "the newest first")
	Near(seen[1].pos, P(150, 0), "where it was last seen")
	T.eq(seen[1].time, 13, "and when")
	T.eq(#board:Sightings(RED, 14), 0, "RED saw nothing")
	T.eq(#board:Sightings(BLUE, 12 + Hunt.HUNT_MEMORY), 2, "at the edge of memory")
	local later = board:Sightings(BLUE, 12 + Hunt.HUNT_MEMORY + 0.5)
	T.eq(#later, 1, "red2 forgotten")
	T.eq(later[1].subject, "red1", "red1 still remembered")
end)

T.test("the quarry is the nearest sighting", function()
	local sightings = {
		{
			subject = "far",
			pos = P(900, 0),
			time = 5,
		},
		{
			subject = "near",
			pos = P(0, 300),
			time = 4,
		},
	}
	T.eq(Hunt.Quarry(sightings, P(0, 0)).subject, "near", "nearest wins")
	T.eq(Hunt.Quarry({}, P(0, 0)), nil, "none seen")
end)

local function Field(spawns)
	return {
		winner = BLUE,
		spawns = spawns,
	}
end

T.test("a hunter goes for its quarry, else for the losers' spawns by slot", function()
	local spawns = {
		[RED] = { P(1000, 0), P(1000, 500), P(1000, 1000) },
		[BLUE] = { P(-1000, 0) },
	}
	local field = Field(spawns)
	local member = {
		team = BLUE,
		slot = 4,
	}
	local sightings = { {
		subject = "red1",
		pos = P(300, 20),
		time = 1,
	} }
	Near(Hunt.HuntGoal(field, member, sightings, P(0, 0)), P(300, 20), "the quarry")
	Near(Hunt.HuntGoal(field, member, {}, P(0, 0)), spawns[RED][4 % 3 + 1], "a losers' spawn, by slot")
	T.eq(Hunt.HuntGoal(Field(nil), member, {}, P(0, 0)), nil, "no spawns known: nowhere")
end)

T.test("a loser hides at its own nearest spawn", function()
	local spawns = {
		[RED] = { P(1000, 0), P(200, 0) },
		[BLUE] = { P(-1000, 0) },
	}
	local member = {
		team = RED,
		slot = 0,
	}
	Near(Hunt.Hideout(Field(spawns), member, P(0, 0)), P(200, 0), "the nearest of its own")
	T.eq(Hunt.Hideout(Field(nil), member, P(0, 0)), nil, "no spawns: no hideout")
	T.eq(Hunt.Hideout(Field({ [BLUE] = spawns[BLUE] }), member, P(0, 0)), nil, "none of its own")
end)

-- The humiliation phase in the soldiers' orders ------------------------------

local N = npc.nextbot
local AiWar = T.require("features.aiwar.model")
local Orders = T.require("features.aiwar.orders")
local Track = math.polyline
local STATE = T.require("games.gameplay.rounds.state")

local TICK = 0.25
local SEEK = "NextSoldier/StrategyMonitor/SeekAndDestroy"
-- A trip buries the action that took it: the trip shows, a level up. The
-- hunt's trips are weak: they give way to any enemy at hand.
local TRIP = "NextSoldier/StrategyMonitor/WeakTravel"
local HIDE_TRIP = "NextSoldier/StrategyMonitor/Travel"
local HUMILIATED = "NextSoldier/StrategyMonitor/Humiliated"
local SPAWNS = {
	[RED] = { P(3000, 0), P(3000, 800), P(-2000, 0) },
	[BLUE] = { P(-3000, 0) },
}

local function Cart(distance)
	local track = Track.New({ P(0, 0), P(4000, 0) })
	return {
		track = track,
		distance = distance,
		pos = track:PointAt(distance),
	}
end

-- A payload field in `phase` (humiliation by default) won by `winner`.
local function CarnageField(phase, winner)
	return {
		phase = phase or AiWar.PHASES.humiliation,
		winner = winner,
		doctrine = Orders.PAYLOAD,
		carts = { [BLUE] = Cart(1000) },
		spawns = SPAWNS,
	}
end

local function NewWar(field)
	local war = AiWar.War.New()
	war:Assign({ [BLUE] = true })
	war:SetField(field)
	return war
end

-- A soldier of t.team (BLU) in `war`, through its first update.
local function Enlist(war, t)
	local member = war:Enlist(t.handle or "me", t.team or BLUE, true)
	member.slot = t.slot or 0
	local me = FS.Soldier(t)
	local npc = N.Npc.New(Orders, {
		war = war,
		member = member,
	}, me)
	npc:Update(TICK)
	return me, npc, member
end

-- Whether the action is anywhere in the soldier's stack, active or buried.
local function Runs(npc, name)
	local _, frames = npc:Stack()
	for _, frame in ipairs(frames) do
		if frame.name == name then return true end
	end
	return false
end

local function Tick(me, npc, n)
	for _ = 1, n or 1 do
		me:Advance(TICK)
		npc:Update(TICK)
	end
end

T.test("the winners leave their jobs to seek and destroy, and will neither retreat nor dawdle", function()
	local war = NewWar(CarnageField(nil, BLUE))
	local me, npc = Enlist(war, { walkable = function() return true end })
	Tick(me, npc, 2)
	T.eq(Runs(npc, "SeekAndDestroy"), true, "seeking: " .. npc:Describe())
	T.eq(npc:Describe() == SEEK or npc:Describe() == TRIP, true, "its jobs buried: " .. npc:Describe())
	T.eq(npc:Query("ShouldRetreat"), N.ANSWER_NO, "no retreat")
	T.eq(npc:Query("ShouldHurry"), N.ANSWER_YES, "hurrying")
end)

T.test("a hunter runs at a loser it sees and reports it; another hunter goes where it was seen", function()
	local war = NewWar(CarnageField(nil, BLUE))
	local me, npc, member = Enlist(war, { handle = "hunter", walkable = function() return true end })
	me.enemy, me.enemyHandle, me.enemyPos = true, "red1", P(900, 0)
	Tick(me, npc, 2)
	Near(me.moving, P(900, 0), "at it")
	T.eq(me.gait, Orders.RUN, "running")
	local seen = war.hunt:Sightings(BLUE, me:Now())
	T.eq(#seen, 1, "reported")
	T.eq(seen[1].subject, "red1", "the loser seen")
	me.pos = P(900 - Orders.HUNT_CLOSE + 10, 0)
	Tick(me, npc)
	T.eq(me.holding, true, "close enough: it holds and fires")
	local other, otherNpc = Enlist(war, { handle = "second", slot = 1, walkable = function() return true end })
	Tick(other, otherNpc, 3)
	T.eq(otherNpc:Describe(), TRIP, "on a hunt trip")
	T.eq(Runs(otherNpc, "SeekAndDestroy"), true, "for the hunt")
	Near(otherNpc:State().goal, P(900, 0), "to the sighting")
	T.eq(other.gait, Orders.RUN, "at a run")
end)

T.test("with nothing seen, a hunter makes for a losers' spawn by its slot", function()
	local war = NewWar(CarnageField(nil, BLUE))
	local me, npc = Enlist(war, { slot = 4, walkable = function() return true end })
	Tick(me, npc, 3)
	T.eq(npc:Describe(), TRIP, "travelling")
	T.eq(Runs(npc, "SeekAndDestroy"), true, "for the hunt")
	Near(npc:State().goal, SPAWNS[RED][4 % 3 + 1], "the spawn its slot picks")
end)

T.test("a hunter on its way turns on a loser it sees at once, firing as it went", function()
	local war = NewWar(CarnageField(nil, BLUE))
	local me, npc = Enlist(war, { slot = 4, walkable = function() return true end })
	Tick(me, npc, 3)
	T.eq(npc:Describe(), TRIP, "travelling")
	T.eq(npc:Query("ShouldAttack", "red1"), N.ANSWER_YES, "it fires on the way")
	me.enemy, me.enemyHandle, me.enemyPos = true, "red1", P(-500, 300)
	Tick(me, npc)
	T.eq(npc:Describe(), SEEK, "the trip gave way that tick")
	Tick(me, npc)
	Near(me.moving, P(-500, 300), "at the loser the next")
end)

T.test("a hunter on its way to a spawn breaks off for a loser reported near it", function()
	local war = NewWar(CarnageField(nil, BLUE))
	local me, npc = Enlist(war, { slot = 4, walkable = function() return true end })
	Tick(me, npc, 3)
	local spawn = SPAWNS[RED][4 % 3 + 1]
	Near(npc:State().goal, spawn, "for the spawn")
	local near = P(me.pos.x + Hunt.PURSUE_REACH / 2, me.pos.y + 200)
	war.hunt:Report(BLUE, "red2", near, me:Now())
	Tick(me, npc, 2)
	Near(npc:State().goal, near, "to the loser reported nearby first")
end)

T.test("a hunter pays no mind to a loser reported far off", function()
	local war = NewWar(CarnageField(nil, BLUE))
	local me, npc = Enlist(war, { slot = 4, walkable = function() return true end })
	Tick(me, npc, 3)
	local goal = npc:State().goal
	war.hunt:Report(BLUE, "red3", P(me.pos.x, me.pos.y + Hunt.PURSUE_REACH * 3), me:Now())
	T.eq(Hunt.Pursues(war.hunt:Sightings(BLUE, me:Now()), me.pos, goal), nil, "too far to turn for")
end)

T.test("a loser flees a winner it sees, to cover away from it, else straight away", function()
	local war = NewWar(CarnageField(nil, BLUE))
	local cover = P(-300, 100)
	local me, npc = Enlist(war, { team = RED, covers = { cover }, walkable = function() return true end })
	me.disarmed = true
	Tick(me, npc)
	me.enemy, me.enemyPos = true, P(500, 0)
	Tick(me, npc, 2)
	T.eq(npc:Describe(), HUMILIATED, "humiliated")
	Near(me.moving, cover, "to cover")
	T.eq(npc:Query("ShouldAttack", "them"), N.ANSWER_NO, "holding fire")
	local bare, bareNpc = Enlist(war, { team = RED, handle = "bare", walkable = function() return true end })
	bare.disarmed = true
	Tick(bare, bareNpc)
	bare.enemy, bare.enemyPos = true, P(500, 0)
	Tick(bare, bareNpc, 2)
	Near(bare.moving, P(-Orders.RETREAT_DISTANCE, 0), "no cover: straight away from it")
end)

T.test("a loser picks new cover once its threat has moved FLEE_REPICK", function()
	local war = NewWar(CarnageField(nil, BLUE))
	local first, second = P(-300, 100), P(-100, -600)
	local me, npc = Enlist(war, { team = RED, covers = { first, second }, walkable = function() return true end })
	me.disarmed = true
	Tick(me, npc)
	me.enemy, me.enemyPos = true, P(500, 0)
	Tick(me, npc, 2)
	Near(me.moving, first, "the first cover")
	me.enemyPos = P(500, Hunt.FLEE_REPICK - 10)
	Tick(me, npc)
	Near(me.moving, first, "a small move: the same cover")
	me.enemyPos = P(500, Hunt.FLEE_REPICK + 10)
	Tick(me, npc)
	Near(me.moving, second, "moved far: new cover")
end)

T.test("a loser with no winner in sight runs to its nearest spawn and hides there", function()
	local war = NewWar(CarnageField(nil, BLUE))
	local me, npc = Enlist(war, { team = RED, walkable = function() return true end })
	me.disarmed = true
	Tick(me, npc, 3)
	T.eq(npc:Describe(), HIDE_TRIP, "on its way")
	T.eq(Runs(npc, "Humiliated"), true, "humiliated")
	Near(npc:State().goal, P(-2000, 0), "its nearest spawn")
	T.eq(me.gait, Orders.RUN, "running")
	me.pos = P(-2000 + Hunt.HIDE_ARRIVE - 10, 0)
	Tick(me, npc, 2)
	T.eq(npc:Describe(), HUMILIATED, "arrived")
	T.eq(me.holding, true, "hiding")
	T.eq(npc:Query("ShouldAttack", "them"), N.ANSWER_NO, "still holding fire")
	me.enemy, me.enemyPos = true, P(-1500, 0)
	Tick(me, npc)
	T.eq(me.moving ~= nil and me.moving.x < me.pos.x, true, "found: it flees again")
end)

T.test("the hunt ends with the round: frozen, then running, gives the soldier its job back", function()
	local war = NewWar(CarnageField(nil, BLUE))
	local me, npc = Enlist(war, { walkable = function() return true end })
	Tick(me, npc, 2)
	T.eq(Runs(npc, "SeekAndDestroy"), true, "hunting")
	war:SetField(CarnageField(AiWar.PHASES.frozen, nil))
	Tick(me, npc, 2)
	T.eq(Runs(npc, "SeekAndDestroy"), false, "the hunt is over")
	war:SetField(CarnageField(AiWar.PHASES.running, nil))
	Tick(me, npc, 2)
	T.eq(Orders.JobOf(npc:Describe()) ~= nil, true, "back to its job: " .. npc:Describe())
end)

T.test("a winner retreating to cover when the hunt begins leaves it within a tick", function()
	local war = NewWar(CarnageField(AiWar.PHASES.running, nil))
	local me, npc = Enlist(war, { enemyPos = P(1400, 0) })
	Tick(me, npc)
	me.health = 20
	Tick(me, npc)
	T.eq(npc:Describe(), "NextSoldier/StrategyMonitor/RetreatToCover", "retreating")
	war:SetField(CarnageField(nil, BLUE))
	Tick(me, npc)
	T.eq(npc:Describe() ~= "NextSoldier/StrategyMonitor/RetreatToCover", true, "left it")
	Tick(me, npc)
	T.eq(Runs(npc, "SeekAndDestroy"), true, "hunting")
end)

T.test("a stalemate has no winner: nobody hunts, and orders stop", function()
	local phase = AiWar.PhaseOf(true, STATE.TEAM_WIN, nil)
	local war = NewWar(CarnageField(phase, nil))
	local me, npc = Enlist(war, { walkable = function() return true end })
	Tick(me, npc, 3)
	T.eq(Runs(npc, "SeekAndDestroy"), false, "no hunt")
	T.eq(Orders.JobOf(npc:Describe()) ~= nil, true, "its job action, idle under the round's end")
	T.eq(#me.moves, 0, "standing")
end)

T.test("in sudden death both sides hunt, with no winner", function()
	local war = NewWar(CarnageField(AiWar.PhaseOf(true, STATE.STALEMATE), nil))
	local me, npc = Enlist(war, { walkable = function() return true end })
	Tick(me, npc, 2)
	T.eq(Runs(npc, "SeekAndDestroy"), true, "BLU hunts")
	T.eq(Orders.Hunting(war:Field(), { team = RED }), true, "and so does RED")
end)

T.test("the losers do not hunt the winners", function()
	local war = NewWar(CarnageField(nil, BLUE))
	local me, npc = Enlist(war, { team = RED, walkable = function() return true end })
	Tick(me, npc, 2)
	T.eq(Runs(npc, "SeekAndDestroy"), false, "RED lost")
end)

T.finish()
