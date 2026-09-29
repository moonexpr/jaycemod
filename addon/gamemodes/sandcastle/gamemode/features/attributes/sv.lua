-- The attributes feature's controller: TF2's custom player attributes. It
-- owns each player's attributes (foundation.players.attributes), gives and
-- takes them as map triggers say, scales the damage their owners take, and
-- clears them when a player spawns or dies (CTFPlayer::Spawn and
-- Event_Killed). A trigger_add_or_remove_tf_player_attributes loads it, so
-- other maps never run these hooks.
local Attributes = WETSAND.require("foundation.players.attributes")

local Controller = {
	byPlayer = setmetatable({}, { __mode = "k" }), -- player -> attrs
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

-- trigger = { name, value, duration, remove }, from the trigger's keyvalues.
function Controller:StartTouch(ply, trigger)
	if Attributes.StartTouchAction(trigger) == Attributes.REMOVE then
		Attributes.Remove(self:Of(ply), trigger.name)
	else
		Attributes.Add(self:Of(ply), trigger.name, trigger.value, trigger.duration, CurTime())
	end
end

function Controller:EndTouch(ply, trigger)
	if Attributes.EndTouchRemoves(trigger) then Attributes.Remove(self:Of(ply), trigger.name) end
end

function Controller:Clear(ply)
	self.byPlayer[ply] = nil
end

hook.Add("EntityTakeDamage", "wetsand_attributes_damage_taken", function(target, dmg)
	local attrs = Controller.byPlayer[target]
	if attrs == nil then return end
	local scale = Attributes.DamageTakenScale(attrs, dmg:GetDamageType(), CurTime())
	if scale ~= 1 then dmg:ScaleDamage(scale) end
end)

hook.Add("PlayerSpawn", "wetsand_attributes_spawn_clear", function(ply) Controller:Clear(ply) end)
hook.Add("PostPlayerDeath", "wetsand_attributes_death_clear", function(ply) Controller:Clear(ply) end)

return Controller
