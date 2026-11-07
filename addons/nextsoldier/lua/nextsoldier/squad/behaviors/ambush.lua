-- An ambush: a squad lies in wait inside a room, beside the entrance the most of the enemy's flow
-- comes in by, where one walking up to it does not see (room.watched), and is sprung by its leader
-- ("Now!") once one of it sees an enemy within SPRING_RANGE of the entrance, or is hurt. Lying in
-- wait it is a mission awaiting its leader's word: its members hold their fire.
--
-- Ambush(room) -> an order (room: as an assault's, with watched(point, entrance) and its entrances'
-- enemyFlow; refused where it cannot hide, or no enemy is known to come): Places(members, spacing[,
-- admit]) -> each member's place within AMBUSH_REACH of the entrance, hidden, spacing apart, nearest
-- it; Spring() (true the once), Sprung(). Its leggings' action is LegsAmbush: to its place at a run,
-- there crouched; sprung, it fights from where it lies; falling back, it evacuates.
local Action = nextsoldier.behavior.action
local Orders = nextsoldier.squad.orders
local Radio = nextsoldier.squad.comms.radio
local Legs = nextsoldier.squad.behaviors.legs
local GIB = nextsoldier.behavior.gib_behaviors
local Geometry = math.geometry
local ipairs, error = ipairs, error
module("nextsoldier.squad.behaviors.ambush")

-- How far from the entrance its members lie in wait, and how near it an enemy springs it.
AMBUSH_REACH, SPRING_RANGE = 320, 300

local Lurk = Orders.Kind()

function Lurk:Places(members, spacing, admit)
	admit = admit or function(slot) return slot end
	self.size = #members
	local room, entrance = self.room, self.entrance
	local hidden = {}
	for _, p in ipairs(Legs.Floor(room, spacing, admit)) do
		if Geometry.Distance2D(p, entrance) <= AMBUSH_REACH and Legs.Hidden(room.watched, p, entrance) then
			hidden[#hidden + 1] = p
		end
	end
	return Legs.Assign(entrance, Legs.Nearest(hidden, entrance, #members, spacing), members)
end

function Lurk:Spring()
	if self.sprung then return false end
	self.sprung = true
	return true
end

function Lurk:Sprung() return self.sprung == true end

function Ambush(room)
	if not room.watched then error("an ambush lies out of its enemy's sight: the room's watched", 2) end
	local entrance
	for _, e in ipairs(room.entrances or {}) do
		if (e.enemyFlow or 0) > 0 and (not entrance or e.enemyFlow > entrance.enemyFlow) then entrance = e end
	end
	if not entrance then error("an ambush waits where the enemy comes in: no entrance has the enemy's flow", 2) end
	return Orders.New(Lurk, { kind = "Ambush", point = room.center, entrance = entrance.pos, room = room, exits = room.exits })
end

LegsAmbush = Action.Extend("LegsAmbush")

-- It contains nothing: lying in wait is all it does.
function LegsAmbush:InitialContainedAction() return nil end

function LegsAmbush:Update(me)
	local result = Legs.OnOrders(self, me)
	if result.type ~= Action.CONTINUE then return result end
	local order = self.order
	local fall = Legs.Evacuating(self)
	if fall then return fall end
	if not order:Sprung() then
		local enemy = me:NSLegsEnemyAt()
		if (enemy and Geometry.Distance2D(enemy, order.entrance) <= SPRING_RANGE) or me:NSLegsHurt() then order.reported = true end
		if order.reported and order.leader == me and order:Spring() then Legs.Speak(me, order, Radio.SQUAD, "NOW") end
	end
	local place = me:NSLegsPlace() or me:NSLegsAt()
	local there = Geometry.Distance2D(me:NSLegsAt(), place) <= GIB.STAGE_REACH
	me:NSLegsHeadFor(place, there and GIB.GAIT.REST or GIB.GAIT.RUN)
	return self:Continue()
end

Orders.Register({
	kind = "Ambush",
	action = LegsAmbush,
	awaiting = function(order) return not order.routed and not order:Sprung() end,
	underway = function(order) return not order.routed end,
})
