-- The holiday feature's controller. It owns the foundation.holiday model
-- (the map's holiday, spells on or off, the active mode) and the mode's gift
-- schedule, reads TF2's convars once when it loads, and turns the model's
-- answers into entities: dropped spell pickups and gifts.
local Holiday = WETSAND.require("foundation.holiday")

-- The holiday modes this gamemode registers, in order of preference.
local MODES = {
	WETSAND.require("foundation.holiday.halloween"),
}

local SPELL_PICKUP = "tf_spell_pickup"
local GIFT_PICKUP = "tf_halloween_gift_pickup"
local GIFT_THINK_INTERVAL = 1
local GIFT_TIMER = "wetsand_holiday_gifts"

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
}

-- A new mode brings its own gift schedule.
function Controller:ModeChanged()
	local mode = self.holiday:Mode()
	if mode == self.mode then return end
	self.mode = mode
	self.gifts = mode and mode.GiftSchedule(math.random)
end

-- tf_logic_holiday: kv = { holidayType, tauntInHell, allowHaunting }.
-- Hell's taunts and haunting are left out, so only the holiday is used.
function Controller:BindHoliday(ent, kv)
	self.holiday:SetMapHoliday(kv.holidayType)
	self:ModeChanged()
end

function Controller:HolidayActive(h) return self.holiday:Active(h) end
function Controller:Mode() return self.holiday:Mode() end
function Controller:UsingSpells() return self.holiday:UsingSpells() end

-- Spells turning on load the spells feature, which hands out the books.
function Controller:SetUsingSpells(on)
	if self.holiday:SetUsingSpells(on) and self.holiday:UsingSpells() then WETSAND.Feature("spells") end
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
