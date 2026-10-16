-- Votes, one at a time. A player calls one (Call), or, for a kick, enough
-- reports start one (StartKick; foundation.reports): players never call a
-- kick vote. A kick that reports start while another vote runs waits for it
-- (Next). The electorate votes yes or no; a caller's yes is cast for them,
-- and a kick's target does not vote. A vote ends at its time, or once
-- everyone has voted (Finish): it passes when at least QUORUM_SHARE of the
-- electorate voted and at least PASS_SHARE of those votes are yes.
-- Refusals carry TF2's wording (GameUI_vote_failed_*) as their detail.
--
-- A book is plain data keyed by whatever the controller gives (players), so
-- a rerun of this module changes the behaviour of the live book too.
local PlayMode = require("foundation.play_mode")
local Refusal = require("foundation.refusal")
local ceil, error, format, ipairs, pairs, remove, tostring = math.ceil, error, string.format, ipairs, pairs, table.remove, tostring
module(...)

KIND_KICK = "kick"
KIND_MAP = "map"
KIND_RESET = "reset"
KIND_SCRAMBLE = "scramble"
KIND_SUPPORT = "support"
KIND_DIFFICULTY = "difficulty"

-- The kinds players call, in the Server tab's order.
CALLABLE = { KIND_DIFFICULTY, KIND_MAP, KIND_SUPPORT, KIND_RESET, KIND_SCRAMBLE }

-- The kinds that change a running match, so need the rounds running.
local NEEDS_ROUNDS = {
	[KIND_RESET] = true,
	[KIND_SCRAMBLE] = true,
	[KIND_SUPPORT] = true,
}

QUORUM_SHARE = 0.5
PASS_SHARE = 0.6

IN_PROGRESS = "in progress"
KICK_BY_REPORTS = "kick by reports"
DISABLED = "disabled"
MODE = "mode"
SCRAMBLE_PENDING = "scramble pending"
COOLDOWN = "cooldown"
IMMUNE = "immune"
NOT_VOTER = "not a voter"
ALREADY_VOTED = "already voted"
NO_VOTE = "no vote"

-- The refusals that are the player's mistake.
PLAYER = {
	[IN_PROGRESS] = true,
	[KICK_BY_REPORTS] = true,
	[DISABLED] = true,
	[MODE] = true,
	[SCRAMBLE_PENDING] = true,
	[COOLDOWN] = true,
	[IMMUNE] = true,
	[NOT_VOTER] = true,
	[ALREADY_VOTED] = true,
	[NO_VOTE] = true,
}

-- Why a vote failed (GameUI_vote_failed_quorum and _yesno).
FAILED_QUORUM = "Not enough players voted."
FAILED_YES = "Not enough players voted \"Yes.\""

local KNOWN = {
	[KIND_KICK] = true,
	[KIND_MAP] = true,
	[KIND_RESET] = true,
	[KIND_SCRAMBLE] = true,
	[KIND_SUPPORT] = true,
	[KIND_DIFFICULTY] = true,
}

function New()
	return {
		current = nil,
		queue = {}, -- kicks waiting: { target, reason }
		calledAt = {}, -- caller -> when they last called
	}
end

function Current(book)
	return book.current
end

-- facts = { electorate (a list), duration }; leaving out is a key to keep
-- out of the electorate (a kick's target).
local function Start(book, kind, subject, caller, now, facts, leavingOut)
	local voters, count = {}, 0
	for _, voter in ipairs(facts.electorate) do
		if voter ~= leavingOut then
			voters[voter] = true
			count = count + 1
		end
	end
	local vote = {
		kind = kind,
		subject = subject,
		caller = caller,
		ends = now + facts.duration,
		voters = voters,
		electorateSize = count,
		choices = {}, -- voter -> true (yes) or false (no)
	}
	if caller ~= nil and voters[caller] then vote.choices[caller] = true end
	book.current = vote
	return vote
end

-- req = { caller, kind, subject }; facts = { electorate, mode, enabled
-- (kind -> true), duration, cooldown, scramblePending }. The vote, or a
-- refusal.
function Call(book, req, now, facts)
	local kind = req.kind
	if not KNOWN[kind] then error("vote: unknown kind " .. tostring(kind), 2) end
	if kind == KIND_KICK then Refusal.Raise(KICK_BY_REPORTS, "To remove a player, hold Tab, right-click them and report them.") end
	if book.current then Refusal.Raise(IN_PROGRESS, "A vote is currently in progress.") end
	if not facts.enabled[kind] then Refusal.Raise(DISABLED, "Server has disabled that issue.") end
	if NEEDS_ROUNDS[kind] and PlayMode.IsSandbox(facts.mode) then Refusal.Raise(MODE, "This vote needs a game running.") end
	if kind == KIND_SCRAMBLE and facts.scramblePending then Refusal.Raise(SCRAMBLE_PENDING, "Teams are already set to be scrambled.") end
	local last = book.calledAt[req.caller]
	if last ~= nil and now - last < facts.cooldown then
		Refusal.Raise(COOLDOWN, format("You cannot call a vote for %d seconds.", ceil(facts.cooldown - (now - last))))
	end
	book.calledAt[req.caller] = now
	return Start(book, kind, req.subject, req.caller, now, facts, nil)
end

-- Reports reached the count against target: their kick vote now, or nil
-- with it queued behind the running vote. facts adds immune (key -> true).
function StartKick(book, target, reason, now, facts)
	if facts.immune[target] then Refusal.Raise(IMMUNE, "You may not vote to kick the server admin.") end
	if book.current then
		book.queue[#book.queue + 1] = {
			target = target,
			reason = reason,
		}
		return nil
	end
	local vote = Start(book, KIND_KICK, target, nil, now, facts, target)
	vote.reason = reason
	return vote
end

-- The next queued kick, started, once no vote runs; else nil.
function Next(book, now, facts)
	if book.current then return nil end
	while #book.queue > 0 do
		local waiting = remove(book.queue, 1)
		if not facts.immune[waiting.target] then
			local vote = Start(book, KIND_KICK, waiting.target, nil, now, facts, waiting.target)
			vote.reason = waiting.reason
			return vote
		end
	end
	return nil
end

function Cast(book, voter, yes)
	local vote = book.current
	if not vote then Refusal.Raise(NO_VOTE, "No vote is running.") end
	if not vote.voters[voter] then Refusal.Raise(NOT_VOTER, "You cannot vote in this vote.") end
	if vote.choices[voter] ~= nil then Refusal.Raise(ALREADY_VOTED, "You have already voted.") end
	vote.choices[voter] = yes == true
end

function Tally(vote)
	local yes, no = 0, 0
	for _, choice in pairs(vote.choices) do
		if choice then yes = yes + 1 else no = no + 1 end
	end
	return yes, no
end

-- The votes a vote needs cast to count.
function Quorum(vote)
	return ceil(QUORUM_SHARE * vote.electorateSize)
end

local function Close(book, vote, passed, why)
	book.current = nil
	return {
		vote = vote,
		passed = passed,
		why = why,
	}
end

-- The running vote's result once it is over: { vote, passed, why }; else nil.
function Finish(book, now)
	local vote = book.current
	if not vote then return nil end
	local yes, no = Tally(vote)
	local everyone = yes + no >= vote.electorateSize
	if now < vote.ends and not everyone then return nil end
	if yes + no < Quorum(vote) then return Close(book, vote, false, FAILED_QUORUM) end
	if yes < PASS_SHARE * (yes + no) then return Close(book, vote, false, FAILED_YES) end
	return Close(book, vote, true, nil)
end

-- A player left: they no longer vote, and a kick waiting for them is
-- dropped. When they were the running kick's target the vote is over, as it
-- wanted: its result.
function Leave(book, player)
	for i = #book.queue, 1, -1 do
		if book.queue[i].target == player then remove(book.queue, i) end
	end
	local vote = book.current
	if not vote then return nil end
	if vote.kind == KIND_KICK and vote.subject == player then return Close(book, vote, true, nil) end
	if vote.voters[player] then
		vote.voters[player] = nil
		vote.choices[player] = nil
		vote.electorateSize = vote.electorateSize - 1
	end
	return nil
end
