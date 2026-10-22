-- Point snapshots and fields for the point scenarios' tests
-- (foundation.aiwar.scenario.control_points and .koth), in the shape the
-- aiwar controller builds them (docs/aiwar-koth-cp.md §2.4), and a battle:
-- War + the scenario's Command + Orders + tests/fake_soldier.lua soldiers,
-- ticked together, each soldier walking FP.SPEED toward where it was last
-- told to move.
local H = dofile("tests/harness.lua")
local FS = dofile("tests/fake_soldier.lua")
local N = H.require("games.npc.nextbot")
local AiWar = H.require("foundation.aiwar")
local Orders = H.require("foundation.aiwar.orders")
local Teams = H.require("games.gameplay.teams")

local FP = {}

local RED, BLUE, NOBODY = Teams.RED, Teams.BLUE, Teams.UNASSIGNED
local P = FS.Point

FP.TICK = 0.25
FP.SPEED = 400 -- units a second
FP.RADIUS = 200 -- a zone's, by default

-- The sides' bases, on the x axis either side of the origin.
FP.BASES = {
	[RED] = P(-3000, 0),
	[BLUE] = P(3000, 0),
}

-- t = { rank, at (the point's origin and its zone's center), radius (the
-- zone's; false: no zone), owner, locked, capping, progress, blocked,
-- mayCapture = { [team] = true }, inRound (default true), hidden }.
function FP.Point(t)
	local may = t.mayCapture or {}
	return {
		id = "point" .. t.rank,
		rank = t.rank,
		pos = t.at,
		zone = t.radius ~= false and {
			center = t.at,
			radius = t.radius or FP.RADIUS,
		} or nil,
		owner = t.owner or NOBODY,
		locked = t.locked == true,
		capping = t.capping or NOBODY,
		progress = t.progress or 0,
		blocked = t.blocked == true,
		mayCapture = {
			[RED] = may[RED] == true,
			[BLUE] = may[BLUE] == true,
		},
		inRound = t.inRound ~= false,
		hidden = t.hidden == true,
	}
end

-- Each team's clock: { left, running }.
function FP.Clocks(red, blue)
	return {
		[RED] = {
			left = red,
			running = true,
		},
		[BLUE] = {
			left = blue,
			running = true,
		},
	}
end

function FP.Field(t)
	return {
		phase = t.phase or AiWar.PHASES.running,
		points = t.points,
		clocks = t.clocks,
		timeLeft = t.timeLeft,
		overtime = t.overtime == true,
		bases = t.bases or FP.BASES,
		spawns = t.spawns,
		setup = t.setup == true,
		gates = t.gates,
		posts = t.posts,
		lanes = t.lanes,
		-- the nav mesh's, which the controller's field always carries
		waypoints = t.waypoints or {},
	}
end

function FP.InZone(pos, point)
	return Orders.InSphere(pos, point.zone.center, point.zone.radius)
end

-- The battle ---------------------------------------------------------------------

local Battle = {}
Battle.__index = Battle

-- scenario: a variant's Scenario class. Its squads are of its size, as
-- the controller makes them, and fill one by one (no squads min), so a
-- battle's squadmates fight together.
function FP.Battle(scenario)
	local war = AiWar.War.New()
	war:SetFireTeamSize(scenario.SQUAD_SIZE)
	war:SetSquadsMin(1)
	return setmetatable({
		scenario = scenario:New(),
		war = war,
		now = 0,
		soldiers = {},
	}, Battle)
end

-- count soldiers of team, each a fake soldier made from soldier (a
-- function of its index -> Fake.Soldier's t, or nil).
function Battle:Enlist(team, count, soldier)
	for i = 1, count do
		local handle = (team == RED and "red" or "blue") .. i
		local t = soldier and soldier(i) or {}
		t.now = self.now
		t.pos = t.pos or FS.Point(FP.BASES[team].x, FP.BASES[team].y)
		self.soldiers[#self.soldiers + 1] = {
			member = self.war:Enlist(handle, team, true),
			me = FS.Soldier(t),
		}
	end
end

-- The controller's think, as far as the models go: the scenario's
-- Command, then the war's field.
function Battle:Command(field)
	self.scenario:Command(self.war, field, self.now)
	self.war:SetField(field)
end

-- The first think: roles given, then each soldier's orders started.
function Battle:Start(field)
	self:Command(field)
	for _, s in ipairs(self.soldiers) do
		s.npc = N.Npc.New(Orders, {
			war = self.war,
			member = s.member,
		}, s.me)
		s.npc:Update(FP.TICK)
	end
end

local function Walk(me, step)
	local to = me.moving
	if not to then return end
	local d = FS.Distance(me.pos, to)
	if d <= step then
		me.pos = P(to.x, to.y, to.z)
		return
	end
	me.pos = P(me.pos.x + (to.x - me.pos.x) * step / d, me.pos.y + (to.y - me.pos.y) * step / d, me.pos.z + (to.z - me.pos.z) * step / d)
end

function Battle:Tick(field, n)
	for _ = 1, n or 1 do
		self.now = self.now + FP.TICK
		self:Command(field)
		for _, s in ipairs(self.soldiers) do
			s.me.now = self.now
			s.npc:Update(FP.TICK)
			Walk(s.me, FP.SPEED * FP.TICK)
		end
	end
end

-- The soldiers of team in job.
function Battle:Of(team, job)
	local list = {}
	for _, s in ipairs(self.soldiers) do
		if s.member.team == team and s.member.role == job then list[#list + 1] = s end
	end
	return list
end

-- How many of team's members are in job.
function Battle:Count(team, job)
	local n = 0
	for _, member in pairs(self.war.members) do
		if member.team == team and member.role == job then n = n + 1 end
	end
	return n
end

return FP
