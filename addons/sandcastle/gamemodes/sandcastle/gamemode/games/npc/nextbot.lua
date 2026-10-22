-- The NPC system: the Npc model that runs one variant's Behavior against an
-- actor port. The Action/Behavior engine and its timers are
-- games.generator.hfsm's; this module hands on their NextBot names so a
-- variant reads Npc.Action, Npc.CHANGE_TO, Npc.CountdownTimer.
--
-- An NPC variant is a part of this system (games.npc.nextbot.<variant>) and
-- provides KIND, LOCOMOTION or HOVER, PATH, NewState(config, actor),
-- InitialAction(state), and optionally FilterDamage(state, damageEvent,
-- actor) -> taken[, amount], Cull(liveStates), PARTICLES (every particle system its NPCs
-- dispatch; see Particles) and PLAYERS_PASS_THROUGH (true when players and
-- the NPC never block each other: its locomotion's ShouldCollideWith
-- refuses players). Actions receive the actor as `me`.
local ipairs, setmetatable = ipairs, setmetatable
local remove = table.remove
local Hfsm = require("games.generator.hfsm")
module(...)

CONTINUE, CHANGE_TO, SUSPEND_FOR, DONE, SUSTAIN =
	Hfsm.CONTINUE, Hfsm.CHANGE_TO, Hfsm.SUSPEND_FOR, Hfsm.DONE, Hfsm.SUSTAIN
RESULT_NONE, RESULT_TRY, RESULT_IMPORTANT, RESULT_CRITICAL =
	Hfsm.RESULT_NONE, Hfsm.RESULT_TRY, Hfsm.RESULT_IMPORTANT, Hfsm.RESULT_CRITICAL
ANSWER_NO, ANSWER_YES, ANSWER_UNDEFINED = Hfsm.ANSWER_NO, Hfsm.ANSWER_YES, Hfsm.ANSWER_UNDEFINED
INTERVAL_UNSTARTED = Hfsm.INTERVAL_UNSTARTED
Action, Behavior = Hfsm.Action, Hfsm.Behavior
CountdownTimer, IntervalTimer = Hfsm.CountdownTimer, Hfsm.IntervalTimer

-------------------------------------------------------------------------------
-- Npc: one NPC's variant, state and Behavior

Npc = {}
Npc.__index = Npc

function Npc.New(variant, config, actor)
	local state = variant.NewState(config, actor)
	return setmetatable({
		variant = variant,
		state = state,
		actor = actor,
		behavior = Behavior:New(variant.InitialAction(state), variant.KIND),
	}, Npc)
end

function Npc:Update(interval) self.behavior:Update(self.actor, interval) end
function Npc:Event(name, ...) self.behavior:Event(self.actor, name, ...) end
function Npc:Query(name, ...) return self.behavior:Query(self.actor, name, ...) end
function Npc:State() return self.state end
function Npc:Describe() return self.behavior:Describe() end
function Npc:IsEmpty() return self.behavior:IsEmpty() end
function Npc:Watch(watcher) self.behavior:Watch(watcher) end
function Npc:Stack() return self.behavior.name, self.behavior:Stack() end
function Npc:Destroy() self.behavior:Destroy() end

-- Whether the hit is taken, and the amount taken when the variant changes
-- it (nil: as dealt). FilterDamage is optional in a variant; without it all
-- damage is taken as dealt.
function Npc:FilterDamage(damageEvent)
	local filter = self.variant.FilterDamage
	if filter == nil then return true end
	return filter(self.state, damageEvent, self.actor)
end

-- After a new NPC binds, the variant's Cull picks which of the live NPCs of
-- that variant (given oldest first) must suicide; each gets
-- `state.culled = true`, which the variant's Behavior reads. Returns the
-- culled states.
function Cull(variant, npcs)
	if variant.Cull == nil then return {} end
	local live = {}
	for _, npc in ipairs(npcs) do
		if npc.actor:IsAlive() then live[#live + 1] = npc.state end
	end
	local culled = variant.Cull(live)
	for _, state in ipairs(culled) do state.culled = true end
	return culled
end

-- The particle systems a variant's NPCs dispatch, which the npc controller
-- precaches when the variant first binds: its PARTICLES, or none.
function Particles(variant)
	if variant.PARTICLES == nil then return {} end
	return variant.PARTICLES
end

-------------------------------------------------------------------------------
-- Group: an event responder over Npcs (CTFBotSquad's contained responders):
-- an event sent to the group reaches each member, in the order they joined.

Group = {}
Group.__index = Group

function Group.New()
	return setmetatable({ members = {} }, Group)
end

function Group:Add(npc)
	for _, member in ipairs(self.members) do
		if member == npc then return end
	end
	self.members[#self.members + 1] = npc
end

function Group:Remove(npc)
	for i, member in ipairs(self.members) do
		if member == npc then
			remove(self.members, i)
			return
		end
	end
end

function Group:Members() return self.members end

function Group:Event(name, ...)
	for _, member in ipairs(self.members) do member:Event(name, ...) end
end
