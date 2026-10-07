-- TF2's Halloween bosses' shared rules (CHalloweenBaseBoss,
-- halloween_base_boss.cpp) as a template method. Variant(boss) turns a boss
-- part into a foundation.npc variant: the template owns spawn health, the
-- damage filter, attacker memory and the damage-per-second window, and the
-- top action BossBehavior, which contains the boss's emerge action and
-- changes to its dying action on death.
--
-- A boss part provides:
--   BOSS_TYPE, LOCOMOTION or HOVER, PATH (as any NPC variant)
--   Health(players, level, convars) -> n: players is the count of living
--     RED and BLU players, convars the binding's values of the boss's convars
--   ModifyDamage(state, damageEvent, me) -> amount (0 refuses the hit)
--   EmergeAction(state) -> Action, DyingAction(state) -> Action
-- and optionally:
--   Level(me) -> n (default 0), Setup(state, config, me) at spawn,
--   OnInjured(state, damageEvent, me), OnUpdate(state, me) each tick,
--   LeaveAction(state, me) -> Action | nil, asked each tick while alive
--     after OnUpdate: an action that replaces the whole behavior (Merasmus
--     escaping, CMerasmusBehavior::Update),
--   InterruptAction(state, damageEvent, me) -> Action | nil, asked on each
--     injury after OnInjured: an action the behavior suspends for, at
--     RESULT_IMPORTANT (Merasmus hiding, CMerasmusBehavior::OnInjured).
-- It must not define KIND, NewState, InitialAction or FilterDamage, which
-- Variant fills in.
--
-- The boss port (METHODS) extends the combatant port; the binding
-- halloween_base_boss implements it: Break() bursts the model into gibs,
-- FireGameEvent(name, fields) fires one of foundation.npc.boss_events'
-- game events to everyone, as TF2's gameeventmanager->FireEvent does.
local require = require
local NpcSystem = require("foundation.npc")
local Teams = require("foundation.teams")
local ipairs = ipairs
module(...)

-- HalloweenBossType
BOSS_INVALID, BOSS_HHH, BOSS_MONOCULUS, BOSS_MERASMUS = 0, 1, 2, 3

KIND = "boss"
DPS_WINDOW = 5 -- UpdateDamagePerSecond's windowDuration
SPAWN_HEIGHT = 10 -- SpawnBossAtPos lifts the boss this far

-- SpawnBossAtPos's entity class per boss type.
CLASSES = {
	[BOSS_HHH] = "headless_hatman",
	[BOSS_MONOCULUS] = "eyeball_boss",
	[BOSS_MERASMUS] = "merasmus",
}

METHODS = {
	"Break",
	"FireGameEvent",
}

function IsSpell(team)
	return team ~= Teams.HALLOWEEN
end

-- SpawnBossAtPos: the class, its Configure{} table and where to spawn it.
-- vector(x, y, z) builds the engine's vectors.
function SpawnAt(bossType, pos, team, owner, vector)
	local config = {
		team = team,
		owner = owner,
	}
	return CLASSES[bossType], config, pos + vector(0, 0, SPAWN_HEIGHT)
end

-- Whether t is one of the living RED and BLU players (TF2's ToTFPlayer,
-- for a target that is alive).
function IsPlayer(me, t)
	for _, ply in ipairs(me:CollectPlayers(nil)) do
		if ply == t then return true end
	end
	return false
end

-- RememberAttacker: every hit counts towards the DPS; each attacker is kept
-- once, with the time of its latest hit.
function RememberAttacker(state, attacker, damage, now)
	state.samples[#state.samples + 1] = {
		damage = damage,
		at = now,
	}
	for _, known in ipairs(state.attackers) do
		if known.attacker == attacker then
			known.at = now
			return
		end
	end
	state.attackers[#state.attackers + 1] = {
		attacker = attacker,
		at = now,
	}
end

-- UpdateDamagePerSecond: the damage no older than the window, per second.
-- Older samples are dropped, since they never count again.
function UpdateDamagePerSecond(state, now)
	local kept, total = {}, 0
	for _, sample in ipairs(state.samples) do
		if now - sample.at <= DPS_WINDOW then
			kept[#kept + 1] = sample
			total = total + sample.damage
		end
	end
	state.samples = kept
	state.dps = total / DPS_WINDOW
	if state.dps > state.maxDps then state.maxDps = state.dps end
end

-------------------------------------------------------------------------------
-- BossBehavior: the top action

local BossBehavior = NpcSystem.Action:Extend("BossBehavior")

function BossBehavior:Init(state)
	self.state = state
end

function BossBehavior:InitialContainedAction(me)
	return self.state.boss.EmergeAction(self.state)
end

-- CHalloweenBaseBoss::Update runs the behavior, then the DPS; the variant's
-- own per-tick work (CEyeballBoss::Update, CHeadlessHatman::Update) follows.
function BossBehavior:Update(me, interval)
	local state = self.state
	UpdateDamagePerSecond(state, me:Now())
	local onUpdate = state.boss.OnUpdate
	if onUpdate then onUpdate(state, me) end
	local leaveAction = state.boss.LeaveAction
	if leaveAction and me:IsAlive() then
		local leaving = leaveAction(state, me)
		if leaving then return self:ChangeTo(leaving, "Leaving") end
	end
	return self:Continue()
end

function BossBehavior:OnInjured(me, damageEvent)
	local state = self.state
	local onInjured = state.boss.OnInjured
	if onInjured then onInjured(state, damageEvent, me) end
	local interruptAction = state.boss.InterruptAction
	if interruptAction then
		local interrupting = interruptAction(state, damageEvent, me)
		if interrupting then return self:TrySuspendFor(interrupting, NpcSystem.RESULT_IMPORTANT, "Interrupted") end
	end
	return self:TryContinue()
end

function BossBehavior:OnKilled(me, damageEvent)
	return self:TryChangeTo(self.state.boss.DyingAction(self.state), NpcSystem.RESULT_CRITICAL, "I died!")
end

-------------------------------------------------------------------------------
-- The NPC variant hooks the template fills in

local function NewState(boss, config, me)
	local team = me:GetTeamNumber()
	local state = {
		boss = boss,
		team = team,
		spell = IsSpell(team),
		convars = config.convars,
		spawnedByCheats = config.cheats == true, -- m_wasSpawnedByCheats: sv_cheats was on
		level = boss.Level and boss.Level(me) or 0,
		attackers = {},
		samples = {},
		dps = 0,
		maxDps = 0,
	}
	local health = boss.Health(#me:CollectPlayers(nil), state.level, state.convars)
	me:SetMaxHealth(health)
	me:SetHealth(health)
	if boss.Setup then boss.Setup(state, config, me) end
	return state
end

-- OnTakeDamage_Alive: my own team and a won round do nothing; otherwise the
-- variant decides the amount taken, and a player's hit is remembered.
local function FilterDamage(state, damageEvent, me)
	local attacker = damageEvent.attacker
	if me:TeamOf(attacker) == state.team or me:RoundHasBeenWon() then return false end
	local amount = state.boss.ModifyDamage(state, damageEvent, me)
	if amount <= 0 then return false end
	if IsPlayer(me, attacker) then RememberAttacker(state, attacker, amount, me:Now()) end
	return true, amount
end

-- Fills the NPC variant's hooks into a boss part and returns it.
function Variant(boss)
	boss.KIND = KIND
	boss.NewState = function(config, me) return NewState(boss, config, me) end
	boss.InitialAction = function(state) return BossBehavior:New(state) end
	boss.FilterDamage = FilterDamage
	return boss
end
