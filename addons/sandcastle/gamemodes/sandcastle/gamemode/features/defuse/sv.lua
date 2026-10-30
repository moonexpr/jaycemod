-- The defuse feature's controller: CS:S's bomb defusal on its de_ maps,
-- made of MvM's bomb and TF2's control points. It puts the round in the
-- defuse mode (features.defuse.round) and owns the round's bomb
-- (features.defuse.model). Each round it makes:
--   the bomb, an item_teamflag RED carries (the flag feature's carry, drop
--   and pick-up), at the middle of RED's spawns;
--   for each func_bomb_target, a team_control_point BLU owns, with two
--   trigger_capture_areas on the site's brush: the plant area, RED's to
--   capture in planttime, open only while the bomb's carrier stands in the
--   site, and the defuse area, BLU's to capture in defusetime, open once the
--   bomb is planted there.
-- RED's capture plants the bomb where its carrier stands (the flag goes), a
-- quick capture after which arming the bomb holds every RED on the site,
-- stunned (the STUNNED condition, controls taken) for armtime; it
-- explodes after c4timer, hurting all within bombradius, and RED wins
-- (TARGET_BOMBED), unless BLU's capture defuses it first (BOMB_DEFUSED). The
-- bomb's state goes to the rounds (SetObjectiveState), whose mode
-- (features.defuse.round) keeps the round on once it is planted.
--
-- The map's settings are its cs_defuse_logic's (features.defuse.config),
-- made with the defaults on a map without one.
--
-- Loaded by func_bomb_target. It loads rounds, flag and capture.
local Defuse = WS.require("features.defuse.model")
local Round = WS.require("features.defuse.round")
local State = WS.require("games.gameplay.rounds.state")
local Rounds = gameplay.rounds

local THINK_INTERVAL = 0.1
local THINK_HOOK = "ws_defuse"
local LOGIC_CLASS = "cs_defuse_logic"
local RED, BLUE = WS.TEAM_RED, WS.TEAM_BLUE

-- CS:S's bomb: carried, planted, and its sounds.
local BOMB_MODEL = "models/weapons/w_c4.mdl"
local PLANTED_MODEL = "models/weapons/w_c4_planted.mdl"
local BEEP_SOUND = "weapons/c4/c4_beep1.wav"
local EXPLODE_SOUND = "weapons/c4/c4_explode1.wav"
local PLANT_SOUND = "weapons/c4/c4_plant.wav"
local DEFUSE_SOUND = "weapons/c4/c4_disarm.wav"
-- Its beep, every BEEP_EVERY seconds at first, faster as it nears its end.
local BEEP_EVERY, BEEP_FASTEST = 1, 0.15
-- The blast's damage at its centre, falling off to none at bombradius.
local BLAST_DAMAGE = 500
-- The sites' names, in the order of their entities.
local SITE_NAMES = { "A", "B", "C", "D" }

local Controller = {
	rounds = WS.Feature("rounds"),
	flag = WS.Feature("flag"),
	capture = WS.Feature("capture"),
	sites = {}, -- func_bomb_target -> { name, point, plant, defuse } (this round's entities)
	bomb = nil, -- features.defuse.model's round
	bombEnt = nil, -- the bomb, an item_teamflag, while it is carried or lies
	planted = nil, -- the planted bomb, a prop
	logic = nil,
	won = false,
	nextBeep = 0,
	nextThink = 0,
}

Controller.rounds:SetMode(Round.Mode)
SetGlobal2Bool("ws_round_arena", true)

-- The map's settings: its cs_defuse_logic's, made with the defaults on a map without one.
function Controller:Config()
	if not IsValid(self.logic) then
		self.logic = ents.FindByClass(LOGIC_CLASS)[1]
		if not IsValid(self.logic) then
			self.logic = ents.Create(LOGIC_CLASS)
			self.logic:Spawn()
		end
	end
	return self.logic:Config(nil)
end

function Controller:Configure()
	self.rounds:ConfigureRound({ defuseRoundTime = self:Config().roundTime })
end

function Controller:BindSite(ent) self.sites[ent] = { name = "?" } end
function Controller:UnbindSite(ent) self.sites[ent] = nil end

-- The sites in a fixed order (by entity index), each named A, B, ...
function Controller:SiteList()
	local list = {}
	for ent in pairs(self.sites) do
		if IsValid(ent) then list[#list + 1] = ent end
	end
	table.sort(list, function(a, b) return a:EntIndex() < b:EntIndex() end)
	return list
end

-- The middle of RED's spawns, on the floor: where the bomb starts.
local function BombHome()
	local spots = ents.FindByClass("info_player_terrorist")
	if #spots == 0 then spots = WS.SpawnPoints(RED) end
	local sum = Vector(0, 0, 0)
	for _, spot in ipairs(spots) do sum = sum + spot:GetPos() end
	local middle = sum / math.max(#spots, 1)
	local nearest = spots[1]
	for _, spot in ipairs(spots) do
		if spot:GetPos():DistToSqr(middle) < nearest:GetPos():DistToSqr(middle) then nearest = spot end
	end
	return nearest:GetPos() + Vector(0, 0, 8)
end

-- An entity of class made with keyvalues kv, set as the map's are and
-- recorded with them (WS.KeyValues, WS.FindByName): the record hears only the
-- map's own.
local function Made(class, kv, pos)
	local ent = ents.Create(class)
	for key, value in pairs(kv) do
		ent:SetKeyValue(key, value)
		WS.MapIO:RecordKeyValue(ent, key, value)
	end
	ent:SetPos(pos)
	ent:Spawn()
	return ent
end

local function Area(site, pointName, seconds, team)
	return Made("trigger_capture_area", {
		model = site:GetModel(),
		area_cap_point = pointName,
		area_time_to_cap = tostring(seconds),
		team_cancap_2 = team == RED and "1" or "0",
		team_cancap_3 = team == BLUE and "1" or "0",
		startdisabled = "1",
	}, site:GetPos())
end

-- This round's bomb and sites, made once each (a cleanup removes them).
function Controller:EnsureRoundEntities()
	local config = self:Config()
	local made = false
	for i, site in ipairs(self:SiteList()) do
		local s = self.sites[site]
		if not IsValid(s.point) then
			local name = "ws_defuse_site_" .. i
			s.name = SITE_NAMES[i] or tostring(i)
			s.point = Made("team_control_point", {
				targetname = name,
				point_index = tostring(i - 1),
				point_default_owner = tostring(BLUE),
				point_printname = "Bomb site " .. s.name,
			}, site:WorldSpaceCenter())
			s.plant = Area(site, name, config.plantTime, RED)
			s.defuse = Area(site, name, config.defuseTime, BLUE)
			made = true
		end
	end
	if made then self.capture:Rebuild() end
	if not IsValid(self.bombEnt) and self.bomb and self.bomb:State() == Defuse.CARRIED then
		local bomb = ents.Create("item_teamflag")
		bomb:SetKeyValue("teamnum", tostring(RED))
		bomb:SetKeyValue("flag_model", BOMB_MODEL)
		bomb:SetKeyValue("returntime", "100000")
		bomb:SetPos(BombHome())
		bomb:Spawn()
		self.bombEnt = bomb
	end
end

-- A new round: the bomb not yet planted.
function Controller:NewRound()
	self.bomb = Defuse.New()
	self.won = false
	SafeRemoveEntity(self.planted)
	SafeRemoveEntity(self.bombEnt)
	self.planted, self.bombEnt = nil, nil
	self.rounds:SetObjectiveState({ bomb = self.bomb })
end

-- Who carries the bomb now, or nil.
function Controller:Carrier()
	local flag = IsValid(self.bombEnt) and self.flag.flags[self.bombEnt]
	return flag and flag:Carrier() or nil
end

-- The site's point, as a site: its func_bomb_target, or nil.
function Controller:SiteOf(point)
	for site, s in pairs(self.sites) do
		if s.point == point then return site end
	end
	return nil
end

-- The plant areas open only to a carrier in their site: each area is enabled
-- while the bomb's carrier stands in its site, and no defuse area before the plant.
function Controller:OpenPlantAreas()
	local carrier = self:Carrier()
	for site, s in pairs(self.sites) do
		if IsValid(s.plant) then
			s.plant:Fire(IsValid(carrier) and site:Holds(carrier) and "Enable" or "Disable")
		end
	end
end

function Controller:Win(team, reason)
	if self.won then return end
	self.won = true
	self.rounds:SetWinningTeam(team, reason, true, false, false)
end

-- RED's capture of a site: the bomb is planted where its carrier stands.
function Controller:Plant(site)
	local config = self:Config()
	local carrier = self:Carrier()
	local at = IsValid(carrier) and carrier:GetPos() or site:WorldSpaceCenter()
	self.bomb = self.bomb:Plant(site, CurTime(), config.c4Timer)
	SafeRemoveEntity(self.bombEnt)
	self.bombEnt = nil
	local prop = ents.Create("prop_dynamic")
	prop:SetModel(PLANTED_MODEL)
	prop:SetPos(at)
	prop:Spawn()
	prop:EmitSound(PLANT_SOUND)
	self.planted = prop
	for other, s in pairs(self.sites) do
		if IsValid(s.plant) then s.plant:Fire("Disable") end
		if IsValid(s.defuse) then s.defuse:Fire(other == site and "Enable" or "Disable") end
	end
	self:Arming(site, config.armTime)
	self.nextBeep = CurTime()
	self.rounds:SetObjectiveState({ bomb = self.bomb })
	SetGlobal2Float("ws_defuse_explode_at", CurTime() + config.c4Timer)
	hook.Run("WSBombPlanted", site, carrier)
end

-- Arming the bomb: every living RED player on the site is stunned, its
-- controls taken, for seconds (the STUNNED condition, WS.StunPlayer's).
local ARMING_FLAGS = WS.PlayerRules.StunFlags(WS.PlayerRules.STUN_TYPE.CONTROLS)
local ARMING_SLOW = 1

function Controller:Arming(site, seconds)
	for _, ply in ipairs(team.GetPlayers(RED)) do
		if ply:Alive() and site:Holds(ply) then WS.StunPlayer(ply, seconds, ARMING_SLOW, ARMING_FLAGS) end
	end
end

-- BLU's capture of the planted site: the bomb is defused.
function Controller:Defused()
	self.bomb = self.bomb:Defuse()
	if IsValid(self.planted) then self.planted:EmitSound(DEFUSE_SOUND) end
	self.rounds:SetObjectiveState({ bomb = self.bomb })
	hook.Run("WSBombDefused", self.bomb:Site())
	self:Win(BLUE, Rounds.WINREASON.BOMB_DEFUSED)
end

-- The planted bomb's timer has run out: the blast, and RED wins.
function Controller:Explode(now)
	self.bomb = self.bomb:Explode(now)
	local pos = IsValid(self.planted) and self.planted:GetPos() or self.bomb:Site():WorldSpaceCenter()
	local effect = EffectData()
	effect:SetOrigin(pos)
	util.Effect("Explosion", effect, true, true)
	sound.Play(EXPLODE_SOUND, pos, 140)
	util.BlastDamage(IsValid(self.planted) and self.planted or game.GetWorld(), game.GetWorld(), pos, self:Config().bombRadius, BLAST_DAMAGE)
	SafeRemoveEntity(self.planted)
	self.planted = nil
	self.rounds:SetObjectiveState({ bomb = self.bomb })
	hook.Run("WSBombExploded", self.bomb:Site())
	self:Win(RED, Rounds.WINREASON.TARGET_BOMBED)
end

-- The planted bomb's beep, quicker as its end nears.
function Controller:Beep(now)
	if now < self.nextBeep or not IsValid(self.planted) then return end
	local left = self.bomb:Remaining(now)
	local fraction = math.Clamp(left / self:Config().c4Timer, 0, 1)
	self.nextBeep = now + math.max(BEEP_FASTEST, BEEP_EVERY * fraction)
	self.planted:EmitSound(BEEP_SOUND, 75)
end

hook.Add("WSPointCaptured", THINK_HOOK, function(point, team)
	local self = Controller
	local site = self:SiteOf(point)
	if not site or not self.bomb or self.won or self.rounds:State() ~= State.STALEMATE then return end
	if team == RED and self.bomb:State() == Defuse.CARRIED then
		self:Plant(site)
	elseif team == BLUE and self.bomb:State() == Defuse.PLANTED and self.bomb:Site() == site then
		self:Defused()
	end
end)

function Controller:Think(now)
	self:Configure()
	if not self.bomb then self:NewRound() end
	self:EnsureRoundEntities()
	-- the bomb is fought over only while the round runs: none after its win
	if self.rounds:State() ~= State.STALEMATE then return end
	local state = self.bomb:State()
	if state == Defuse.CARRIED then
		self:OpenPlantAreas()
	elseif state == Defuse.PLANTED then
		if self.bomb:Due(now) then self:Explode(now) else self:Beep(now) end
	end
end

hook.Add("Think", THINK_HOOK, function()
	local now = CurTime()
	if now < Controller.nextThink or not WS.Active() then return end
	Controller.nextThink = now + THINK_INTERVAL
	Controller:Think(now)
end)

-- Each round its bomb anew (the pre-round's cleanup removed the last one's
-- entities; Think makes them again).
Controller.rounds:AddRoundListener(Rounds.PHASE_SPAWN, Rounds.LISTEN_LOGIC, function() Controller:NewRound() end)

for _, path in ipairs({ BEEP_SOUND, EXPLODE_SOUND, PLANT_SOUND, DEFUSE_SOUND }) do util.PrecacheSound(path) end
util.PrecacheModel(BOMB_MODEL)
util.PrecacheModel(PLANTED_MODEL)

return Controller
