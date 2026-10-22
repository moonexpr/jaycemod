-- The mvm feature's controller: CTFGameRules::Activate makes a map with a
-- tf_logic_mann_vs_machine MvM (features.mvm.model), and the flag panel
-- shows the bomb (ws_mvm). The bombs and their delivery are the flag
-- feature's; mvm_mannhattan's gates (trigger_timer_door) the capture
-- feature's.
--
-- One wave, with setup for the ready-up: each round's setup lasts
-- ws_mvm_setup_time on the map's team_round_timers, and its end starts the
-- wave, firing the popfile's StartWaveOutput (wave_start_relay). In the
-- wave a bomb at home goes to the invader in its spawn room nearest it, and
-- every invader in its spawn room is ubered while it stays.
--
-- Loaded by tf_logic_mann_vs_machine. It loads rounds and flag.
local Mvm = WS.require("features.mvm.model")
local Flag = WS.require("features.flag.model")
local Rounds = WS.require("games.gameplay.rounds")

local THINK_INTERVAL = 0.25
local THINK_HOOK = "ws_mvm"

local setupTime = CreateConVar("ws_mvm_setup_time", tostring(Mvm.SETUP_SECONDS), { FCVAR_NOTIFY, FCVAR_ARCHIVE },
	"Seconds of setup before an MvM wave starts, standing in for the ready-up (0: the map's own)", 0)

local Controller = {
	rounds = WS.Feature("rounds"),
	flag = WS.Feature("flag"),
	wave = false,
	nextThink = 0,
}

Controller.rounds:SetMode(Mvm.Mode)
SetGlobal2Bool("ws_mvm", true)

local INVADERS = Mvm.Mode.FLAG_INVADERS

local function Fire(output)
	for _, ent in ipairs(ents.FindByName(output.target)) do ent:Fire(output.input) end
end

-- The wave starts: the popfile's StartWaveOutput, then the bomb is handed out.
function Controller:StartWave()
	self.wave = true
	for _, output in ipairs(Mvm.WAVE_START_OUTPUTS) do Fire(output) end
end

-- The invaders' active spawn rooms.
local function InvaderRooms()
	local rooms = {}
	for _, room in ipairs(ents.FindByClass("func_respawnroom")) do
		if room.active and room.team == INVADERS then rooms[#rooms + 1] = room end
	end
	return rooms
end

-- The living invaders, players and soldiers, standing in any of rooms.
local function InSpawn(rooms)
	local inside = {}
	local function Check(ent)
		local point = ent:WorldSpaceCenter()
		for _, room in ipairs(rooms) do
			if room:PointIsWithin(point) then
				inside[#inside + 1] = ent
				return
			end
		end
	end
	for _, ply in ipairs(team.GetPlayers(INVADERS)) do
		if WS.IsAliveInGame(ply) then Check(ply) end
	end
	for _, member in ipairs(WS.TeamMembers(INVADERS)) do Check(member) end
	return inside
end

-- CTFBotMainAction::Update: uber, renewed while it stays.
local function Protect(invaders)
	for _, ent in ipairs(invaders) do
		for _, p in ipairs(Mvm.SPAWN_PROTECTION) do WS.AddCondition(ent, p.cond, p.seconds) end
	end
end

-- CTFBotFetchFlag: a bomb at home goes to an invader that has just spawned.
function Controller:HandOutBombs(invaders)
	if #invaders == 0 then return end
	for ent, flag in pairs(self.flag.flags) do
		if IsValid(ent) and flag:Enabled() and flag:Team() == INVADERS and flag:State() == Flag.HOME then
			local candidates = {}
			for _, invader in ipairs(invaders) do
				if not self:Carrying(invader) then candidates[#candidates + 1] = { ent = invader, pos = invader:GetPos() } end
			end
			local chosen = Mvm.BombCarrier(candidates, ent.wsHome)
			if chosen then self.flag:Give(ent, chosen.ent) end
		end
	end
end

function Controller:Carrying(ent)
	for _, flag in pairs(self.flag.flags) do
		if flag:Carrier() == ent then return true end
	end
	return false
end

function Controller:Think()
	local invaders = InSpawn(InvaderRooms())
	Protect(invaders)
	if self.wave then self:HandOutBombs(invaders) end
end

hook.Add("Think", THINK_HOOK, function()
	local now = CurTime()
	if now < Controller.nextThink then return end
	Controller.nextThink = now + THINK_INTERVAL
	Controller:Think()
end)

-- Setup's end, its clock run out or cut short, starts the wave.
hook.Add("WSSetup", THINK_HOOK, function(on)
	if not on and not Controller.wave then Controller:StartWave() end
end)

-- Each round: no wave yet, and the map's timers set to the ready-up's
-- setup. A map without setup starts its wave as the round does.
Controller.rounds:AddRoundListener(Rounds.PHASE_SPAWN, Rounds.LISTEN_LOGIC, function()
	Controller.wave = false
	local seconds = setupTime:GetInt()
	if seconds <= 0 then return end
	for _, ent in ipairs(ents.FindByClass("team_round_timer")) do
		local timer = Controller.rounds:TimerOf(ent)
		if timer and timer:InSetup() then Controller.rounds:TimerInput(ent, "setsetuptime", tostring(seconds)) end
	end
end)

Controller.rounds:AddRoundListener(Rounds.PHASE_ACTIVATE, Rounds.LISTEN_LOGIC, function()
	if not Controller.rounds:InSetup() then Controller:StartWave() end
end)

return Controller
