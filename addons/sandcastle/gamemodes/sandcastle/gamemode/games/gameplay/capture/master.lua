-- The team_control_point_master (CTeamControlPointMaster,
-- team_control_point_master.cpp) and its team_control_point_rounds
-- (CTeamControlPointRound, team_control_point_round.cpp) over a PointSet:
-- which mini-round is played, when a team has won, how a win ends the
-- round, the stage the HUD shows, and the team's base point. No I/O; the
-- capture controller fires the outputs and asks the rounds controller to
-- end the round, and randomness is passed in.
--
-- New{ restrict, switchTeams, scoreStyle, playAllRounds, partialCapRate,
-- capLayout, disabled, rounds = { { name, priority, restrict, printName,
-- points = { ids } } }, firstAfterRestart (default true) }.
local ipairs, setmetatable = ipairs, setmetatable
local sort, remove = table.sort, table.remove
local Capture = gameplay.capture
local Rounds = gameplay.rounds
local Teams = gameplay.teams
local Snapshot = world.snapshot
module(...)

-- score_style: a team scores per round won, or per point captured.
SCORE_PER_ROUND, SCORE_PER_CAPTURE = 0, 1

local NOBODY, FIRST_GAME_TEAM = Teams.UNASSIGNED, Teams.FIRST_GAME_TEAM
local TEAM_INVALID = Teams.INVALID
local RESTRICT_NEITHER = Rounds.RESTRICT_NEITHER

-- FireTeamWinOutput: the output the master and the won round fire.
local WIN_OUTPUT = {
	[Teams.RED] = "OnWonByTeam1",
	[Teams.BLUE] = "OnWonByTeam2",
}

function WinOutput(team)
	return WIN_OUTPUT[team]
end

local MasterModel = {}
MasterModel.__index = MasterModel

function New(config)
	local firstAfterRestart = config.firstAfterRestart
	if firstAfterRestart == nil then firstAfterRestart = true end
	return setmetatable({
		restrict = config.restrict,
		switchTeams = config.switchTeams,
		scoreStyle = config.scoreStyle,
		playAllRounds = config.playAllRounds,
		partialCapRate = config.partialCapRate,
		capLayout = config.capLayout,
		disabled = config.disabled,
		rounds = config.rounds,
		current = nil,
		firstAfterRestart = firstAfterRestart,
	}, MasterModel)
end

-- Settings and state -----------------------------------------------------------------

function MasterModel:Enable() self.disabled = false end
function MasterModel:Disable() self.disabled = true end
function MasterModel:Active() return not self.disabled end
function MasterModel:ScorePerCapture() return self.scoreStyle == SCORE_PER_CAPTURE end
function MasterModel:PlayAllRounds() return self.playAllRounds end
function MasterModel:PartialCapRate() return self.partialCapRate end
function MasterModel:CapLayout() return self.capLayout end
function MasterModel:SetCapLayout(layout) self.capLayout = layout end

function MasterModel:PlayingMiniRounds()
	return #self.rounds > 0
end

local function CurrentRound(self)
	for _, r in ipairs(self.rounds) do
		if r.name == self.current then return r end
	end
end

-- The mini-round being played, by name, or nil.
-- The master as plain data (games.world.snapshot): its chosen
-- mini-round and switches. Its rounds are the map's list, kept as they are.
local SNAPSHOT = Snapshot.Spec({
	name = "master",
	skip = { "rounds" },
})

function MasterModel:Snapshot(now, refs) return Snapshot.Take(self, SNAPSHOT, now, refs) end
function MasterModel:Restore(snapshot, now, refs) Snapshot.Apply(self, snapshot, SNAPSHOT, now, refs) end

function MasterModel:Current()
	return self.current
end

-- InputRoundSpawn's FindControlPointRounds: the rounds as the map has them
-- now. The round being played stays chosen while it is among them.
function MasterModel:SetRounds(rounds)
	self.rounds = rounds
	if not CurrentRound(self) then self.current = nil end
end

-- The points in play: { [id] = true } for the current mini-round, or nil
-- when every point is (no mini-rounds, or none chosen yet).
function MasterModel:InRound()
	local r = CurrentRound(self)
	if not r then return nil end
	local set = {}
	for _, id in ipairs(r.points) do set[id] = true end
	return set
end

-- CTeamControlPointMaster::IsInRound
function MasterModel:IsInRound(id)
	local inRound = self:InRound()
	return inRound == nil or inRound[id] == true
end

-- Wins -----------------------------------------------------------------------------------

-- CTeamControlPointRound::CheckWinConditions (and the master's own without
-- rounds): the team owning every point, unless the round forbids it.
local function RoundWinner(set, restrict, ids)
	local winner = set:TeamOwnsAll(ids)
	if restrict ~= RESTRICT_NEITHER and winner >= FIRST_GAME_TEAM and winner ~= restrict then return winner end
	return nil
end

-- CTeamControlPointRound::IsPlayable
local function Playable(set, r)
	if r.restrict == RESTRICT_NEITHER then return true end
	return RoundWinner(set, r.restrict, r.points) == nil
end

-- CTeamControlPointMaster::CheckWinConditions without KOTH's clock gate,
-- which the rounds controller's MayWinByPoints applies: the winner and the
-- won mini-round's name, or nil.
function MasterModel:Winner(set)
	if self.disabled then return nil end
	if not self:PlayingMiniRounds() then return RoundWinner(set, self.restrict, set:Ids()) end
	local r = CurrentRound(self)
	if not r then return nil end
	local winner = RoundWinner(set, r.restrict, r.points)
	if winner then return winner, r.name end
	return nil
end

-- NumPlayableControlPointRounds
function MasterModel:NumPlayable(set)
	local n = 0
	for _, r in ipairs(self.rounds) do
		if Playable(set, r) then n = n + 1 end
	end
	return n
end

-- A win resets the map unless mini-rounds are left to play, and only that
-- final win switches teams.
function MasterModel:WinArgs(set)
	local forceMapReset = not self:PlayingMiniRounds() or self:NumPlayable(set) == 0
	return forceMapReset, forceMapReset and self.switchTeams
end

-- InternalSetWinner: team 0 is a stalemate (STALEMATE_TIMER).
function MasterModel:SetWinnerArgs(team, set)
	local forceMapReset, switchTeams = self:WinArgs(set)
	return {
		stalemate = team == NOBODY,
		forceMapReset = forceMapReset,
		switchTeams = switchTeams,
	}
end

-- WouldNewCPOwnerWinGame, over every point.
function MasterModel:WouldNewOwnerWin(set, id, team)
	return set:TeamOwnsAll(set:Ids(), id, team) == team
end

-- InputSetWinnerAndForceCaps: the points the winner is given.
function MasterModel:ForcedCaps(set)
	local ids = {}
	for _, id in ipairs(set:Ids()) do
		if self:IsInRound(id) then ids[#ids + 1] = id end
	end
	return ids
end

local function Contains(list, value)
	for i, v in ipairs(list) do
		if v == value then return i end
	end
end

-- CTeamTrainWatcher::WatcherThink's bFinalPointInMap: would one of teams
-- win the game by capturing id? With mini-rounds only in the last playable
-- round, over its points.
function MasterModel:FinalPoint(set, id, teams)
	local ids = set:Ids()
	if self:PlayingMiniRounds() then
		local r = CurrentRound(self)
		if self:NumPlayable(set) ~= 1 or not r then return false end
		ids = r.points
	end
	if not Contains(ids, id) then return false end
	for _, team in ipairs(teams) do
		if set:TeamOwnsAll(ids, id, team) == team then return true end
	end
	return false
end

-- Round choice ---------------------------------------------------------------------------

local function ByPriority(rounds)
	local order = {}
	for i = 1, #rounds do order[i] = i end
	sort(order, function(a, b)
		if rounds[a].priority ~= rounds[b].priority then return rounds[a].priority > rounds[b].priority end
		return a < b
	end)
	return order
end

-- GetControlPointRoundToPlay: the playable rounds of the highest playable
-- priority, less the last played and (after a restart) the first played
-- after the previous restart, then a random one not played recently.
-- history = { previous = the last two played, most recent first, first =
-- the first round played after the last restart } (the gamerules'
-- AddPlayedRound and SetFirstRoundPlayed); random(n) returns 1..n.
-- RegisterRoundBeingPlayed: returns the chosen name and whether it is the
-- first after a restart, or nil.
function MasterModel:ChooseRound(set, history, random)
	local rounds = self.rounds
	local order = ByPriority(rounds)
	local priority
	for _, i in ipairs(order) do
		if Playable(set, rounds[i]) then
			priority = rounds[i].priority
			break
		end
	end
	if priority == nil then
		self.current = nil
		return nil
	end

	local candidates = {}
	for _, i in ipairs(order) do
		if rounds[i].priority == priority and Playable(set, rounds[i]) then candidates[#candidates + 1] = i end
	end
	local function Drop(name)
		if #candidates < 2 or name == nil then return end
		for k, i in ipairs(candidates) do
			if rounds[i].name == name then
				remove(candidates, k)
				return
			end
		end
	end
	Drop(history.previous[1])
	if self.firstAfterRestart then Drop(history.first) end

	local k = random(#candidates)
	while #candidates > 1 and Contains(history.previous, rounds[candidates[k]].name) do
		remove(candidates, k)
		k = random(#candidates)
	end
	self.current = rounds[candidates[k]].name
	local firstAfterRestart = self.firstAfterRestart
	self.firstAfterRestart = false
	return self.current, firstAfterRestart
end

-- The round that comes first while none is chosen (Sandbox mode keeps the
-- rounds from activating): the first playable round of the highest
-- priority, or nil. It chooses nothing; ChooseRound does, at RoundActivate.
function MasterModel:Upcoming(set)
	for _, i in ipairs(ByPriority(self.rounds)) do
		if Playable(set, self.rounds[i]) then return self.rounds[i].name end
	end
	return nil
end

-- InputRoundActivate: with mini-rounds and none chosen, choose one.
-- Returns ChooseRound's answer, or nil when nothing was chosen now.
function MasterModel:RoundActivate(set, history, random)
	if not self:PlayingMiniRounds() or self.current then return nil end
	return self:ChooseRound(set, history, random)
end

-- FireRoundEndOutput: the ended round's name (its OnEnd fires), or nil.
function MasterModel:EndRound()
	local name = self.current
	self.current = nil
	return name
end

-- The HUD's stage: the current round's place in priority order (the order
-- multi-stage maps play them in), the number of rounds, its print name.
function MasterModel:Stage(set)
	local r = CurrentRound(self)
	if not r then return 0, #self.rounds, "" end
	for stage, i in ipairs(ByPriority(self.rounds)) do
		if self.rounds[i] == r then return stage, #self.rounds, r.printName end
	end
end

-- CalcNumRoundsRemaining: how many more mini-rounds the team must win to
-- own every point, simulating it winning each next playable round. Unlike
-- IsPlayable this ignores point groups. It stops when no round makes
-- progress (the SDK would loop forever there).
function MasterModel:RoundsRemaining(team, set)
	local ids = set:Ids()
	local owned, count = {}, 0
	for _, id in ipairs(ids) do
		if set:Owner(id) == team then
			owned[id] = true
			count = count + 1
		end
	end
	local remaining = 0
	while count < #ids do
		local progressed = false
		for _, r in ipairs(self.rounds) do
			local roundOwner
			for k, id in ipairs(r.points) do
				local owner = owned[id] and team or set:Owner(id)
				if k == 1 then
					roundOwner = owner
				elseif roundOwner ~= owner then
					roundOwner = TEAM_INVALID
				end
			end
			local playable = roundOwner == nil or roundOwner < FIRST_GAME_TEAM or r.restrict == RESTRICT_NEITHER or roundOwner == r.restrict
			if playable then
				for _, id in ipairs(r.points) do
					if not owned[id] then
						owned[id] = true
						count = count + 1
						progressed = true
					end
				end
				if progressed then break end
			end
		end
		if not progressed then break end
		remaining = remaining + 1
	end
	return remaining
end

-- GetBaseControlPoint: the team's end of the chain, as a rank, among the
-- current mini-round's points (G8) or every point.
function MasterModel:BaseControlPoint(set, team)
	local points = {}
	for _, id in ipairs(set:Ids()) do
		if self:IsInRound(id) then
			points[#points + 1] = {
				index = set:Rank(id),
				defaultOwner = set:DefaultOwner(id),
			}
		end
	end
	return Capture.BaseControlPoint(team, points)
end
