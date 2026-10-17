-- Votes on the server (foundation.vote; ws/sh_votes.lua). A player's call
-- starts a vote and a timer for its end; every cast, the timer and a player
-- leaving may end it. A passed vote runs its effect: the next map
-- (nextlevel), a round restart or a scramble of the next round's teams
-- (the rounds feature), or a kick. Reports reaching the count
-- (WSReportsReached) start a kick vote, queued behind a running vote.
-- Every player hears the vote as vote_state; holders of the players
-- privilege (admins, by default) are never put to a kick vote.
local Vote = WS.require("foundation.vote")
local Permissions = WS.require("foundation.permissions")
local Refusal = WS.require("foundation.refusal")
local E = WS.Events

local TIMER = "ws_vote"
local book = Vote.New()

-- The map cycle (mapcyclefile under cfg/): one map a line, // comments.
local function ReadCycle()
	local text = file.Read("cfg/" .. GetConVar("mapcyclefile"):GetString(), "GAME") or ""
	local maps = {}
	for line in text:gmatch("[^\r\n]+") do
		local map = line:match("^%s*(.-)%s*$")
		if map ~= "" and map:sub(1, 2) ~= "//" then maps[#maps + 1] = map end
	end
	return maps
end

local MAPS = ReadCycle()
local IN_CYCLE = {}
for _, map in ipairs(MAPS) do IN_CYCLE[map] = true end

local function Facts()
	local humans = player.GetHumans()
	local enabled, immune = {}, {}
	for _, kind in ipairs(Vote.CALLABLE) do enabled[kind] = WS.VoteEnabled(kind) end
	for _, ply in ipairs(humans) do immune[ply] = WS.Can(ply, Permissions.PLAYERS) == true end
	return {
		electorate = humans,
		mode = WS.PlayMode(),
		enabled = enabled,
		duration = GetConVar("mp_vote_duration"):GetInt(),
		cooldown = GetConVar("mp_vote_cooldown"):GetInt(),
		scramblePending = WS.Active() and WS.Feature("rounds"):ScramblePending() or false,
		immune = immune,
	}
end

-- What a vote is about, as players read it.
local function SubjectText(vote)
	if vote.kind == Vote.KIND_KICK then return IsValid(vote.subject) and vote.subject:Nick() or "" end
	return vote.subject
end

local function StateFor(vote, ply)
	if not vote then
		return {
			running = false,
			kind = 0,
			question = "",
			caller = "",
			ends = 0,
			yes = 0,
			no = 0,
			quorum = 0,
			mine = false,
		}
	end
	local yes, no = Vote.Tally(vote)
	return {
		running = true,
		kind = WS.VoteKindIndex(vote.kind),
		question = WS.VoteQuestion(vote.kind, SubjectText(vote), vote.reason),
		caller = IsValid(vote.caller) and vote.caller:Nick() or "",
		ends = vote.ends,
		yes = yes,
		no = no,
		quorum = Vote.Quorum(vote),
		mine = vote.voters[ply] == true and vote.choices[ply] == nil,
	}
end

local function Broadcast()
	local vote = Vote.Current(book)
	for _, ply in ipairs(player.GetHumans()) do E.Fire("vote_state", StateFor(vote, ply), ply) end
end

local EFFECTS = {
	[Vote.KIND_KICK] = function(vote)
		if IsValid(vote.subject) then vote.subject:Kick("Kicked by vote") end
	end,
	[Vote.KIND_MAP] = function(vote) RunConsoleCommand("nextlevel", vote.subject) end,
	[Vote.KIND_RESET] = function() WS.Feature("rounds"):RestartRound() end,
	[Vote.KIND_SCRAMBLE] = function() WS.Feature("rounds"):ScheduleScramble() end,
}

local Started

-- A vote is over: its effect (unless its target already left), the result
-- for everyone, then the next queued kick, if any.
local function Conclude(result, targetLeft)
	if not result then return end
	timer.Remove(TIMER)
	local vote = result.vote
	local subject = SubjectText(vote)
	if result.passed and not targetLeft then EFFECTS[vote.kind](vote) end
	local text = result.passed and WS.VotePassed(vote.kind, subject) or result.why
	print("[Sandcastle] vote " .. vote.kind .. " " .. subject .. ": " .. text)
	E.Fire("vote_ended", {
		passed = result.passed,
		text = text,
	})
	local nextVote = Vote.Next(book, CurTime(), Facts())
	if nextVote then return Started(nextVote) end
	Broadcast()
end

function Started(vote)
	timer.Create(TIMER, vote.ends - CurTime(), 1, function() Conclude(Vote.Finish(book, CurTime())) end)
	Broadcast()
end

local function Refuse(ply, err)
	E.Fire("vote_refused", { text = Refusal.Detail(err, Vote.PLAYER) }, ply)
end

E.Listen("vote_call", "ws_votes", function(fields, ply)
	local kind = WS.VOTE_KINDS[fields.kind + 1]
	if not kind then return E.Fire("vote_refused", { text = "That is not a vote." }, ply) end
	local subject = ""
	if kind == Vote.KIND_MAP then
		if not IN_CYCLE[fields.subject] then
			return E.Fire("vote_refused", { text = "That map was not found in the server's map cycle." }, ply)
		end
		subject = fields.subject
	end
	local ok, result = pcall(Vote.Call, book, {
		caller = ply,
		kind = kind,
		subject = subject,
	}, CurTime(), Facts())
	if not ok then return Refuse(ply, result) end
	PrintMessage(HUD_PRINTTALK, ply:Nick() .. " wants to call a vote.")
	Started(result)
end)

E.Listen("vote_cast", "ws_votes", function(fields, ply)
	local ok, err = pcall(Vote.Cast, book, ply, fields.yes)
	if not ok then return Refuse(ply, err) end
	local result = Vote.Finish(book, CurTime())
	if result then return Conclude(result) end
	Broadcast()
end)

hook.Add("WSReportsReached", "ws_votes", function(target, reason)
	local ok, result = pcall(Vote.StartKick, book, target, reason, CurTime(), Facts())
	if not ok then
		print("[Sandcastle] reports against " .. target:Nick() .. ": " .. Refusal.Detail(result, Vote.PLAYER))
		return
	end
	if result then Started(result) end
end)

hook.Add("PlayerDisconnected", "ws_votes", function(ply)
	local result = Vote.Leave(book, ply)
	if result then return Conclude(result, true) end
	if Vote.Current(book) then Broadcast() end
end)

E.Listen("client_ready", "ws_votes", function(_, ply)
	E.Fire("vote_maps", { maps = MAPS }, ply)
	E.Fire("vote_state", StateFor(Vote.Current(book), ply), ply)
end)
