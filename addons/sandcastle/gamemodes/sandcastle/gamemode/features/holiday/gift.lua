-- A Halloween gift (CHalloweenGiftPickup, entity_halloween_pickup.cpp): a
-- pickup meant for one player, which only that player sees and can take.
-- Unclaimed after its lifetime, it despawns (it belongs to nobody), and is
-- removed a second later. Taking it gives nothing here: TF2's rewards (soul
-- packs, contract points) are econ features.
--
-- New{ player, lifetime }, now: the holiday controller's gift and
-- features.holiday.halloween's LIFETIME. Then :Target(), :Touch(player)
-- -> taken, :Tick(now) -> NONE, DESPAWN or REMOVE.
local require = require
local Holiday = require("features.holiday.model")
local setmetatable = setmetatable
module(...)

-- CTFGameRules::LevelInitPostEntity takes tf_halloween_gift_spawn_location
-- origins only while this holiday is on.
HOLIDAY = Holiday.HALLOWEEN

MODEL = "models/props_halloween/gargoyle_ghost.mdl" -- TF_GIFT_MODEL
REMOVE_DELAY = 1 -- DespawnGift, then RemoveGift

-- MyTouch: the particle everyone near sees, and the sounds only the taker
-- hears.
TAKE_PARTICLE = "duck_collect_green"
TAKE_SOUNDS = { "Halloween.PumpkinPickup", "sf15.Merasmus.Gargoyle.Got" }

NONE, DESPAWN, REMOVE = "none", "despawn", "remove"

local Gift = {}
Gift.__index = Gift

function New(config, now)
	return setmetatable({
		target = config.player,
		despawnAt = now + config.lifetime,
		removeAt = nil,
		gone = false,
	}, Gift)
end

function Gift:Target() return self.target end

-- ValidTouch and MyTouch: only the target takes it, once.
function Gift:Touch(player)
	if self.gone or player ~= self.target then return false end
	self.gone = true
	return true
end

function Gift:Tick(now)
	if self.gone then return NONE end
	if self.despawnAt and now >= self.despawnAt then
		self.target = nil
		self.despawnAt = nil
		self.removeAt = now + REMOVE_DELAY
		return DESPAWN
	end
	if self.removeAt and now >= self.removeAt then
		self.gone = true
		return REMOVE
	end
	return NONE
end
