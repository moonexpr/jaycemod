-- Votes on the server (games.gameplay.vote; ws/sh_votes.lua). A player's call
-- starts a vote and a timer for its end; every cast, the timer and a player
-- leaving may end it. A passed vote runs its effect: the next map
-- (nextlevel), a round restart or a scramble of the next round's teams
-- (the rounds feature), help for the caller's other team (ws/sv_handicap.lua),
-- the soldiers' difficulty (tf_bot_difficulty), or a kick. Reports reaching the count
-- (WSReportsReached) start a kick vote, queued behind a running vote.
-- Every player hears the vote as game_vote_state; holders of the players
-- privilege (admins, by default) are never put to a kick vote.
--
-- A map vote names a map the server plays: the map cycle's or the rounds'
-- maplist (VoteMaps), the list the Server tab shows.
--
-- The next-map vote (mp_vote_nextmap_enabled): once a map, as soon as the
-- match is one round from its end or over (Rounds.MapVoteDue), the server
-- calls a vote of choices among maplist maps (Rounds.MapVoteChoices: two of
-- this map's mode, one of another's), unless nextlevel is already set; the
-- most picked becomes nextlevel, or one drawn at random when nobody picks,
-- an empty server included, so an idle server moves on rather than
-- reloading its map. An empty server at the level change goes to a map
-- without a nav mesh instead (Rounds.IdleNextMap), so it builds one while
-- idle (ws/sv_nav.lua), unless players picked the next map or an admin set
-- nextlevel. Still running when the level changes
-- (WSChangeLevel), it is counted then.
local Vote = gameplay.vote
local Rounds = gameplay.rounds
local Permissions = system.permissions
local Transaction = transaction
local E = WS.Events

local TIMER = "ws_vote"
local book = Vote.New()
-- the next-map vote's, read by Conclude and the level change
local nextMapCalled = false -- once a map: the Lua state starts over with the map
local nextMapPicked = false -- players picked the next map, rather than its being drawn

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

-- The maps a map vote may name: the map cycle's, and the rounds' maplist
-- (the installed maps the gamemode plays, Rounds.MapsMatching's), since
-- GMod's own mapcycle.txt is empty. Read once a map, when first asked.
local voteMaps, inVoteMaps

local function VoteMaps()
	if voteMaps then return voteMaps, inVoteMaps end
	local rounds = WS.Feature("rounds")
	voteMaps, inVoteMaps = {}, {}
	for _, list in ipairs({ ReadCycle(), rounds and rounds.Maplist and (rounds:Maplist()) or {} }) do
		for _, map in ipairs(list) do
			if not inVoteMaps[map] then voteMaps[#voteMaps + 1], inVoteMaps[map] = map, true end
		end
	end
	table.sort(voteMaps)
	return voteMaps, inVoteMaps
end

local function Facts()
	local humans = player.GetHumans()
	local enabled, immune, teams = {}, {}, {}
	for _, kind in ipairs(Vote.CALLABLE) do enabled[kind] = WS.VoteEnabled(kind) end
	for _, ply in ipairs(humans) do
		immune[ply] = WS.Can(ply, Permissions.PLAYERS) == true
		teams[ply] = ply:Team()
	end
	return {
		electorate = humans,
		mode = WS.PlayMode(),
		enabled = enabled,
		duration = GetConVar("mp_vote_duration"):GetInt(),
		cooldown = GetConVar("mp_vote_cooldown"):GetInt(),
		scramblePending = WS.Active() and WS.Feature("rounds"):ScramblePending() or false,
		immune = immune,
		teams = teams,
		supported = WS.Handicap():Supported(),
		difficulty = Vote.DIFFICULTIES[GetConVar("tf_bot_difficulty"):GetInt() + 1],
	}
end

-- What a vote is about, as players read it.
local function SubjectText(vote)
	if vote.kind == Vote.KIND_KICK then return IsValid(vote.subject) and vote.subject:Nick() or "" end
	if vote.kind == Vote.KIND_SUPPORT then return team.GetName(vote.subject) end
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
			cast = Vote.BALLOT_NONE,
			options = {},
			counts = {},
		}
	end
	local yes, no, counts = 0, 0, {}
	if vote.options then counts = Vote.Counts(vote) else yes, no = Vote.Tally(vote) end
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
		cast = Vote.Ballot(vote, ply),
		options = vote.options or {},
		counts = counts,
	}
end

local function Broadcast()
	local vote = Vote.Current(book)
	for _, ply in ipairs(player.GetHumans()) do E.Fire("game_vote_state", StateFor(vote, ply), ply) end
end

local EFFECTS = {
	[Vote.KIND_KICK] = function(vote)
		if IsValid(vote.subject) then vote.subject:Kick("Kicked by vote") end
	end,
	[Vote.KIND_MAP] = function(vote) RunConsoleCommand("nextlevel", vote.subject) end,
	[Vote.KIND_RESET] = function() WS.Feature("rounds"):RestartRound() end,
	[Vote.KIND_SCRAMBLE] = function() WS.Feature("rounds"):ScheduleScramble() end,
	[Vote.KIND_SUPPORT] = function(vote) WS.GrantHandicap(vote.subject) end,
	[Vote.KIND_DIFFICULTY] = function(vote) GetConVar("tf_bot_difficulty"):SetInt(Vote.DifficultyLevel(vote.subject)) end,
	-- known at once (WS.VotedNextLevel, which the rounds feature changes level
	-- to): the level may be changing now, before the queued nextlevel runs,
	-- and Lua may not set the engine's convar itself
	[Vote.KIND_NEXTMAP] = function(vote)
		WS.VotedNextLevel = vote.subject
		RunConsoleCommand("nextlevel", vote.subject)
	end,
}

local Started

-- A vote is over: its effect (unless its target already left), the result
-- for everyone, then the next queued kick, if any.
local function Conclude(result, targetLeft)
	if not result then return end
	timer.Remove(TIMER)
	local vote = result.vote
	-- a vote of choices is about the option it chose
	if result.choice then vote.subject = vote.options[result.choice] end
	local subject = SubjectText(vote)
	if result.passed and not targetLeft then EFFECTS[vote.kind](vote) end
	if vote.kind == Vote.KIND_NEXTMAP and result.passed and not result.drawn then nextMapPicked = true end
	local text = result.passed and WS.VotePassed(vote.kind, subject) or result.why
	print("[Sandcastle] vote " .. vote.kind .. " " .. subject .. ": " .. text)
	E.Fire("game_vote_ended", {
		passed = result.passed,
		text = text,
	})
	local nextVote = Vote.Next(book, CurTime(), Facts())
	if nextVote then return Started(nextVote) end
	Broadcast()
end

function Started(vote)
	timer.Create(TIMER, vote.ends - CurTime(), 1, function() Conclude(Vote.Finish(book, CurTime(), false, math.random)) end)
	Broadcast()
end

local function Refuse(ply, err)
	E.Fire("game_vote_refused", { text = Transaction.Detail(err, Vote.PLAYER) }, ply)
end

E.Listen("game_vote_call", "ws_votes", function(fields, ply)
	local kind = WS.VOTE_KINDS[fields.kind + 1]
	if not kind then return E.Fire("game_vote_refused", { text = "That is not a vote." }, ply) end
	local subject = ""
	if kind == Vote.KIND_MAP then
		local _, known = VoteMaps()
		if not known[fields.subject] then
			return E.Fire("game_vote_refused", { text = "That map is not one the server plays." }, ply)
		end
		subject = fields.subject
	end
	-- the model checks a level; a support vote's team is the model's to pick
	if kind == Vote.KIND_DIFFICULTY then subject = fields.subject end
	local ok, result = pcall(Vote.Call, book, {
		caller = ply,
		kind = kind,
		subject = subject,
	}, CurTime(), Facts())
	if not ok then return Refuse(ply, result) end
	PrintMessage(HUD_PRINTTALK, ply:Nick() .. " wants to call a vote.")
	Started(result)
end)

-- choice: an option's number on a vote of choices, else 0 and yes counts
E.Listen("game_vote_cast", "ws_votes", function(fields, ply)
	local choice = fields.choice
	if choice == 0 then choice = fields.yes end
	local ok, err = pcall(Vote.Cast, book, ply, choice)
	if not ok then return Refuse(ply, err) end
	local result = Vote.Finish(book, CurTime(), false, math.random)
	if result then return Conclude(result) end
	Broadcast()
end)

hook.Add("WSReportsReached", "ws_votes", function(target, reason)
	local ok, result = pcall(Vote.StartKick, book, target, reason, CurTime(), Facts())
	if not ok then
		print("[Sandcastle] reports against " .. target:Nick() .. ": " .. Transaction.Detail(result, Vote.PLAYER))
		return
	end
	if result then Started(result) end
end)

hook.Add("PlayerDisconnected", "ws_votes", function(ply)
	local result = Vote.Leave(book, ply)
	if result then return Conclude(result, true) end
	if Vote.Current(book) then Broadcast() end
end)

-- The next-map vote ---------------------------------------------------------------

-- CTFGameRules::ManageServerSideVoteCreation's throttle, about.
local NEXTMAP_CHECK_SECONDS = 1
local NEXTMAP_TIMER = "ws_vote_nextmap"

local function CheckNextMapVote()
	if nextMapCalled or not WS.Active() then return end
	if not GetConVar("mp_vote_nextmap_enabled"):GetBool() or GetConVar("nextlevel"):GetString() ~= "" then return end
	local rounds = WS.Feature("rounds")
	if not Rounds.MapVoteDue(rounds:MatchEndFacts(CurTime())) then return end
	nextMapCalled = true
	local maps, filter = rounds:Maplist()
	local options = Rounds.MapVoteChoices(maps, game.GetMap(), filter, math.random)
	if #options == 0 then return end
	local vote = Vote.StartChoices(book, Vote.KIND_NEXTMAP, options, CurTime(), Facts())
	if vote then Started(vote) end
end

timer.Create(NEXTMAP_TIMER, NEXTMAP_CHECK_SECONDS, 0, CheckNextMapVote)

-- Whether the map has a nav mesh to load.
local function HasNav(map)
	return file.Exists("maps/" .. map .. ".nav", "GAME")
end

-- The rounds feature is about to change level: a next-map vote still running
-- is counted now, so its map is the one changed to; then an empty server
-- whose next map nobody chose goes to one without a nav mesh.
hook.Add("WSChangeLevel", "ws_votes", function()
	local vote = Vote.Current(book)
	if vote and vote.kind == Vote.KIND_NEXTMAP then Conclude(Vote.Finish(book, CurTime(), true, math.random)) end
	if #player.GetHumans() > 0 or nextMapPicked then return end
	-- an admin's nextlevel, set with no vote called
	if not WS.VotedNextLevel and GetConVar("nextlevel"):GetString() ~= "" then return end
	local idle = Rounds.IdleNextMap((WS.Feature("rounds"):Maplist()), game.GetMap(), HasNav, math.random)
	if not idle then return end
	WS.VotedNextLevel = idle
	RunConsoleCommand("nextlevel", idle)
end)

E.Listen("system_client_ready", "ws_votes", function(_, ply)
	E.Fire("game_vote_maps", { maps = (VoteMaps()) }, ply)
	E.Fire("game_vote_state", StateFor(Vote.Current(book), ply), ply)
end)
