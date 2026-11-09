-- Common base for the TF2 triggers (CBaseTrigger): tracks the players
-- inside, polled like the other volumes, and calls PlayerStartTouch,
-- PlayerTouch and PlayerEndTouch. The trigger's filtername is honoured when
-- it names a Lua filter (filter_activator_tfteam); an engine filter cannot
-- be asked from Lua and lets everyone through.
ENT.Type = "brush"
ENT.Base = "base_brush2"

local THINK_INTERVAL = 0.1

function ENT:VolumeInit()
	self.touching = {}
	if self.TriggerInit then self:TriggerInit() end
end

function ENT:PassesTriggerFilters(ent)
	local filter = WS.FindByName(self:Key("filtername"))
	if not (IsValid(filter) and filter.PassesFilter) then return true end
	return filter:PassesFilter(self, ent)
end

function ENT:EndAllTouches()
	for ply in pairs(self.touching) do
		self.touching[ply] = nil
		if IsValid(ply) and self.PlayerEndTouch then self:PlayerEndTouch(ply) end
	end
end

function ENT:Think()
	self:NextThink(CurTime() + THINK_INTERVAL)
	if not self.enabled then return true end
	local inside = {}
	for _, ply in ipairs(WS.PlayersInside(self)) do inside[ply] = true end
	for ply in pairs(self.touching) do
		if not inside[ply] then
			self.touching[ply] = nil
			if IsValid(ply) and self.PlayerEndTouch then self:PlayerEndTouch(ply) end
		end
	end
	for ply in pairs(inside) do
		if not self.touching[ply] then
			self.touching[ply] = true
			if self.PlayerStartTouch then self:PlayerStartTouch(ply) end
		end
		if self.PlayerTouch then self:PlayerTouch(ply) end
	end
	if self.TriggerThink then self:TriggerThink() end
	return true
end

-- CBaseTrigger::Disable ends every touch after marking itself disabled;
-- DisableAndEndTouch ends them first, while still enabled.
local function Disable(self)
	self.enabled = false
	self:EndAllTouches()
end

ENT.TriggerInputs = {
	disable = Disable,
	toggle = function(self)
		if self.enabled then Disable(self) else self.enabled = true end
	end,
	disableandendtouch = function(self)
		self:EndAllTouches()
		self.enabled = false
	end,
}
ENT.Inputs = ENT.TriggerInputs