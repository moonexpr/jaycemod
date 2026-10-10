-- The attributes feature's controller: TF2's custom player attributes. It
-- owns each player's attributes (foundation.players.attributes), gives and
-- takes them as map triggers and the Wheel of Fate say, scales the damage
-- their owners take, and clears them when a player spawns or dies
-- (CTFPlayer::Spawn and Event_Killed). It applies the rest to the player:
-- top speed (ws_speed_scale, which sh_core's movement reads on both
-- realms), jump power, fall damage and the head bone's scale. A
-- trigger_add_or_remove_tf_player_attributes or a wheel_of_doom loads it,
-- so other maps never run these hooks.
local Attributes = WS.require("foundation.players.attributes")

local HEAD_BONE = "ValveBiped.Bip01_Head1"
local SYNC_INTERVAL = 0.1 -- timed attributes run out between changes
local SYNC_TIMER = "ws_attributes_sync"

local Controller = {
	byPlayer = setmetatable({}, { __mode = "k" }), -- player -> attrs
	jumpBase = setmetatable({}, { __mode = "k" }), -- player -> jump power before a jump bonus
}

function Controller:Of(ply)
	local attrs = self.byPlayer[ply]
	if attrs == nil then
		attrs = {}
		self.byPlayer[ply] = attrs
	end
	return attrs
end

function Controller:Supported(name)
	return Attributes.Supported(name)
end

-- What the player's attributes do now, on the player. A model without the
-- head bone keeps its head.
function Controller:Sync(ply)
	if not IsValid(ply) then return end
	local attrs, now = self.byPlayer[ply] or {}, CurTime()
	ply:SetNW2Float("ws_speed_scale", Attributes.SpeedScale(attrs, now))
	local jump = Attributes.JumpScale(attrs, now)
	if jump ~= 1 and self.jumpBase[ply] == nil then self.jumpBase[ply] = ply:GetJumpPower() end
	if self.jumpBase[ply] then
		ply:SetJumpPower(self.jumpBase[ply] * jump)
		if jump == 1 then self.jumpBase[ply] = nil end
	end
	local head = ply:LookupBone(HEAD_BONE)
	if head then
		local s = Attributes.HeadScale(attrs, now)
		ply:ManipulateBoneScale(head, Vector(s, s, s))
	end
end

-- trigger = { name, value, duration, remove }, from the trigger's keyvalues.
function Controller:StartTouch(ply, trigger)
	if Attributes.StartTouchAction(trigger) == Attributes.REMOVE then
		Attributes.Remove(self:Of(ply), trigger.name)
	else
		Attributes.Add(self:Of(ply), trigger.name, trigger.value, trigger.duration, CurTime())
	end
	self:Sync(ply)
end

function Controller:EndTouch(ply, trigger)
	if Attributes.EndTouchRemoves(trigger) then Attributes.Remove(self:Of(ply), trigger.name) end
	self:Sync(ply)
end

-- ApplyAttributeToPlayer and RemoveAttributeFromPlayer (the Wheel of Fate):
-- until taken back.
function Controller:Give(ply, name, value)
	Attributes.Add(self:Of(ply), name, value, Attributes.UNTIL_REMOVED, CurTime())
	self:Sync(ply)
end

function Controller:Take(ply, name)
	Attributes.Remove(self:Of(ply), name)
	self:Sync(ply)
end

-- A player's spawn or death: no attributes, and nothing left of them.
function Controller:Clear(ply)
	self.byPlayer[ply] = nil
	self:Sync(ply)
end

hook.Add("EntityTakeDamage", "ws_attributes_damage_taken", function(target, dmg)
	local attrs = Controller.byPlayer[target]
	if attrs == nil then return end
	local scale = Attributes.DamageTakenScale(attrs, dmg:GetDamageType(), CurTime())
	if scale ~= 1 then dmg:ScaleDamage(scale) end
end)

-- "cancel falling damage"
hook.Add("GetFallDamage", "ws_attributes_fall_damage", function(ply)
	local attrs = Controller.byPlayer[ply]
	if attrs and Attributes.FallDamageCancelled(attrs, CurTime()) then return 0 end
end)

timer.Create(SYNC_TIMER, SYNC_INTERVAL, 0, function()
	for ply in pairs(Controller.byPlayer) do Controller:Sync(ply) end
end)

hook.Add("PlayerSpawn", "ws_attributes_spawn_clear", function(ply) Controller:Clear(ply) end)
hook.Add("PostPlayerDeath", "ws_attributes_death_clear", function(ply) Controller:Clear(ply) end)

return Controller
