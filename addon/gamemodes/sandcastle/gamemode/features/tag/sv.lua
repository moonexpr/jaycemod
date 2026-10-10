-- The tag feature's controller: TF2's IT. It owns the foundation.npc.tag
-- model, feeds it players' melee hits and deaths, and delivers the sounds
-- and messages it answers with. The Horsemann loads it (its combatant
-- port's Tag()), so a map without one has no IT; and IT ends when the
-- Horsemann dies or is removed, so these hooks do nothing without one.
local Tag = WS.require("foundation.npc.tag")

local holiday = WS.Feature("holiday")

-- Player melee damage (TF2's melee weapons deal DMG_CLUB or DMG_SLASH).
local MELEE = bit.bor(DMG_CLUB, DMG_SLASH)

-- The tag model's world.
local World = {}
function World:HolidayActive(h) return holiday:HolidayActive(h) end
function World:Mode() return holiday:Mode() end
function World:IsAlive(p) return IsValid(p) and p:Alive() end
function World:TeamOf(p) return p:Team() end

local function Names(players)
	local names = {}
	for i, p in ipairs(players) do names[i] = p:Nick() end
	return names
end

local DELIVER = {
	[Tag.SOUND_TO] = function(n) WS.PlaySoundTo(n.player, n.player, n.sound) end,
	[Tag.SOUND_FROM] = function(n) n.player:EmitSound(n.sound) end,
	[Tag.PRINT_CENTER] = function(n) n.player:PrintMessage(HUD_PRINTCENTER, n.text) end,
	[Tag.PRINT_TALK] = function(n) n.player:PrintMessage(HUD_PRINTTALK, n.text) end,
	[Tag.PRINT_ALL] = function(n) PrintMessage(HUD_PRINTTALK, string.format(n.text, unpack(Names(n.subjects)))) end,
}

local Controller = {
	model = Tag.New(World),
}

function Controller:Deliver(notices)
	for _, notice in ipairs(notices) do DELIVER[notice.kind](notice) end
end

function Controller:Get() return self.model:Get() end
function Controller:Set(ply) self:Deliver(self.model:Set(ply)) end
function Controller:Warn(ply) self:Deliver(self.model:Warn(ply)) end

hook.Add("EntityTakeDamage", "ws_tag_melee_hit", function(victim, dmg)
	local attacker = dmg:GetAttacker()
	if not (victim:IsPlayer() and IsValid(attacker) and attacker:IsPlayer()) then return end
	if bit.band(dmg:GetDamageType(), MELEE) == 0 then return end
	Controller:Deliver(Controller.model:OnMeleeHit(attacker, victim))
end)

hook.Add("PlayerDeath", "ws_tag_player_death", function(victim, inflictor, attacker)
	local killer = nil
	if IsValid(attacker) and attacker:IsPlayer() then killer = attacker end
	Controller:Deliver(Controller.model:OnDeath(victim, killer))
end)

return Controller
