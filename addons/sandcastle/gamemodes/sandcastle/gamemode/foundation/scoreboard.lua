-- The team scoreboard (ws/cl_scoreboard.lua): Sandbox's rows of name,
-- kills, assists, deaths and ping, set out as TF2's (CTFClientScoreBoardDialog) are:
-- BLU's column on the left and RED's on the right, each under its team's
-- name and points, the spectators as a line of names, and the match's win
-- conditions beneath. A team's NPCs (the AI war's soldiers) sit in its column
-- beside its players.
local floor, format, ipairs, sort = math.floor, string.format, ipairs, table.sort
local Credit = require("foundation.kill_credit")
local Teams = require("foundation.teams")
module(...)

local RED, BLUE, SPECTATOR = Teams.RED, Teams.BLUE, Teams.SPECTATOR

COLUMN_TEAMS = { BLUE, RED }

local SECONDS_PER_MINUTE, SECONDS_PER_HOUR = 60, 3600

-- Most points first (foundation.kill_credit's: kills, and assists), then
-- most kills, then fewest deaths; players before NPCs; then by name.
local function Before(a, b)
	local pointsA, pointsB = Credit.Points(a.kills, a.assists), Credit.Points(b.kills, b.assists)
	if pointsA ~= pointsB then return pointsA > pointsB end
	if a.kills ~= b.kills then return a.kills > b.kills end
	if a.deaths ~= b.deaths then return a.deaths < b.deaths end
	if a.npc ~= b.npc then return not a.npc end
	return a.name < b.name
end

-- rows = { { name, team, kills, assists, deaths, npc }, ... }: players and NPCs alike.
-- Returns { teams = { [RED] = rows, [BLUE] = rows }, spectators = names,
-- unassigned = rows (anyone on neither team nor spectating) }.
function Build(rows)
	local board = {
		teams = {
			[RED] = {},
			[BLUE] = {},
		},
		spectators = {},
		unassigned = {},
	}
	for _, row in ipairs(rows) do
		local column = board.teams[row.team]
		if column then
			column[#column + 1] = row
		elseif row.team == SPECTATOR then
			board.spectators[#board.spectators + 1] = row.name
		else
			board.unassigned[#board.unassigned + 1] = row
		end
	end
	for _, column in ipairs({ board.teams[RED], board.teams[BLUE], board.unassigned }) do sort(column, Before) end
	sort(board.spectators)
	return board
end

-- Seconds as TF2's scoreboard clock: m:ss, or h:mm:ss from an hour.
function Clock(seconds)
	local h = floor(seconds / SECONDS_PER_HOUR)
	local m = floor(seconds % SECONDS_PER_HOUR / SECONDS_PER_MINUTE)
	local s = floor(seconds % SECONDS_PER_MINUTE)
	if h > 0 then return format("%d:%02d:%02d", h, m, s) end
	return format("%d:%02d", m, s)
end

local function Plural(n, word)
	return format("%d %s%s", n, word, n == 1 and "" or "s")
end

-- limits = { winlimit, maxrounds, roundsPlayed, timelimit (minutes),
-- timeLeft (seconds) }, as foundation.rounds' Round:Limits gives them. The
-- lines that say how the match ends: mp_winlimit, mp_maxrounds, then the
-- map's clock (#Scoreboard_TimeLeft, #Scoreboard_ChangeOnRoundEnd,
-- #Scoreboard_NoTimeLimit).
function WinConditions(limits)
	local lines = {}
	if limits.winlimit > 0 then lines[#lines + 1] = "Win limit: " .. Plural(limits.winlimit, "round") end
	if limits.maxrounds > 0 then
		lines[#lines + 1] = format("Rounds played: %d of %d", limits.roundsPlayed, limits.maxrounds)
	end
	if limits.timelimit <= 0 then
		lines[#lines + 1] = "No time limit"
	elseif limits.timeLeft > 0 then
		lines[#lines + 1] = "Time left on map: " .. Clock(limits.timeLeft)
	else
		lines[#lines + 1] = "Map will change at end of round"
	end
	return lines
end
