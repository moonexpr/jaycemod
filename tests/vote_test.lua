-- foundation.vote: one vote at a time, called by a player or, for a kick,
-- started by enough reports (foundation.reports). The electorate votes
-- yes or no; the caller's yes is cast for them. A vote passes when enough of
-- the electorate voted (QUORUM_SHARE) and enough of those votes are yes
-- (PASS_SHARE). Refusals use TF2's reasons (GameUI_vote_failed_*).
local T = dofile("tests/harness.lua")
local Vote = T.require("foundation.vote")
local PlayMode = T.require("foundation.play_mode")
local Refusal = T.require("foundation.refusal")

local DURATION, COOLDOWN = 20, 120 -- mp_vote_duration's and mp_vote_cooldown's defaults, as the server reads them

local function Facts(over)
	local facts = {
		electorate = { "alice", "bob", "carol", "dave", "erin" },
		mode = PlayMode.GAMEPLAY,
		enabled = {
			[Vote.KIND_MAP] = true,
			[Vote.KIND_RESET] = true,
			[Vote.KIND_SCRAMBLE] = true,
			[Vote.KIND_SUPPORT] = true,
			[Vote.KIND_DIFFICULTY] = true,
		},
		duration = DURATION,
		cooldown = COOLDOWN,
		scramblePending = false,
		immune = {},
	}
	for k, v in pairs(over or {}) do facts[k] = v end
	return facts
end

local function Refused(kind, fn, ...)
	local ok, err = pcall(fn, ...)
	T.eq(ok, false, "refused")
	T.eq(Refusal.Is(err, Vote.PLAYER), true, "the player's refusal: " .. tostring(err and err.kind or err))
	T.eq(err.kind, kind)
end

local function Call(book, caller, kind, subject, now, facts)
	return Vote.Call(book, {
		caller = caller,
		kind = kind,
		subject = subject or "",
	}, now or 0, facts or Facts())
end

T.test("a called vote runs for the vote's duration with the caller's yes cast", function()
	local book = Vote.New()
	local vote = Call(book, "alice", Vote.KIND_MAP, "cp_dustbowl", 100)
	T.eq(vote.kind, Vote.KIND_MAP)
	T.eq(vote.subject, "cp_dustbowl")
	T.eq(vote.ends, 100 + DURATION)
	local yes, no = Vote.Tally(vote)
	T.eq(yes, 1)
	T.eq(no, 0)
	T.eq(Vote.Current(book), vote)
end)

T.test("one vote at a time", function()
	local book = Vote.New()
	Call(book, "alice", Vote.KIND_MAP, "cp_dustbowl")
	Refused(Vote.IN_PROGRESS, Call, book, "bob", Vote.KIND_RESET)
end)

T.test("players cannot call a kick vote", function()
	Refused(Vote.KICK_BY_REPORTS, Call, Vote.New(), "alice", Vote.KIND_KICK, "bob")
end)

T.test("a kind the server disabled is refused", function()
	local facts = Facts()
	facts.enabled[Vote.KIND_SCRAMBLE] = nil
	Refused(Vote.DISABLED, Call, Vote.New(), "alice", Vote.KIND_SCRAMBLE, "", 0, facts)
end)

T.test("restart, scramble and team help need the rounds running; map votes do not", function()
	local sandbox = Facts({ mode = PlayMode.SANDBOX })
	for _, kind in ipairs({ Vote.KIND_RESET, Vote.KIND_SCRAMBLE, Vote.KIND_SUPPORT }) do
		Refused(Vote.MODE, Call, Vote.New(), "alice", kind, "", 0, sandbox)
	end
	T.eq(Call(Vote.New(), "alice", Vote.KIND_MAP, "cp_dustbowl", 0, sandbox).kind, Vote.KIND_MAP)
end)

T.test("a scramble already set is refused", function()
	Refused(Vote.SCRAMBLE_PENDING, Call, Vote.New(), "alice", Vote.KIND_SCRAMBLE, "", 0, Facts({ scramblePending = true }))
end)

T.test("a caller waits the cooldown between their votes; others need not", function()
	local book = Vote.New()
	Call(book, "alice", Vote.KIND_MAP, "cp_dustbowl", 0)
	Vote.Finish(book, DURATION)
	Refused(Vote.COOLDOWN, Call, book, "alice", Vote.KIND_RESET, "", DURATION + 1)
	T.eq(Call(book, "bob", Vote.KIND_RESET, "", DURATION + 1).kind, Vote.KIND_RESET)
	Vote.Finish(book, 2 * DURATION + 1)
	T.eq(Call(book, "alice", Vote.KIND_RESET, "", COOLDOWN).kind, Vote.KIND_RESET, "after the cooldown")
end)

T.test("only the electorate votes, once each", function()
	local book = Vote.New()
	local vote = Call(book, "alice", Vote.KIND_MAP, "cp_dustbowl")
	Refused(Vote.NOT_VOTER, Vote.Cast, book, "zed", true)
	Refused(Vote.ALREADY_VOTED, Vote.Cast, book, "alice", false)
	Vote.Cast(book, "bob", false)
	Refused(Vote.ALREADY_VOTED, Vote.Cast, book, "bob", true)
	local yes, no = Vote.Tally(vote)
	T.eq(yes, 1)
	T.eq(no, 1)
end)

T.test("casting with no vote running is refused", function()
	Refused(Vote.NO_VOTE, Vote.Cast, Vote.New(), "alice", true)
end)

T.test("a vote passes with a quorum and enough yes votes", function()
	T.defined(Vote.QUORUM_SHARE, "Vote.QUORUM_SHARE")
	T.defined(Vote.PASS_SHARE, "Vote.PASS_SHARE")
	local book = Vote.New()
	Call(book, "alice", Vote.KIND_MAP, "cp_dustbowl")
	Vote.Cast(book, "bob", true)
	Vote.Cast(book, "carol", true)
	local result = Vote.Finish(book, DURATION)
	T.eq(result.passed, true)
	T.eq(Vote.Current(book), nil)
end)

T.test("too few voters fail it for quorum", function()
	local book = Vote.New()
	Call(book, "alice", Vote.KIND_MAP, "cp_dustbowl")
	local result = Vote.Finish(book, DURATION)
	T.eq(result.passed, false)
	T.eq(result.why, Vote.FAILED_QUORUM)
end)

T.test("too few yes votes fail it", function()
	local book = Vote.New()
	Call(book, "alice", Vote.KIND_MAP, "cp_dustbowl")
	Vote.Cast(book, "bob", false)
	Vote.Cast(book, "carol", false)
	local result = Vote.Finish(book, DURATION)
	T.eq(result.passed, false)
	T.eq(result.why, Vote.FAILED_YES)
end)

T.test("a vote is not over before its time, unless everyone has voted", function()
	local book = Vote.New()
	Call(book, "alice", Vote.KIND_MAP, "cp_dustbowl", 0, Facts({ electorate = { "alice", "bob" } }))
	T.eq(Vote.Finish(book, DURATION - 1), nil, "still running")
	Vote.Cast(book, "bob", true)
	T.eq(Vote.Finish(book, 1).passed, true, "everyone voted: over at once")
end)

T.test("reports start a kick vote, without a caller, the target not voting", function()
	local book = Vote.New()
	local vote = Vote.StartKick(book, "bob", "cheating", 0, Facts())
	T.eq(vote.kind, Vote.KIND_KICK)
	T.eq(vote.subject, "bob")
	T.eq(vote.reason, "cheating")
	local yes = Vote.Tally(vote)
	T.eq(yes, 0, "no caller's yes")
	Refused(Vote.NOT_VOTER, Vote.Cast, book, "bob", false)
end)

T.test("a kick reports start while a vote runs waits for it to end", function()
	local book = Vote.New()
	local first = Call(book, "alice", Vote.KIND_MAP, "cp_dustbowl")
	T.eq(Vote.StartKick(book, "bob", "idle", 0, Facts()), nil, "queued")
	T.eq(Vote.Current(book), first)
	Vote.Finish(book, DURATION)
	local kick = Vote.Next(book, DURATION, Facts())
	T.eq(kick.kind, Vote.KIND_KICK)
	T.eq(kick.subject, "bob")
	T.eq(kick.ends, DURATION + DURATION)
end)

T.test("an immune player is never put to a kick vote", function()
	Refused(Vote.IMMUNE, Vote.StartKick, Vote.New(), "dave", "idle", 0, Facts({ immune = { dave = true } }))
end)

T.test("a player who leaves no longer counts; a kick's target leaving ends it", function()
	local book = Vote.New()
	Call(book, "alice", Vote.KIND_MAP, "cp_dustbowl", 0, Facts({ electorate = { "alice", "bob", "carol" } }))
	Vote.Cast(book, "bob", true)
	Vote.Leave(book, "bob")
	local yes = Vote.Tally(Vote.Current(book))
	T.eq(yes, 1, "bob's vote went with him")
	Vote.Finish(book, DURATION)
	Vote.StartKick(book, "carol", "idle", 0, Facts({ electorate = { "alice", "carol", "dave" } }))
	local ended = Vote.Leave(book, "carol")
	T.eq(ended ~= nil, true, "the kick is over")
	T.eq(ended.passed, true, "the target is gone, as the vote wanted")
	T.eq(Vote.Current(book), nil)
end)

T.finish()
