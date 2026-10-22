-- Part of the rounds controller (sv.lua): the controller's state as plain
-- data and back, for the dev workbench's capture and restore: whether the
-- map runs rounds, the Round, every timer, the HUD's timer, the team
-- scores and the goals and roles the map's inputs set. Entities go through
-- refs (Encode(ent) -> key, Decode(key) -> the entity or nil); a timer
-- whose key no longer resolves is reported missing, not restored.
local Controller, PublishState = ...

local RED, BLUE = WS.TEAM_RED, WS.TEAM_BLUE
local GAME_TEAMS = { RED, BLUE }
local GOAL_KEY, ROLE_KEY = "ws_round_goal_", "ws_round_role_"

function Controller:Snapshot(now, refs)
	local timers = {}
	for ent, timer in pairs(self.timers) do
		if IsValid(ent) then timers[refs:Encode(ent)] = timer:Snapshot(now) end
	end
	local snapshot = {
		active = self.rounds,
		round = self.round:Snapshot(now),
		timers = timers,
		hudTimer = IsValid(self.hudTimer) and refs:Encode(self.hudTimer) or nil,
		scores = {},
		goals = {},
		roles = {},
	}
	for _, t in ipairs(GAME_TEAMS) do
		snapshot.scores[t] = team.GetScore(t)
		snapshot.goals[t] = GetGlobal2String(GOAL_KEY .. t, "")
		snapshot.roles[t] = GetGlobal2Int(ROLE_KEY .. t, 0)
	end
	return snapshot
end

-- The state put back in place; returns { missing = { keys } }.
function Controller:Restore(snapshot, now, refs)
	local missing = {}
	self.rounds = snapshot.active
	self.round:Restore(snapshot.round, now)
	for key, data in pairs(snapshot.timers) do
		local ent = refs:Decode(key)
		if IsValid(ent) and self.timers[ent] then
			self.timers[ent]:Restore(data, now)
		else
			missing[#missing + 1] = key
		end
	end
	local hud = snapshot.hudTimer and refs:Decode(snapshot.hudTimer)
	if IsValid(hud) and self.timers[hud] then
		self:SetActiveTimer(hud)
	elseif snapshot.hudTimer then
		missing[#missing + 1] = snapshot.hudTimer
	end
	for _, t in ipairs(GAME_TEAMS) do
		team.SetScore(t, snapshot.scores[t])
		SetGlobal2String(GOAL_KEY .. t, snapshot.goals[t])
		SetGlobal2Int(ROLE_KEY .. t, snapshot.roles[t])
	end
	PublishState()
	self:PublishRoundLimits()
	self:PublishHudTimer(now)
	return { missing = missing }
end
