-- Part of the AI war controller (sv.lua): the soldier port
-- (features.aiwar.soldier) over a bot player (player.CreateNextBot, kept
-- by tf_bot_quota: sv_bots.lua), beside sv_soldier.lua's over a DrGBase
-- NextBot. It is that port where the two agree (routes, cover, kits,
-- gadgets, health kits) and differs where the body does: a player's body
-- plans no routes of its own (the orders walk its route), sees and fights
-- through its vision and body (games.nextsoldier.vision, player_body;
-- sv_bots.lua presses its keys), and neither sits on carts nor takes poses.
local Map, Soldier = ...
local Vision = nextsoldier.vision
local PlayerBody = nextsoldier.player_body
local ToVector, Point = Map.ToVector, Map.Point
local WALK_MINS, WALK_MAXS, WALK_LIFT, WALK_MAX_RISE = Map.WALK_MINS, Map.WALK_MAXS, Map.WALK_LIFT, Map.WALK_MAX_RISE

-- How long it keeps the jump key's wish when its orders ask a hop: long
-- enough to land on the ground and press it.
local HOP_WISH = 0.5
-- A hop's way is swept this high (a crouch jump's lift: a player's jump with
-- its legs tucked), and a bot hops at most once in HOP_RETRY seconds.
local HOP_CLEAR = Vector(0, 0, 56)
local HOP_RETRY = 6
-- How long it remembers an enemy out of sight, where last seen.
local MEMORY = 5

local BotSoldier = setmetatable({}, { __index = Soldier })
BotSoldier.__index = BotSoldier

-- reaction: the difficulty's (features.aiwar.marksmanship), before it
-- recognizes an enemy it sees.
function BotSoldier.New(ent, controller, team, reaction)
	return setmetatable({
		ent = ent,
		controller = controller,
		team = team,
		ticket = 0,
		result = nil,
		moveTarget = nil,
		relations = {},
		vision = Vision.New({
			reaction = reaction,
			memory = MEMORY,
		}),
		body = PlayerBody.New(),
		look = nil, -- where it faces with no enemy (Watch), a Vector
		hopUntil = 0,
		mayFire = false, -- its orders let it fire at its contact (sv_bots.lua asks them)
		loadout = nil, -- features.aiwar.arms' loadout it carries (KitBot)
		wantWeapon = nil, -- the weapon its contact's distance calls for
	}, BotSoldier)
end

function BotSoldier:IsAlive() return IsValid(self.ent) and self.ent:Alive() end

-- The enemy it fights: its vision's contact, while the enemy lives.
function BotSoldier:Enemy()
	local enemy = self.vision:Contact()
	return IsValid(enemy) and enemy or nil
end

function BotSoldier:HasEnemy()
	local enemy = self:Enemy()
	return enemy ~= nil and self.vision:Visible(enemy)
end

function BotSoldier:EnemyHealth()
	local enemy = self:Enemy()
	if not enemy or enemy:Health() <= 0 then return nil end
	return enemy:Health() / math.max(enemy:GetMaxHealth(), 1)
end

-- Where its enemy is: in sight, where it stands; out of it, where it was
-- last seen.
function BotSoldier:EnemyPosition()
	local enemy = self:Enemy()
	if not enemy then return nil end
	if self.vision:Visible(enemy) then return Point(enemy:GetPos()) end
	return (self.vision:LastKnown(enemy))
end

-- A player's body plans no route: the orders walk the route they ask for,
-- planned again once what blocks the nav mesh has changed since (a door
-- opened or shut, setup's gates gone: the npc feature's BlockerGeneration).
function BotSoldier:PlansRoutes() return false end

function BotSoldier:RequestRoute(goal)
	self.routeGeneration = WS.Feature("npc"):BlockerGeneration()
	Soldier.RequestRoute(self, goal)
end

function BotSoldier:RouteStale()
	return self.routeGeneration ~= nil and WS.Feature("npc"):BlockerGeneration() ~= self.routeGeneration
end

function BotSoldier:MoveTo(p, gait)
	self.moveTarget = p
	self.gait = gait or "run"
end

function BotSoldier:Release()
	self.moveTarget = nil
	self.walkSpeed = 0
end

function BotSoldier:Watch(p)
	self.look = p and ToVector(p) or nil
end

-- A clear walk under player movement's mask: what stops a player stops it.
function BotSoldier:CanWalkTo(p)
	local from, to = self.ent:GetPos(), ToVector(p)
	if math.abs(to.z - from.z) > WALK_MAX_RISE then return false end
	local tr = util.TraceHull({
		start = from + WALK_LIFT,
		endpos = to + WALK_LIFT,
		mins = WALK_MINS,
		maxs = WALK_MAXS,
		mask = MASK_PLAYERSOLID,
		filter = self.ent,
	})
	return not tr.Hit
end

-- What stands between me and p for a player's movement; a player passes
-- nothing that stops it.
function BotSoldier:Blocker(p)
	local controller = self.controller
	local from, to = self.ent:GetPos() + WALK_LIFT, ToVector(p) + WALK_LIFT
	local function NotSoldier(hit) return controller.soldiers[hit] == nil end
	local hit = util.TraceHull({ start = from, endpos = to, mins = WALK_MINS, maxs = WALK_MAXS, mask = MASK_PLAYERSOLID, filter = NotSoldier })
	if not hit.Hit then return nil, false end
	return hit.HitWorld and game.GetWorld() or hit.Entity, false
end

-- My movement heads straight for p (the orders' waypoint).
function BotSoldier:Heading(p) return ToVector(p) end

-- A hop: it jumps (a crouch jump) on its way to p, as a player would, where
-- a jump clears what stands between (a hull swept at the jump's height,
-- under player movement's mask), and not again within HOP_RETRY: a hop
-- that got it nowhere lets the orders step aside and plan again.
function BotSoldier:Hop(p)
	local now = CurTime()
	if now - (self.hoppedAt or -math.huge) < HOP_RETRY then return false end
	local from, to = self.ent:GetPos() + HOP_CLEAR, ToVector(p) + HOP_CLEAR
	local tr = util.TraceHull({ start = from, endpos = to, mins = WALK_MINS, maxs = WALK_MAXS, mask = MASK_PLAYERSOLID, filter = self.ent })
	if tr.Hit then return false end
	self.hoppedAt = now
	self.hopUntil = now + HOP_WISH
	return true
end

function BotSoldier:Hopping(now) return now < self.hopUntil end

-- Its path is the orders' route: nothing of its own to plan again.
function BotSoldier:Repath() end

-- A player's body neither sits on the cart nor strikes poses.
function BotSoldier:Sit() return false end
function BotSoldier:Pose() return nil end
function BotSoldier:Unpose() end

return BotSoldier
