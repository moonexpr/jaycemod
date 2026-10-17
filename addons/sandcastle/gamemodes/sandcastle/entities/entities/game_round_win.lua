-- game_round_win: ends the round (CTeamplayRoundWin, server/tf/entity_roundwin.cpp),
-- bound to the rounds feature, whose Round decides what the win means: a
-- team wins, or TeamNum 0 is a stalemate (sudden death with
-- mp_stalemate_enable), and only a full-reset win switches teams.
ENT.Type = "point"
ENT.Base = "base_point"

local Rounds

-- WINREASON_DEFEND_UNTIL_TIME_LIMIT, the entity's default win_reason.
local DEFEND_UNTIL_TIME_LIMIT = 4

function ENT:KeyValue(key, value)
	local k = string.lower(key)
	if k == "teamnum" then
		self.team = tonumber(value) or WS.TEAM_UNASSIGNED
	elseif k == "force_map_reset" then
		self.forceMapReset = value ~= "0"
	elseif k == "switch_teams" then
		self.switchTeams = value == "1"
	elseif k == "win_reason" then
		self.winReason = tonumber(value) or DEFEND_UNTIL_TIME_LIMIT
	elseif string.sub(key, 1, 2) == "On" then
		self:StoreOutput(key, value)
	end
end

function ENT:Initialize()
	Rounds = WS.Feature("rounds")
	self.team = self.team or WS.TEAM_UNASSIGNED
	if self.forceMapReset == nil then self.forceMapReset = true end
	self.switchTeams = self.switchTeams or false
	self.winReason = self.winReason or DEFEND_UNTIL_TIME_LIMIT
end

function ENT:UpdateTransmitState()
	return TRANSMIT_NEVER
end

local INPUTS = {
	roundwin = function(self)
		Rounds:GameRoundWin(self, {
			team = self.team,
			reason = self.winReason,
			forceMapReset = self.forceMapReset,
			switchTeams = self.switchTeams,
		})
	end,
	setteam = function(self, value) self.team = tonumber(value) or WS.TEAM_UNASSIGNED end,
}

function ENT:AcceptInput(name, activator, caller, value)
	local handler = INPUTS[string.lower(name)]
	if not handler then return false end
	handler(self, value)
	return true
end
