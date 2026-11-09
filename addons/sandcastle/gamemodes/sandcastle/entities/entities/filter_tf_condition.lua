-- filter_tf_condition (CFilterTFCondition, tf_filters.cpp): passes players in
-- the player condition `condition` (foundation.players.COND), or fails them
-- when Negated; anything but a player never matches (koth_undergrove_event's
-- ghosts, filter_ghosts on HALLOWEEN_GHOST_MODE). Triggers consult it through
-- PassesFilter, as they do filter_activator_tfteam. Conditions GMod does not
-- track never match; see sv_teams_conditions.lua.
ENT.Type = "filter"
ENT.Base = "base_filter"

function ENT:KeyValue(key, value)
	local k = string.lower(key)
	if k == "condition" then
		self.condition = tonumber(value)
	elseif k == "negated" then
		-- Hammer sometimes stores the choice's label ("Allow entities that
		-- match criteria") rather than 0/1; only "1" negates. Kept from the
		-- engine so the negation applies once, here.
		self.negated = value == "1"
		return true
	elseif string.sub(key, 1, 2) == "On" then
		self:StoreOutput(key, value)
	end
end

function ENT:Initialize()
	self.condition = self.condition or WS.PlayerRules.COND.INVALID
	self.negated = self.negated or false
end

-- CBaseFilter::PassesFilter over CFilterTFCondition::PassesFilterImpl.
function ENT:PassesFilter(trigger, ent)
	-- TestActivator may come with no activator.
	local matches = IsValid(ent) and ent:IsPlayer() and WS.InCondition(ent, self.condition)
	return matches ~= self.negated
end

-- CBaseFilter::PassesDamageFilter: every damage matches.
function ENT:PassesDamageFilter(dmg)
	return not self.negated
end

local INPUTS = {
	-- CBaseFilter::InputTestActivator
	testactivator = function(self, activator)
		if self:PassesFilter(self, activator) then
			self:TriggerOutput("OnPass", activator)
		else
			self:TriggerOutput("OnFail", activator)
		end
	end,
}

function ENT:AcceptInput(name, activator, caller, value)
	local handler = INPUTS[string.lower(name)]
	if not handler then return false end
	handler(self, activator)
	return true
end
