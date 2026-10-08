-- The holiday feature's controller. It owns the foundation.holiday model
-- (the map's holiday, spells on or off, the active mode) and the mode's gift
-- schedule, reads TF2's convars once when it loads, and turns the model's
-- answers into entities: dropped spell pickups and gifts. It also owns the
-- fortune tellers' models, and carries out their outputs, sounds and
-- teleports.
local Holiday = WETSAND.require("foundation.holiday")

-- The holiday modes this gamemode registers, in order of preference.
local MODES = {
	WETSAND.require("foundation.holiday.halloween"),
}

local SPELL_PICKUP = "tf_spell_pickup"
local GIFT_PICKUP = "tf_halloween_gift_pickup"
local GIFT_THINK_INTERVAL = 1
local GIFT_TIMER = "wetsand_holiday_gifts"
local FORTUNE_MODEL = "foundation.holiday.fortune"

-- TF2's convars (tf_gamerules.cpp), server-only here.
local forcedHoliday = CreateConVar("tf_forced_holiday", "0", FCVAR_NOTIFY, "Forced holiday, \n   Birthday = 1\n   Halloween = 2\n")
local spellsEnabled = CreateConVar("tf_spells_enabled", "0", FCVAR_NOTIFY,
	"Enable to Allow Halloween Spells to be dropped and used by players")

local Controller = {
	holiday = Holiday.New({
		mapHoliday = Holiday.NONE,
		forced = forcedHoliday:GetInt(),
		spellsForced = spellsEnabled:GetBool(),
		modes = MODES,
	}),
	mode = nil,
	gifts = nil, -- the mode's gift schedule, when it has one
	giftLocations = {},
	fortunes = {}, -- fortune teller entity -> its foundation.holiday.fortune model
	fortuneEffects = nil,
}

-- A new mode brings its own gift schedule.
function Controller:ModeChanged()
	local mode = self.holiday:Mode()
	if mode == self.mode then return end
	self.mode = mode
	self.gifts = mode and mode.GiftSchedule(math.random)
end

-- tf_logic_holiday: kv = { holidayType, tauntInHell, allowHaunting }.
-- Hell's taunts are left out; allowHaunting lets the Wheel of Fate's
-- ghosts haunt a map that is no boss's scenario (BeginHaunting).
function Controller:BindHoliday(ent, kv)
	self.holiday:SetMapHoliday(kv.holidayType)
	self.allowHaunting = kv.allowHaunting
	self:ModeChanged()
end

-- CTFGameRules::BeginHaunting's permission (foundation.npc.ghost).
function Controller:HauntingAllowed()
	local Ghost = WETSAND.require("foundation.npc.ghost")
	return Ghost.HauntingAllowed(self:HolidayActive(Holiday.HALLOWEEN), self.bossScenario == true, self.allowHaunting == true)
end

function Controller:HolidayActive(h) return self.holiday:Active(h) end

-- TF2's Halloween scenarios, read from what the map places once its
-- entities are in (foundation.npc.boss_timer.Runs): a boss's scenario map
-- runs the boss timer, which brings him. A templated entity is not among
-- them until it spawns; the timer stops if the map's own boss does.
function Controller:StartBossScenarios()
	local BossTimer = WETSAND.require("foundation.npc.boss_timer")
	local map = {
		names = {},
		classes = {},
	}
	for _, ent in ipairs(ents.GetAll()) do
		local name = ent:GetName()
		if name ~= "" then map.names[name] = true end
		map.classes[ent:GetClass()] = true
	end
	for _, scenario in ipairs(BossTimer.SCENARIOS) do
		if BossTimer.Runs(scenario, map) then
			self.bossScenario = true
			WETSAND.Feature("boss_timer"):Run(scenario.variant)
		end
	end
end

hook.Add("InitPostEntity", "wetsand_holiday_boss_scenarios", function() Controller:StartBossScenarios() end)

-- tf_logic_on_holiday's Fire: the outputs for the holidays that are on. Its
-- part loads with the first Fire.
function Controller:OnHolidayOutputs()
	return WETSAND.require("foundation.holiday.on_holiday").Outputs(self.holiday)
end
function Controller:Mode() return self.holiday:Mode() end
function Controller:UsingSpells() return self.holiday:UsingSpells() end

-- Spells turning on load the spells feature, which hands out the books.
function Controller:SpellsChanged(changed)
	if changed and self.holiday:UsingSpells() then WETSAND.Feature("spells") end
end

function Controller:SetUsingSpells(on)
	self:SpellsChanged(self.holiday:SetUsingSpells(on))
end

-- A tf_spell_pickup the map placed reports itself as it initializes.
function Controller:SpellPickupPlaced()
	self:SpellsChanged(self.holiday:SpellPickupPlaced())
end

-- CTFGameRules::DropSpellPickup. The pickup flies with the velocity given
-- in its config.
function Controller:DropSpellPickup(pos, tier)
	local drop = self.holiday:SpellDrop(pos, math.Rand, Vector)
	if drop == nil then return end
	local pickup = ents.Create(SPELL_PICKUP)
	pickup:Configure({
		tier = tier,
		dropped = true,
		velocity = drop.velocity,
	})
	pickup:SetPos(drop.position)
	pickup:Spawn()
end

-- tf_halloween_gift_spawn_location
function Controller:AddGiftLocation(pos)
	self.giftLocations[#self.giftLocations + 1] = pos
end

-- tf_halloween_gift_pickup: config = { player, lifetime }.
function Controller:BindGift(ent, config)
	return WETSAND.require("foundation.holiday.gift").New(config, CurTime())
end

function Controller:SpawnGift(gift)
	local pickup = ents.Create(GIFT_PICKUP)
	pickup:Configure({
		player = gift.player,
		lifetime = self.mode.LIFETIME,
	})
	pickup:SetPos(gift.location)
	pickup:Spawn()
end

function Controller:ThinkGifts(now)
	if self.gifts == nil then return end
	for _, gift in ipairs(self.gifts:Tick(now, player.GetAll(), self.giftLocations)) do self:SpawnGift(gift) end
end

-- CTFGameRules::TeleportPlayersToTargetEntities, once the model has paired
-- the team with the spots: conditions cleared, the dead respawned, then
-- moved, facing the spot's way, at rest.
local function TeleportTeam(Fortune, teamNumber, target)
	for _, move in ipairs(Fortune.Teleports(team.GetPlayers(teamNumber), ents.FindByName(target), math.random)) do
		local ply, spot = move.player, move.spot
		WETSAND.RemoveAllConditions(ply)
		if not ply:Alive() then ply:Spawn() end
		ply:SetPos(spot:GetPos())
		ply:SetEyeAngles(spot:GetAngles())
		ply:SetLocalVelocity(vector_origin)
	end
end

-- A fortune teller's effects, by kind.
local function FortuneEffects(Fortune)
	return {
		[Fortune.OUTPUT] = function(ent, e) ent:TriggerOutput(e.name, ent) end,
		[Fortune.BROADCAST] = function(ent, e) WETSAND.BroadcastSound(WETSAND.TEAM_UNASSIGNED, e.sound) end,
		[Fortune.TELEPORT] = function(ent, e) TeleportTeam(Fortune, e.team, e.target) end,
	}
end

-- halloween_fortune_teller: kv = { redTeleport, blueTeleport }. The first
-- teller loads foundation.holiday.fortune.
function Controller:BindFortuneTeller(ent, kv)
	local Fortune = WETSAND.require(FORTUNE_MODEL)
	self.fortuneEffects = self.fortuneEffects or FortuneEffects(Fortune)
	local fortune = Fortune.New(kv, CurTime())
	self.fortunes[ent] = fortune
	return fortune
end

function Controller:UnbindFortuneTeller(ent)
	self.fortunes[ent] = nil
end

function Controller:CarryOutFortune(ent, effects)
	for _, e in ipairs(effects) do self.fortuneEffects[e.kind](ent, e) end
end

-- An input the teller accepts, lower-cased.
function Controller:FortuneInput(ent, name)
	self:CarryOutFortune(ent, self.fortunes[ent]:Input(name, CurTime()))
end

function Controller:ThinkFortune(ent)
	self:CarryOutFortune(ent, self.fortunes[ent]:Tick(CurTime()))
end

Controller:ModeChanged()

timer.Create(GIFT_TIMER, GIFT_THINK_INTERVAL, 0, function()
	Controller:ThinkGifts(CurTime())
end)

-- tf_spells_enabled 1 loads the spells feature once this one has finished
-- loading, since the spells controller may ask for this one.
if Controller.holiday:UsingSpells() then
	timer.Simple(0, function() WETSAND.Feature("spells") end)
end

return Controller
