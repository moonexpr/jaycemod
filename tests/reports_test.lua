-- foundation.reports: players report one another with one of TF2's kick
-- reasons. Players cannot call a kick vote themselves; enough reports from
-- different players start one. The count is mp_reports_kick_count, and two
-- on a server of exactly three players, where three reporters would be
-- everyone but the target.
local T = dofile("tests/harness.lua")
local Reports = T.require("foundation.reports")
local Transaction = T.require("foundation.transaction")

local CONFIGURED = 3 -- mp_reports_kick_count's default, as the server reads it

local function Refused(kind, fn, ...)
	local ok, err = pcall(fn, ...)
	T.eq(ok, false, "refused")
	T.eq(Transaction.IsRefusal(err, Reports.PLAYER), true, "the player's refusal, not our bug")
	T.eq(err.kind, kind)
end

T.test("the kick count is the configured one, but two on a server of exactly three", function()
	T.defined(Reports.SMALL_SERVER_PLAYERS, "Reports.SMALL_SERVER_PLAYERS")
	T.defined(Reports.SMALL_SERVER_COUNT, "Reports.SMALL_SERVER_COUNT")
	T.eq(Reports.Needed(Reports.SMALL_SERVER_PLAYERS, CONFIGURED), Reports.SMALL_SERVER_COUNT)
	T.eq(Reports.Needed(Reports.SMALL_SERVER_PLAYERS + 1, CONFIGURED), CONFIGURED)
	T.eq(Reports.Needed(Reports.SMALL_SERVER_PLAYERS - 1, CONFIGURED), CONFIGURED)
	T.eq(Reports.Needed(Reports.SMALL_SERVER_PLAYERS, 1), 1, "a server asking for fewer keeps its own count")
end)

T.test("reports below the count start nothing", function()
	local book = Reports.New()
	T.eq(Reports.File(book, "alice", "bob", Reports.CHEATING, 6, CONFIGURED), nil)
	T.eq(Reports.File(book, "carol", "bob", Reports.IDLE, 6, CONFIGURED), nil)
	T.eq(Reports.Count(book, "bob"), 2)
end)

T.test("the report that reaches the count starts a kick vote, for the commonest reason", function()
	local book = Reports.New()
	Reports.File(book, "alice", "bob", Reports.CHEATING, 6, CONFIGURED)
	Reports.File(book, "carol", "bob", Reports.IDLE, 6, CONFIGURED)
	T.eq(Reports.File(book, "dave", "bob", Reports.CHEATING, 6, CONFIGURED), Reports.CHEATING)
	T.eq(Reports.Count(book, "bob"), 0, "the reports are spent on the vote")
end)

T.test("a tie between reasons goes to the latest report's", function()
	local book = Reports.New()
	Reports.File(book, "alice", "bob", Reports.CHEATING, 6, CONFIGURED)
	Reports.File(book, "carol", "bob", Reports.IDLE, 6, CONFIGURED)
	T.eq(Reports.File(book, "dave", "bob", Reports.SCAMMING, 6, CONFIGURED), Reports.SCAMMING)
end)

T.test("on a server of three, two reports are enough", function()
	local book = Reports.New()
	T.eq(Reports.File(book, "alice", "bob", Reports.IDLE, Reports.SMALL_SERVER_PLAYERS, CONFIGURED), nil)
	T.eq(Reports.File(book, "carol", "bob", Reports.IDLE, Reports.SMALL_SERVER_PLAYERS, CONFIGURED), Reports.IDLE)
end)

T.test("a player cannot report themself", function()
	Refused(Reports.SELF_REPORT, Reports.File, Reports.New(), "alice", "alice", Reports.CHEATING, 6, CONFIGURED)
end)

T.test("a second report of the same player by the same reporter is refused", function()
	local book = Reports.New()
	Reports.File(book, "alice", "bob", Reports.CHEATING, 6, CONFIGURED)
	Refused(Reports.ALREADY_REPORTED, Reports.File, book, "alice", "bob", Reports.IDLE, 6, CONFIGURED)
	T.eq(Reports.Count(book, "bob"), 1)
end)

T.test("an unknown reason is our bug, not the player's", function()
	local ok, err = pcall(Reports.File, Reports.New(), "alice", "bob", "rude", 6, CONFIGURED)
	T.eq(ok, false)
	T.eq(Transaction.IsRefusal(err, Reports.PLAYER), false)
end)

T.test("a player who leaves takes their reports, given and received, with them", function()
	local book = Reports.New()
	Reports.File(book, "alice", "bob", Reports.CHEATING, 6, CONFIGURED)
	Reports.File(book, "bob", "carol", Reports.IDLE, 6, CONFIGURED)
	Reports.File(book, "dave", "carol", Reports.IDLE, 6, CONFIGURED)
	Reports.Forget(book, "bob")
	T.eq(Reports.Count(book, "bob"), 0)
	T.eq(Reports.Count(book, "carol"), 1, "only dave's report of carol is left")
end)

T.test("every reason is one of TF2's four", function()
	T.eq(#Reports.REASONS, 4)
	local seen = {}
	for _, reason in ipairs(Reports.REASONS) do seen[reason] = true end
	for _, reason in ipairs({ Reports.CHEATING, Reports.IDLE, Reports.SCAMMING, Reports.NONE }) do
		T.eq(seen[reason], true, reason)
	end
end)

T.finish()
