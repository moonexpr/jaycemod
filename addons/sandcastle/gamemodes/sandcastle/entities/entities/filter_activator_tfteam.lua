-- filter_activator_tfteam (CFilterTFTeam): passes entities on its TF2 team,
-- or fails them when Negated. During team win the winners pass every team
-- filter, which opens the losers' spawn doors to them. With a controlpoint,
-- the filter takes that point's owner at each round start.
-- Engine triggers consult it through PassesFilter.
ENT.Type = "filter"
ENT.Base = "base_filter"

function ENT:KeyValue(key, value)
	local k = string.lower(key)
	if k == "teamnum" then
		self.team = tonumber(value) or WS.TEAM_UNASSIGNED
	elseif k == "negated" then
		-- Hammer sometimes stores the choice's label ("Allow entities that
		-- match criteria") rather than 0/1; only "1" negates.
		self.negated = value == "1"
	elseif k == "controlpoint" then
		self.pointName = value
	elseif string.sub(key, 1, 2) == "On" then
		self:StoreOutput(key, value)
	end
end

function ENT:Initialize()
	self.team = self.team or WS.TEAM_UNASSIGNED
	self.negated = self.negated or false
end

-- Team numbers are compared raw, as TF2 does: a player on another addon's
-- team matches neither RED nor BLU. An NPC fighting for a team (the AI
-- war's) passes as that team's player would.
function ENT:PassesFilter(trigger, ent)
	-- out of gameplay, every door opens for everyone
	if WS.GameplayStopped() then return true end
	return WS.TeamRules.FilterPasses(self.team, self.negated, WS.TeamNumber(ent), WS.State(), GetGlobal2Int("ws_round_winner", WS.TEAM_UNASSIGNED))
end

-- CFilterTFTeam::InputRoundActivate
function ENT:RoundActivate()
	if not self.pointName or self.pointName == "" then return end
	local point = WS.FindByName(self.pointName)
	if IsValid(point) then self.team = WS.Feature("capture"):Owner(point) end
end

local INPUTS = {
	setteam = function(self, value) self.team = tonumber(value) or WS.TEAM_UNASSIGNED end,
	roundactivate = function(self) self:RoundActivate() end,
	-- CFilterTFTeam::InputRoundSpawn does nothing.
	roundspawn = function() end,
	-- CBaseFilter::InputTestActivator
	testactivator = function(self, value, activator)
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
	handler(self, value, activator)
	return true
end
