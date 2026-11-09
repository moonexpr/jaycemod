-- TF2's IT (CTFGameRules::SetIT and IsIT): the one player the Horseless
-- Headless Horsemann chases. IT passes by a melee hit on an enemy
-- (CTFWeaponBaseMelee::OnSwingHit) and to whoever kills IT
-- (CTFPlayer::Event_Killed). The tag controller owns one of these.
--
-- New(world): world:HolidayActive(h) and world:Mode() are the holiday
-- controller's; world:IsAlive(p) and world:TeamOf(p) answer for a player.
--
-- Every change returns notices for the controller to deliver, in order:
-- { kind, player, sound } for SOUND_TO (only the player hears it) and
-- SOUND_FROM (the player makes it); { kind, player, text } for PRINT_CENTER
-- and PRINT_TALK; { kind, text, subjects } for PRINT_ALL, whose text formats
-- the subjects' names. The warnings play only while Halloween is on and its
-- mode ANNOUNCES_IT; the chat line that names a tag always plays.
local require = require
local Holiday = require("features.holiday.model")
local setmetatable = setmetatable
module(...)

SOUND_TO = "sound_to"
SOUND_FROM = "sound_from"
PRINT_CENTER = "print_center"
PRINT_TALK = "print_talk"
PRINT_ALL = "print_all"

YOU_ARE_IT_SOUND = "Player.YouAreIT"
SCREAM_SOUND = "Halloween.PlayerScream"
TAGGED_OTHER_SOUND = "Player.TaggedOtherIT"

-- tf_english.txt
WARN_VICTIM = "YOU ARE IT!  MELEE HIT AN ENEMY TO TAG THEM IT!" -- TF_HALLOWEEN_BOSS_WARN_VICTIM
LOST_AGGRO = "You are no longer IT." -- TF_HALLOWEEN_BOSS_LOST_AGGRO
ANNOUNCE_TAG = "%s tagged %s as IT!" -- TF_HALLOWEEN_BOSS_ANNOUNCE_TAG

local TagModel = {}
TagModel.__index = TagModel

function New(world)
	return setmetatable({
		world = world,
		it = nil,
	}, TagModel)
end

function TagModel:Get() return self.it end
function TagModel:IsIT(p) return p ~= nil and p == self.it end

-- SetIT's IsHolidayActive( kHoliday_Halloween ), with the mode's say.
function TagModel:Announces()
	local world = self.world
	if not world:HolidayActive(Holiday.HALLOWEEN) then return false end
	local mode = world:Mode()
	return mode ~= nil and mode.ANNOUNCES_IT == true
end

local function Add(notices, notice)
	notices[#notices + 1] = notice
end

local function Say(notices, kind, player, text)
	Add(notices, {
		kind = kind,
		player = player,
		text = text,
	})
end

local function Sound(notices, kind, player, sound)
	Add(notices, {
		kind = kind,
		player = player,
		sound = sound,
	})
end

-- CTFGameRules::SetIT
function TagModel:Set(who)
	local notices = {}
	if self:Announces() then
		if who ~= nil and who ~= self.it then
			Say(notices, PRINT_TALK, who, WARN_VICTIM)
			Say(notices, PRINT_CENTER, who, WARN_VICTIM)
			Sound(notices, SOUND_TO, who, YOU_ARE_IT_SOUND)
			Sound(notices, SOUND_FROM, who, SCREAM_SOUND)
		end
		local old = self.it
		if old ~= nil and old ~= who and self.world:IsAlive(old) then
			Sound(notices, SOUND_TO, old, TAGGED_OTHER_SOUND)
			Say(notices, PRINT_TALK, old, LOST_AGGRO)
			Say(notices, PRINT_CENTER, old, LOST_AGGRO)
		end
	end
	self.it = who
	return notices
end

-- CHeadlessHatmanAttack::Update's reminder to the player it chases.
function TagModel:Warn(who)
	local notices = {}
	if self:Announces() then Say(notices, PRINT_CENTER, who, WARN_VICTIM) end
	return notices
end

-- CTFWeaponBaseMelee::OnSwingHit: IT hitting an enemy tags them.
function TagModel:OnMeleeHit(attacker, victim)
	local world = self.world
	if world:TeamOf(attacker) == world:TeamOf(victim) or not self:IsIT(attacker) then return {} end
	local notices = self:Set(victim)
	Add(notices, {
		kind = PRINT_ALL,
		text = ANNOUNCE_TAG,
		subjects = { attacker, victim },
	})
	return notices
end

-- CTFPlayer::Event_Killed: IT killed by a player makes the killer IT.
-- killer is nil unless a player dealt the blow.
function TagModel:OnDeath(victim, killer)
	if killer == nil or not self:IsIT(victim) then return {} end
	return self:Set(killer)
end
