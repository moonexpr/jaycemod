-- The arena feature's controller. It owns the tf_logic_arena model
-- (features.arena.round), puts the round in the arena mode, and gives the
-- round the arena's convars: mp_arena_preround_time and mp_arena_round_time.
-- As the arena round starts it does what SetupOnStalemateStart's arena
-- branch does: fires OnArenaRoundStart, sets the round's cap-enable time
-- (mp_arena_override_cap_enable_time above 0, else the map's CapEnableDelay)
-- and plays the round-start line. Every 0.1 s it fires OnCapEnabled as that
-- time passes (CArenaLogic::ArenaLogicThink). It publishes the time for the
-- view (ws_arena_cap_enable_time) and that the round is arena's
-- (ws_round_arena).
--
-- Loaded by tf_logic_arena. It loads rounds.
local Arena = WS.require("features.arena.round")
local Rounds = gameplay.rounds

local THINK_INTERVAL = 0.1 -- ArenaLogicThink's
local THINK_HOOK = "ws_arena"

-- TF2's tf_arena_* convars (teamplayroundbased_gamerules.cpp, tf_gamerules.cpp),
-- named mp_arena_* here.
local preroundTime = CreateConVar("mp_arena_preround_time", "10", { FCVAR_NOTIFY, FCVAR_REPLICATED },
	"Length of the Pre-Round time", Arena.PREROUND_MIN, Arena.PREROUND_MAX)
local roundTime = CreateConVar("mp_arena_round_time", "0", { FCVAR_NOTIFY, FCVAR_REPLICATED },
	"Length of the arena round in seconds, shown as its timer; when it runs out the round is a stalemate. 0: untimed.")
local overrideCapEnableTime = CreateConVar("mp_arena_override_cap_enable_time", "-1", { FCVAR_REPLICATED, FCVAR_NOTIFY },
	"Overrides the time (in seconds) it takes for the capture point to become enable, -1 uses the level designer specified time.")

local Controller = {
	rounds = WS.Feature("rounds"),
	logicEnt = NULL,
	logic = nil,
	nextThink = 0,
}

-- CTFGameRules::Activate: a tf_logic_arena makes the game arena.
Controller.rounds:SetMode(Arena.Mode)
SetGlobal2Bool("ws_round_arena", true)

function Controller:Configure()
	self.rounds:ConfigureRound({
		arenaPreroundTime = preroundTime:GetInt(),
		arenaRoundTime = roundTime:GetInt(),
	})
end

-- Before the first pre-round reads them.
Controller:Configure()

-- The first tf_logic_arena is the one in charge (FindEntityByClassname).
-- kv = { capEnableDelay }, a number or nil.
function Controller:BindLogic(ent, kv)
	if IsValid(self.logicEnt) and self.logicEnt ~= ent then return end
	self.logicEnt = ent
	self.logic = Arena.New(kv)
end

-- A map reset removes the logic before its replacement binds.
function Controller:UnbindLogic(ent)
	if ent ~= self.logicEnt then return end
	self.logicEnt = NULL
	self.logic = nil
end

-- SetupOnStalemateStart, in arena.
function Controller:RoundStart()
	if not self.logic then return end
	local at = CurTime() + self.logic:CapEnableDelay(overrideCapEnableTime:GetFloat())
	self.rounds:SetCapEnableTime(at)
	SetGlobal2Float("ws_arena_cap_enable_time", at)
	WS.FireOutput(self.logicEnt, "OnArenaRoundStart", self.logicEnt)
	WS.BroadcastPA(WS.TEAM_UNASSIGNED, Arena.ROUND_START_LINE)
end

function Controller:Think(now)
	self:Configure()
	if self.logic and self.logic:Think(now, self.rounds:State(), self.rounds:CapEnableTime()) then
		WS.FireOutput(self.logicEnt, "OnCapEnabled", self.logicEnt)
	end
end

hook.Add("Think", THINK_HOOK, function()
	local now = CurTime()
	if now < Controller.nextThink or not WS.Active() then return end
	Controller.nextThink = now + THINK_INTERVAL
	Controller:Think(now)
end)

Controller.rounds:AddRoundListener(Rounds.PHASE_ARENA_START, Rounds.LISTEN_LOGIC, function() Controller:RoundStart() end)

return Controller
