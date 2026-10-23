-- Votes, one at a time. A player calls one (Call), or, for a kick, enough
-- reports start one (StartKick; games.gameplay.reports): players never call a
-- kick vote. A kick that reports start while another vote runs waits for it
-- (Next). The electorate votes yes or no; a caller's yes is cast for them,
-- and a kick's target does not vote. A vote ends at its time, or once
-- everyone has voted (Finish): it passes when at least QUORUM_SHARE of the
-- electorate voted and at least PASS_SHARE of those votes are yes.
--
-- The server starts a vote of choices (StartChoices: the next-map vote, as
-- TF2's nextlevel vote in its choices mode), which waits its turn as a kick
-- does: each voter picks one option, and the most picked wins (the first
-- listed of a tie) once CHOICE_QUORUM_SHARE of the electorate picked; with
-- nobody picking (an empty server too) one is drawn at random.
-- Refusals carry TF2's wording (GameUI_vote_failed_*) as their detail.
--
-- A book is plain data keyed by whatever the controller gives (players), so
-- a rerun of this module changes the behaviour of the live book too.
local PlayMode = require("games.system.play_mode")
local Transaction = require("foundation.transaction")
local Sets = require("foundation.world.sets")
local ceil, error, format, ipairs, pairs, remove, tostring, type = math.ceil, error, string.format, ipairs, pairs, table.remove, tostring, type
module(...)

KIND_KICK = "kick"
KIND_MAP = "map"
KIND_RESET = "reset"
KIND_SCRAMBLE = "scramble"
KIND_SUPPORT = "support"
KIND_DIFFICULTY = "difficulty"
-- the server's vote of choices on the next map (never a player's call)
KIND_NEXTMAP = "nextmap"

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
-- CNextLevelIssue::GetQuorumRatio in choices mode: a few voters' preference
-- is enough when nobody else minds.
CHOICE_QUORUM_SHARE = 0.1

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
NOT_A_CHOICE = "not a choice"

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
	[NOT_A_CHOICE] = true,
}

-- Why a vote failed (GameUI_vote_failed_quorum and _yesno).
FAILED_QUORUM = "Not enough players voted."
FAILED_YES = "Not enough players voted \"Yes.\""

local KIND = Sets.Named("vote kind", {
	KIND_KICK,
	KIND_MAP,
	KIND_RESET,
	KIND_SCRAMBLE,
	KIND_SUPPORT,
	KIND_DIFFICULTY,
	KIND_NEXTMAP,
})

function New()
	return {
		current = nil,
		queue = {}, -- votes waiting: a kick's { target, reason }, or choices' { kind, options }
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
	KIND:Check(kind)
	if kind == KIND_KICK then Transaction.Refuse(KICK_BY_REPORTS, "To remove a player, hold Tab, right-click them and report them.") end
	if book.current then Transaction.Refuse(IN_PROGRESS, "A vote is currently in progress.") end
	if not facts.enabled[kind] then Transaction.Refuse(DISABLED, "Server has disabled that issue.") end
	if NEEDS_ROUNDS[kind] and PlayMode.IsSandbox(facts.mode) then Transaction.Refuse(MODE, "This vote needs a game running.") end
	if kind == KIND_SCRAMBLE and facts.scramblePending then Transaction.Refuse(SCRAMBLE_PENDING, "Teams are already set to be scrambled.") end
	local last = book.calledAt[req.caller]
	if last ~= nil and now - last < facts.cooldown then
		Transaction.Refuse(COOLDOWN, format("You cannot call a vote for %d seconds.", ceil(facts.cooldown - (now - last))))
	end
	book.calledAt[req.caller] = now
	return Start(book, kind, req.subject, req.caller, now, facts, nil)
end

-- Reports reached the count against target: their kick vote now, or nil
-- with it queued behind the running vote. facts adds immune (key -> true).
function StartKick(book, target, reason, now, facts)
	if facts.immune[target] then Transaction.Refuse(IMMUNE, "You may not vote to kick the server admin.") end
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

local function StartOptions(book, kind, options, now, facts)
	local vote = Start(book, kind, "", nil, now, facts, nil)
	vote.options = options
	return vote
end

-- The server's vote of choices among options (a list of what players read),
-- now, or nil with it queued behind the running vote.
function StartChoices(book, kind, options, now, facts)
	if book.current then
		book.queue[#book.queue + 1] = {
			kind = kind,
			options = options,
		}
		return nil
	end
	return StartOptions(book, kind, options, now, facts)
end

-- The next queued vote, started, once no vote runs; else nil.
function Next(book, now, facts)
	if book.current then return nil end
	while #book.queue > 0 do
		local waiting = remove(book.queue, 1)
		if waiting.options then return StartOptions(book, waiting.kind, waiting.options, now, facts) end
		if not facts.immune[waiting.target] then
			local vote = Start(book, KIND_KICK, waiting.target, nil, now, facts, waiting.target)
			vote.reason = waiting.reason
			return vote
		end
	end
	return nil
end

-- A voter's vote: yes (true) or no on a yes-or-no vote, an option's number
-- on a vote of choices.
function Cast(book, voter, choice)
	local vote = book.current
	if not vote then Transaction.Refuse(NO_VOTE, "No vote is running.") end
	if not vote.voters[voter] then Transaction.Refuse(NOT_VOTER, "You cannot vote in this vote.") end
	if vote.choices[voter] ~= nil then Transaction.Refuse(ALREADY_VOTED, "You have already voted.") end
	if vote.options then
		if type(choice) ~= "number" or vote.options[choice] == nil then Transaction.Refuse(NOT_A_CHOICE, "That is not one of the choices.") end
		vote.choices[voter] = choice
		return
	end
	if type(choice) ~= "boolean" then Transaction.Refuse(NOT_A_CHOICE, "This vote is yes or no.") end
	vote.choices[voter] = choice
end

-- What a voter cast, as their card shows it: an option's number on a vote
-- of choices, else BALLOT_YES or BALLOT_NO; BALLOT_NONE before they vote.
BALLOT_NONE, BALLOT_YES, BALLOT_NO = 0, 1, 2

function Ballot(vote, voter)
	local choice = vote.choices[voter]
	if choice == nil then return BALLOT_NONE end
	if choice == true then return BALLOT_YES end
	if choice == false then return BALLOT_NO end
	return choice
end

-- What a player hears as the running vote changes, from the state they had
-- (before) to the state they got (after; game_vote_state's running,
-- question, ends and cast): a vote starting, as TF2 plays Vote.Created,
-- their own cast landing (Vote.Cast.Yes or .No), else nil. The caller's yes
-- comes with the vote, so they hear it start. A vote's end is heard from
-- its result.
HEARD_STARTED = "started"
HEARD_CAST = "cast"

local function SameVote(before, after)
	return before.running and before.question == after.question and before.ends == after.ends
end

function Heard(before, after)
	if not after.running then return nil end
	if not SameVote(before, after) then return HEARD_STARTED end
	if before.cast == BALLOT_NONE and after.cast ~= BALLOT_NONE then return HEARD_CAST end
	return nil
end

-- A vote of choices' picks: each option's count, in the options' order.
function Counts(vote)
	local counts = {}
	for i = 1, #vote.options do counts[i] = 0 end
	for _, choice in pairs(vote.choices) do counts[choice] = counts[choice] + 1 end
	return counts
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
	return ceil((vote.options and CHOICE_QUORUM_SHARE or QUORUM_SHARE) * vote.electorateSize)
end

local function Close(book, vote, passed, why, choice)
	book.current = nil
	return {
		vote = vote,
		passed = passed,
		why = why,
		choice = choice,
	}
end

-- A vote of choices' winner: the most picked option, the first listed of a tie.
local function Winner(vote)
	local counts, best = Counts(vote), 1
	for i, count in ipairs(counts) do
		if count > counts[best] then best = i end
	end
	return best
end

-- The running vote's result once it is over (its time, everyone voted, or
-- force: closed now, as the level changes): { vote, passed, why, choice (a
-- vote of choices' winner), drawn (true when nobody picked it) }; else nil.
-- random(n) (1..n) draws a vote of choices' winner when nobody picked.
function Finish(book, now, force, random)
	local vote = book.current
	if not vote then return nil end
	local cast = 0
	for _ in pairs(vote.choices) do cast = cast + 1 end
	-- nobody to vote (an empty server) waits out the time
	local everyone = vote.electorateSize > 0 and cast >= vote.electorateSize
	if now < vote.ends and not everyone and not force then return nil end
	if vote.options and cast == 0 then
		local result = Close(book, vote, true, nil, random(#vote.options))
		result.drawn = true
		return result
	end
	if cast < Quorum(vote) then return Close(book, vote, false, FAILED_QUORUM) end
	if vote.options then return Close(book, vote, true, nil, Winner(vote)) end
	local yes = Tally(vote)
	if yes < PASS_SHARE * cast then return Close(book, vote, false, FAILED_YES) end
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
