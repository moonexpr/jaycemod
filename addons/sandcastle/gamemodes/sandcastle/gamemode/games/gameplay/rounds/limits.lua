-- Round limits: mp_round_fraglimit and mp_round_cashlimit win a round for
-- the first team to reach them (0: off), counted from the round's start by
-- a Tally: each team's frags (its kills of the enemy) and the money it has
-- earned (not what it held to begin with). Frags decide before money; both
-- teams at a
-- limit together go to the higher count, and an equal one is a tie, a
-- stalemate for games.gameplay.rounds to break. And the match's win
-- conditions on a map of each kind (WinConditions).
local ceil, ipairs, min, setmetatable, tostring = math.ceil, ipairs, math.min, setmetatable, tostring
local Economy = gameplay.economy
local Rounds = gameplay.rounds
local Teams = gameplay.teams
module(...)

-- A team this share of the way to a limit is close to winning (Calls).
CLOSE_SHARE = 0.8

local RED, BLUE = Teams.RED, Teams.BLUE
local W = Rounds.WINREASON

-------------------------------------------------------------------------------
-- Tally

Tally = {}
Tally.__index = Tally

function Tally.New()
	local t = setmetatable({}, Tally)
	t:Reset()
	return t
end

function Tally:Reset()
	self.frags = { [RED] = 0, [BLUE] = 0 }
	self.earned = { [RED] = 0, [BLUE] = 0 }
	self.firstBlood = false
	self.called = { [W.FRAGLIMIT] = {}, [W.CASHLIMIT] = {} } -- reason -> team -> true: close to winning, said
end

function Tally:Frag(team)
	self.frags[team] = self.frags[team] + 1
end

function Tally:Earn(team, amount)
	self.earned[team] = self.earned[team] + amount
end

function Tally:Frags(team) return self.frags[team] end
function Tally:Earned(team) return self.earned[team] end

local TEAMS = { RED, BLUE }

-- The announcer's cues since the last call, each once a round: { kind =
-- "first_blood", team } for the round's first frag (with the frag limit on),
-- and { kind = "close", team, reason } for a team CLOSE_SHARE of the way
-- to a limit.
function Tally:Calls(limits)
	local calls = {}
	if limits.frags > 0 and not self.firstBlood then
		for _, team in ipairs(TEAMS) do
			if self.frags[team] > 0 and not self.firstBlood then
				self.firstBlood = true
				calls[#calls + 1] = { kind = "first_blood", team = team }
			end
		end
	end
	for _, limit in ipairs({ { limits.frags, self.frags, W.FRAGLIMIT }, { limits.cash, self.earned, W.CASHLIMIT } }) do
		local value, counts, reason = limit[1], limit[2], limit[3]
		for _, team in ipairs(TEAMS) do
			if value > 0 and not self.called[reason][team] and counts[team] >= ceil(value * CLOSE_SHARE) then
				self.called[reason][team] = true
				calls[#calls + 1] = { kind = "close", team = team, reason = reason }
			end
		end
	end
	return calls
end

-------------------------------------------------------------------------------
-- Outcome

-- At limit (0: off) over counts (team -> n): { team, reason } for a winner,
-- { tie = true, reason } for both there with equal counts, or nil.
local function AtLimit(limit, counts, reason)
	if limit <= 0 then return nil end
	local red, blue = counts[RED] >= limit, counts[BLUE] >= limit
	if not (red or blue) then return nil end
	if red and blue and counts[RED] == counts[BLUE] then return { tie = true, reason = reason } end
	if red and (not blue or counts[RED] > counts[BLUE]) then return { team = RED, reason = reason } end
	return { team = BLUE, reason = reason }
end

-- The limits a mode plays to: mp_round_fraglimit and mp_round_cashlimit on
-- a map without an objective, both 0 where an objective decides the round
-- (mode.OBJECTIVE), so they never compete with it.
function Of(mode, fraglimit, cashlimit)
	if mode.OBJECTIVE then return { frags = 0, cash = 0 } end
	return { frags = fraglimit, cash = cashlimit }
end

-- limits = { frags, cash }; tally: the round's. The round's outcome by its
-- limits, frags first, or nil while no limit is reached.
function Outcome(limits, tally)
	return AtLimit(limits.frags, tally.frags, W.FRAGLIMIT) or AtLimit(limits.cash, tally.earned, W.CASHLIMIT)
end

-------------------------------------------------------------------------------
-- The match's win conditions

-- TF2's casual matches: mp_winlimit and mp_maxrounds as the
-- server_casual_*_win_conditions.cfg for the map's kind sets them, over
-- server_matchmaking_base.cfg's zeroes. name: the cfg's.
WIN_CONDITIONS = {
	ROUNDS = { name = "rounds", winlimit = 2, maxrounds = 0 },
	STOPWATCH = { name = "stopwatch", winlimit = 0, maxrounds = 2 },
	MAX_ROUNDS = { name = "max_rounds", winlimit = 0, maxrounds = 1 },
	-- Sandcastle's own, for a control-point map TF2 would play to the win
	-- limit: a capture can be a point on the score (score_style 1), so a
	-- win limit would end the match a few captures in; mp_timelimit ends it.
	CONTROL_POINTS = { name = "control_points", winlimit = 0, maxrounds = 0 },
	-- Sandcastle's own, for a hostage map: a round is won by rescue or by
	-- killing, so the match is ten rounds, not a count of wins.
	HOSTAGE = { name = "hostage", winlimit = 0, maxrounds = 10 },
}

-- map = { mvm, payload, ctf, controlPoints (the round's mode: KOTH and
-- arena are not), multipleTrains (a race), miniRounds, stages (the master's
-- rounds), switchTeams (the master's switch_teams), scorePerCapture (its
-- score_style 1) }. TF2's choice (CTFMatchDescCasual's
-- InitGameRulesSettingsPostEntity): an attack/defend map
-- (CTFGameRules::IsAttackDefenseMode) plays stopwatch; a payload race in
-- stages and CTF play one round; any other map goes to the first team to
-- the win limit, but for control-point maps and a score per capture
-- (CONTROL_POINTS). nil for MvM, whose waves decide.
function WinConditions(map)
	if map.mvm then return nil end
	if map.hostage then return WIN_CONDITIONS.HOSTAGE end
	if not map.multipleTrains and (map.payload or map.miniRounds or map.switchTeams) then return WIN_CONDITIONS.STOPWATCH end
	local raceInStages = map.payload and map.multipleTrains and map.miniRounds and map.stages > 1
	if raceInStages or map.ctf then return WIN_CONDITIONS.MAX_ROUNDS end
	if map.controlPoints or map.scorePerCapture then return WIN_CONDITIONS.CONTROL_POINTS end
	return WIN_CONDITIONS.ROUNDS
end

-------------------------------------------------------------------------------
-- The HUD

-- TF2's #TF_PlayingTo
local PLAYING_TO = "Playing to: "

local function Panel(reason, limit, counts, text)
	local panel = { reason = reason, label = PLAYING_TO .. text(limit), fills = {}, values = {} }
	for _, team in ipairs(TEAMS) do
		panel.fills[team] = min(counts[team] / limit, 1)
		panel.values[team] = text(counts[team])
	end
	return panel
end

-- The Player Destruction panels the HUD draws, bottom to top: one per limit
-- on (limits = { frags, cash }), the frag limit's first; each { reason,
-- label, fills = team -> share of the limit (at most 1), values = team ->
-- its count as text }. frags, earned: team -> the round's counts.
function Panels(limits, frags, earned)
	local panels = {}
	if limits.frags > 0 then panels[#panels + 1] = Panel(W.FRAGLIMIT, limits.frags, frags, tostring) end
	if limits.cash > 0 then panels[#panels + 1] = Panel(W.CASHLIMIT, limits.cash, earned, Economy.Format) end
	return panels
end
