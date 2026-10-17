-- Players report one another, each report with one of TF2's four kick
-- reasons. Players cannot call a kick vote; enough reports of one player,
-- each from a different reporter, start one instead. How many is the
-- server's setting (mp_reports_kick_count), except on a server of exactly
-- three players, where that many reporters would be everyone but the target:
-- there two are enough. The report that reaches the count spends every
-- report of that player and names the reason the vote shows.
--
-- A book is plain data keyed by whatever the controller gives (players), so
-- a rerun of this module changes the behaviour of the live book too.
local Transaction = require("foundation.core.transaction")
local Sets = require("foundation.core.structs.sets")
local min, pairs = math.min, pairs
module(...)

-- TF2's kick reasons (TF_VoteKickReason_*), in its order.
NONE, CHEATING, IDLE, SCAMMING = "none", "cheating", "idle", "scamming"
REASONS = { NONE, CHEATING, IDLE, SCAMMING }

SMALL_SERVER_PLAYERS = 3
SMALL_SERVER_COUNT = 2

SELF_REPORT = "self report"
ALREADY_REPORTED = "already reported"

-- The refusals that are the player's mistake.
PLAYER = {
	[SELF_REPORT] = true,
	[ALREADY_REPORTED] = true,
}

local REASON = Sets.Named("reports reason", REASONS)

function New()
	return { against = {} } -- target -> { by = { reporter -> { reason, order } }, filed }
end

-- How many reports start a kick vote, with playerCount players on the server.
function Needed(playerCount, configured)
	if playerCount == SMALL_SERVER_PLAYERS then return min(configured, SMALL_SERVER_COUNT) end
	return configured
end

function Count(book, target)
	local entry = book.against[target]
	if not entry then return 0 end
	local n = 0
	for _ in pairs(entry.by) do n = n + 1 end
	return n
end

-- The commonest reason among a target's reports; a tie goes to the latest.
local function Commonest(entry)
	local tally, latest = {}, {}
	for _, report in pairs(entry.by) do
		tally[report.reason] = (tally[report.reason] or 0) + 1
		if (latest[report.reason] or 0) < report.order then latest[report.reason] = report.order end
	end
	local best
	for reason, n in pairs(tally) do
		if best == nil or n > tally[best] or (n == tally[best] and latest[reason] > latest[best]) then best = reason end
	end
	return best
end

-- Files reporter's report of target. Returns the reason for the kick vote
-- when this report reaches the count (and spends the reports), else nil.
function File(book, reporter, target, reason, playerCount, configured)
	REASON:Check(reason)
	if reporter == target then Transaction.Refuse(SELF_REPORT, "You cannot report yourself.") end
	local entry = book.against[target]
	if entry == nil then
		entry = {
			by = {},
			filed = 0,
		}
		book.against[target] = entry
	end
	if entry.by[reporter] then Transaction.Refuse(ALREADY_REPORTED, "You have already reported this player.") end
	entry.filed = entry.filed + 1
	entry.by[reporter] = {
		reason = reason,
		order = entry.filed,
	}
	if Count(book, target) < Needed(playerCount, configured) then return nil end
	local chosen = Commonest(entry)
	book.against[target] = nil
	return chosen
end

-- A player who leaves: their reports of others, and others' of them, go.
function Forget(book, player)
	book.against[player] = nil
	for _, entry in pairs(book.against) do entry.by[player] = nil end
end
