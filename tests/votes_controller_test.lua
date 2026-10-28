-- ws/sv_votes.lua: runs games.gameplay.vote on the server. A player's call
-- starts a vote and its timer; casts and the timer end it; a passed vote
-- runs its effect; reports reaching the count (WSReportsReached) start a
-- kick vote, or queue it behind the running one. Run against fake events,
-- players, timers, convars and the rounds feature.
local T = dofile("tests/harness.lua")
local Vote = gameplay.vote
local Permissions = system.permissions
local PlayMode = system.play_mode

local KINDS = {
	Vote.KIND_KICK,
	Vote.KIND_MAP,
	Vote.KIND_RESET,
	Vote.KIND_SCRAMBLE,
	Vote.KIND_SUPPORT,
	Vote.KIND_DIFFICULTY,
	Vote.KIND_NEXTMAP,
}

local function Index(kind)
	for i, k in ipairs(KINDS) do
		if k == kind then return i - 1 end
	end
end

local RED, BLUE = 2, 3 -- TF2's teams

local function Player(name, held, team)
	local p = {
		name = name,
		held = held or {},
		got = {},
		team = team or RED,
	}
	function p:Nick() return self.name end
	function p:IsPlayer() return true end
	function p:Team() return self.team end
	return p
end

local function Load(players, opts)
	opts = opts or {}
	local s = {
		now = 100,
		listeners = {},
		hooks = {},
		timers = {},
		ended = {},
		kicked = {},
		commands = {},
		restarts = 0,
		scrambles = 0,
		scramblePending = false,
		cycle = opts.cycle or "cp_dustbowl\n// a comment\n\npl_badwater\n",
		-- the rounds feature's match (MatchEndFacts) and maplist (Maplist)
		match = {
			winlimit = 0,
			maxrounds = 0,
			timelimit = 0,
			roundsPlayed = 0,
			timeLeft = 0,
			scores = { 0, 0 },
			over = false,
		},
		maplist = opts.maplist or { "cp_steel", "koth_viaduct", "pl_badwater", "pl_goldrush", "pl_upward" },
		filter = "^pl_|^cp_|^koth_",
		map = "pl_upward",
	}
	-- the maps with a nav mesh: every maplist map unless told
	s.navs = opts.navs or { cp_steel = true, koth_viaduct = true, pl_badwater = true, pl_goldrush = true, pl_upward = true }
	local convars = {
		mp_vote_duration = 20,
		mp_vote_cooldown = 120,
		mapcyclefile = "mapcycle.txt",
		mp_vote_nextmap_enabled = opts.nextmapEnabled == false and 0 or 1,
		nextlevel = opts.nextlevel or "",
		tf_bot_difficulty = 1,
	}
	s.convars = convars
	s.handicaps = {}
	local function Got(ply, name, fields)
		ply.got[#ply.got + 1] = {
			name = name,
			fields = fields,
		}
	end
	local W = {
		require = T.require,
		VOTE_KINDS = KINDS,
		VoteKindIndex = Index,
		VoteEnabled = function(kind) return kind ~= Vote.KIND_KICK and not (opts.disabled or {})[kind] end,
		Handicap = function() return { Supported = function() return s.supported or 0 end } end,
		GrantHandicap = function(t) s.handicaps[#s.handicaps + 1] = t end,
		VoteQuestion = function(kind, subject) return kind .. "?" .. subject end,
		VotePassed = function(kind, subject) return kind .. "!" .. subject end,
		Events = {
			Listen = function(name, _, fn) s.listeners[name] = fn end,
			Fire = function(name, fields, ply)
				if ply then return Got(ply, name, fields) end
				for _, p in ipairs(players) do Got(p, name, fields) end
			end,
		},
		Can = function(ply, name) return ply.held[name] == true end,
		PlayMode = function() return opts.mode or PlayMode.GAMEPLAY end,
		Active = function() return (opts.mode or PlayMode.GAMEPLAY) ~= PlayMode.SANDBOX end,
		Feature = function(name)
			assert(name == "rounds", name)
			return {
				RestartRound = function() s.restarts = s.restarts + 1 end,
				ScheduleScramble = function() s.scrambles = s.scrambles + 1 end,
				ScramblePending = function() return s.scramblePending end,
				MatchEndFacts = function() return s.match end,
				Maplist = function() return s.maplist, s.filter end,
			}
		end,
	}
	for _, p in ipairs(players) do
		function p:Kick(reason) s.kicked[#s.kicked + 1] = { ply = self, reason = reason } end
	end
	s.W = W
	local env = setmetatable({
		WS = W,
		CurTime = function() return s.now end,
		IsValid = function(v) return v ~= nil end,
		player = { GetHumans = function() return players end },
		hook = { Add = function(name, _, fn) s.hooks[name] = fn end },
		timer = {
			-- repetitions 0: it repeats every delay
			Create = function(name, delay, repetitions, fn)
				s.timers[name] = { at = s.now + delay, delay = delay, repeats = repetitions == 0, fn = fn }
			end,
			Remove = function(name) s.timers[name] = nil end,
		},
		GetConVar = function(name)
			return {
				GetInt = function() return convars[name] end,
				GetFloat = function() return convars[name] end,
				GetString = function() return convars[name] end,
				GetBool = function() return convars[name] ~= 0 end,
				-- GMod: "attempted to modify ConVar not created by Lua"
				SetString = function() error("attempted to modify ConVar not created by Lua", 2) end,
				SetInt = function(_, value) convars[name] = value end,
			}
		end,
		game = { GetMap = function() return s.map end },
		team = { GetName = function(t) return ({ [RED] = "RED", [BLUE] = "BLU" })[t] end },
		math = setmetatable({ random = function(a, b) if b then return a end return 1 end }, { __index = math }),
		file = {
			Read = function(path, where)
				assert(path == "cfg/mapcycle.txt" and where == "GAME", path)
				return s.cycle
			end,
			Exists = function(path, where)
				assert(where == "GAME", where)
				local map = assert(path:match("^maps/(.+)%.nav$"), path)
				return s.navs[map] == true
			end,
		},
		RunConsoleCommand = function(...) s.commands[#s.commands + 1] = table.concat({ ... }, " ") end,
		PrintMessage = function() end,
		HUD_PRINTTALK = 3,
		print = function() end,
	}, { __index = _G })
	setfenv(assert(loadfile("addons/sandcastle/gamemodes/sandcastle/gamemode/ws/sv_votes.lua")), env)()
	-- Runs the vote's timer when its time comes.
	function s.Advance(seconds)
		s.now = s.now + seconds
		for name, t in pairs(s.timers) do
			if t.at <= s.now then
				if t.repeats then t.at = s.now + t.delay else s.timers[name] = nil end
				t.fn()
			end
		end
	end
	return s
end

local function Last(ply, name)
	for i = #ply.got, 1, -1 do
		if ply.got[i].name == name then return ply.got[i].fields end
	end
end

local function CallVote(s, ply, kind, subject)
	s.listeners.game_vote_call({ kind = Index(kind), subject = subject or "" }, ply)
end

local function Cast(s, ply, yes)
	s.listeners.game_vote_cast({ yes = yes, choice = 0 }, ply)
end

-- An option of a vote of choices, by its number.
local function Pick(s, ply, choice)
	s.listeners.game_vote_cast({ yes = false, choice = choice }, ply)
end

local function Five()
	return Player("Alice"), Player("Bob"), Player("Carol"), Player("Dave"), Player("Erin")
end

T.test("a new player hears the map cycle's maps, comments and blanks left out", function()
	local alice = Player("Alice")
	local s = Load({ alice })
	s.listeners.system_client_ready({}, alice)
	local maps = Last(alice, "game_vote_maps").maps
	T.eq(table.concat(maps, ","), "cp_dustbowl,pl_badwater")
end)

T.test("a call starts the vote for everyone, the caller's yes counted", function()
	local alice, bob, carol, dave, erin = Five()
	local s = Load({ alice, bob, carol, dave, erin })
	CallVote(s, alice, Vote.KIND_MAP, "cp_dustbowl")
	local state = Last(bob, "game_vote_state")
	T.eq(state.running, true)
	T.eq(state.kind, Index(Vote.KIND_MAP))
	T.eq(state.caller, "Alice")
	T.eq(state.yes, 1)
	T.eq(state.mine, true, "bob may vote")
	T.eq(Last(alice, "game_vote_state").mine, false, "alice voted when she called it")
end)

T.test("each player hears what they cast, the others' casts kept from them", function()
	local alice, bob, carol, dave, erin = Five()
	local s = Load({ alice, bob, carol, dave, erin })
	CallVote(s, alice, Vote.KIND_MAP, "cp_dustbowl")
	Cast(s, bob, false)
	T.eq(Last(alice, "game_vote_state").cast, Vote.BALLOT_YES, "the caller's yes")
	T.eq(Last(bob, "game_vote_state").cast, Vote.BALLOT_NO, "bob's no")
	T.eq(Last(carol, "game_vote_state").cast, Vote.BALLOT_NONE, "carol has not voted")
end)

T.test("no vote running: nothing cast", function()
	local alice = Player("Alice")
	local s = Load({ alice })
	s.listeners.system_client_ready({}, alice)
	T.eq(Last(alice, "game_vote_state").cast, Vote.BALLOT_NONE)
end)

T.test("a map not in the cycle is refused", function()
	local alice = Player("Alice")
	local s = Load({ alice })
	CallVote(s, alice, Vote.KIND_MAP, "gm_flatgrass")
	T.eq(Last(alice, "game_vote_state"), nil)
	T.eq(Last(alice, "game_vote_refused") ~= nil, true)
end)

T.test("a kind the server disabled is refused with the server's reason", function()
	local alice = Player("Alice")
	local s = Load({ alice }, { disabled = { [Vote.KIND_SUPPORT] = true } })
	CallVote(s, alice, Vote.KIND_SUPPORT)
	T.eq(Last(alice, "game_vote_refused").text, "Server has disabled that issue.")
end)

T.test("a vote that passes when its time is up runs its effect: the next map", function()
	local alice, bob, carol, dave, erin = Five()
	local s = Load({ alice, bob, carol, dave, erin })
	CallVote(s, alice, Vote.KIND_MAP, "pl_badwater")
	Cast(s, bob, true)
	Cast(s, carol, true)
	s.Advance(20)
	T.eq(Last(dave, "game_vote_ended").passed, true)
	T.eq(s.commands[1], "nextlevel pl_badwater")
	T.eq(Last(dave, "game_vote_state").running, false, "the card goes away")
end)

T.test("everyone voting ends it at once; restart and scramble run through the rounds", function()
	local alice, bob = Player("Alice"), Player("Bob")
	local s = Load({ alice, bob })
	CallVote(s, alice, Vote.KIND_RESET)
	Cast(s, bob, true)
	T.eq(s.restarts, 1)
	s.Advance(1)
	CallVote(s, bob, Vote.KIND_SCRAMBLE)
	Cast(s, alice, true)
	T.eq(s.scrambles, 1)
end)

T.test("a failed vote says why and changes nothing", function()
	local alice, bob, carol, dave, erin = Five()
	local s = Load({ alice, bob, carol, dave, erin })
	CallVote(s, alice, Vote.KIND_MAP, "pl_badwater")
	s.Advance(20)
	local ended = Last(bob, "game_vote_ended")
	T.eq(ended.passed, false)
	T.eq(ended.text, Vote.FAILED_QUORUM)
	T.eq(#s.commands, 0)
end)

T.test("reports start a kick vote that kicks when it passes", function()
	local alice, bob, carol, dave, erin = Five()
	local s = Load({ alice, bob, carol, dave, erin })
	s.hooks.WSReportsReached(bob, "cheating")
	T.eq(Last(alice, "game_vote_state").kind, Index(Vote.KIND_KICK))
	T.eq(Last(bob, "game_vote_state").mine, false, "the target does not vote")
	Cast(s, alice, true)
	Cast(s, carol, true)
	Cast(s, dave, true)
	Cast(s, erin, true)
	T.eq(s.kicked[1].ply, bob)
end)

T.test("a kick reports start during another vote runs once it ends", function()
	local alice, bob, carol, dave, erin = Five()
	local s = Load({ alice, bob, carol, dave, erin })
	CallVote(s, alice, Vote.KIND_MAP, "pl_badwater")
	s.hooks.WSReportsReached(bob, "idle")
	T.eq(Last(carol, "game_vote_state").kind, Index(Vote.KIND_MAP))
	s.Advance(20)
	T.eq(Last(carol, "game_vote_state").kind, Index(Vote.KIND_KICK), "the kick follows")
end)

T.test("an admin reported enough is not put to a vote", function()
	local alice, admin = Player("Alice"), Player("Admin", { [Permissions.PLAYERS] = true })
	local s = Load({ alice, admin })
	s.hooks.WSReportsReached(admin, "idle")
	T.eq(Last(alice, "game_vote_state"), nil)
end)

T.test("a kick's target leaving ends the vote", function()
	local alice, bob, carol = Player("Alice"), Player("Bob"), Player("Carol")
	local s = Load({ alice, bob, carol })
	s.hooks.WSReportsReached(bob, "idle")
	s.hooks.PlayerDisconnected(bob)
	T.eq(Last(alice, "game_vote_state").running, false)
	T.eq(#s.kicked, 0, "nobody left to kick")
end)

T.test("a cast with no vote running is refused, not an error", function()
	local alice = Player("Alice")
	local s = Load({ alice })
	Cast(s, alice, true)
	T.eq(Last(alice, "game_vote_refused").text, "No vote is running.")
end)

-- The next-map vote (mp_vote_nextmap_enabled): once the match is one round
-- from its end or over, the server calls a vote of three maps from the
-- maplist, two of this map's mode and one of another's; the most picked
-- becomes nextlevel.
local function NextMapVote(ply)
	local state = Last(ply, "game_vote_state")
	return state and state.running and state.kind == Index(Vote.KIND_NEXTMAP) and state or nil
end

T.test("nothing is called while the match has rounds to go", function()
	local alice = Player("Alice")
	local s = Load({ alice })
	s.Advance(5)
	T.eq(NextMapVote(alice), nil, "no vote")
end)

T.test("one round from the match's end, the vote offers two maps of this mode and one of another", function()
	local alice, bob = Player("Alice"), Player("Bob")
	local s = Load({ alice, bob })
	s.match.maxrounds, s.match.roundsPlayed = 3, 2
	s.Advance(1)
	local state = NextMapVote(alice)
	T.eq(state ~= nil, true, "called")
	T.eq(#state.options, 3, "three maps")
	local payload = 0
	for _, map in ipairs(state.options) do
		T.eq(map ~= s.map, true, "not this map")
		if map:sub(1, 3) == "pl_" then payload = payload + 1 end
	end
	T.eq(payload, 2, "two of this map's mode")
	T.eq(state.mine, true, "everyone may pick")
end)

T.test("the match over calls it too, and only once a map", function()
	local alice = Player("Alice")
	local s = Load({ alice })
	s.match.over = true
	s.Advance(1)
	T.eq(NextMapVote(alice) ~= nil, true, "called")
	s.Advance(25)
	T.eq(NextMapVote(alice), nil, "over, and not called again")
end)

T.test("no vote when it is off, or the next map is already set", function()
	local alice = Player("Alice")
	local off = Load({ alice }, { nextmapEnabled = false })
	off.match.over = true
	off.Advance(1)
	T.eq(NextMapVote(alice), nil, "switched off")
	local bob = Player("Bob")
	local set = Load({ bob }, { nextlevel = "cp_dustbowl" })
	set.match.over = true
	set.Advance(1)
	T.eq(NextMapVote(bob), nil, "a map vote already chose")
end)

T.test("the most picked map becomes the next level", function()
	local alice, bob, carol = Player("Alice"), Player("Bob"), Player("Carol")
	local s = Load({ alice, bob, carol })
	s.match.over = true
	s.Advance(1)
	local options = NextMapVote(alice).options
	Pick(s, alice, 3)
	T.eq(table.concat(NextMapVote(bob).counts, " "), "0 0 1", "the picks so far")
	Pick(s, bob, 3)
	s.Advance(20)
	T.eq(Last(carol, "game_vote_ended").passed, true, "passed")
	T.eq(s.commands[#s.commands], "nextlevel " .. options[3], "the next level")
	T.eq(s.W.VotedNextLevel, options[3], "known at once")
end)

T.test("nobody picking, or nobody on the server, draws one of the maps", function()
	local alice = Player("Alice")
	local s = Load({ alice })
	s.match.over = true
	s.Advance(1)
	local options = NextMapVote(alice).options
	s.Advance(25)
	T.eq(Last(alice, "game_vote_ended").passed, true, "a map all the same")
	T.eq(s.W.VotedNextLevel, options[1], "the one drawn")
	local empty = Load({})
	empty.match.over = true
	empty.Advance(1)
	empty.Advance(25)
	T.eq(empty.W.VotedNextLevel ~= nil and empty.W.VotedNextLevel ~= empty.map, true, "an empty server moves on")
end)

-- An empty server at the match's end goes to a map without a nav mesh, so
-- it builds one while idle (ws/sv_nav.lua), unless players picked or an
-- admin set the next map.
local NO_NAV = { cp_steel = true, koth_viaduct = true, pl_badwater = true, pl_upward = true } -- pl_goldrush has none

T.test("an empty server at the match's end goes to a map without a nav mesh", function()
	local s = Load({}, { navs = NO_NAV })
	s.match.over = true
	s.Advance(1)
	s.hooks.WSChangeLevel()
	T.eq(s.W.VotedNextLevel, "pl_goldrush", "the map with none")
	T.eq(s.commands[#s.commands], "nextlevel pl_goldrush", "set as nextlevel")
end)

T.test("players who drew a map by not voting, then left, still send an empty server to a map without one", function()
	local alice = Player("Alice")
	local players = { alice }
	local s = Load(players, { navs = NO_NAV })
	s.match.maxrounds, s.match.roundsPlayed = 3, 2
	s.Advance(1)
	s.Advance(25)
	T.eq(s.W.VotedNextLevel ~= nil, true, "drawn while they were on")
	table.remove(players)
	s.hooks.WSChangeLevel()
	T.eq(s.W.VotedNextLevel, "pl_goldrush", "the map with none once empty")
end)

T.test("a map players picked, or an admin's nextlevel, stands on an empty server", function()
	local alice = Player("Alice")
	local players = { alice }
	local s = Load(players, { navs = NO_NAV })
	s.match.over = true
	s.Advance(1)
	local options = NextMapVote(alice).options
	Pick(s, alice, 2)
	table.remove(players)
	s.hooks.WSChangeLevel()
	T.eq(s.W.VotedNextLevel, options[2], "their pick")
	local set = Load({}, { navs = NO_NAV, nextlevel = "cp_steel" })
	set.match.over = true
	set.Advance(1)
	set.hooks.WSChangeLevel()
	T.eq(set.W.VotedNextLevel, nil, "the admin's nextlevel left alone")
end)

T.test("with players on, or every map meshed, the drawn map stands", function()
	local alice = Player("Alice")
	local s = Load({ alice }, { navs = NO_NAV })
	s.match.over = true
	s.Advance(1)
	local options = NextMapVote(alice).options
	s.hooks.WSChangeLevel()
	T.eq(s.W.VotedNextLevel, options[1], "players on: the draw")
	local meshed = Load({})
	meshed.match.over = true
	meshed.Advance(1)
	meshed.hooks.WSChangeLevel()
	T.eq(meshed.W.VotedNextLevel ~= nil and meshed.W.VotedNextLevel ~= meshed.map, true, "every map meshed: the draw")
end)

T.test("a vote still running when the level changes is counted first", function()
	local alice, bob = Player("Alice"), Player("Bob")
	local s = Load({ alice, bob })
	s.match.over = true
	s.Advance(1)
	local options = NextMapVote(alice).options
	Pick(s, alice, 2)
	s.hooks.WSChangeLevel()
	T.eq(s.W.VotedNextLevel, options[2], "known before the change")
	T.eq(Last(bob, "game_vote_state").running, false, "over")
end)

T.test("a yes-or-no cast on a vote of choices is refused", function()
	local alice = Player("Alice")
	local s = Load({ alice })
	s.match.over = true
	s.Advance(1)
	Cast(s, alice, true)
	T.eq(Last(alice, "game_vote_refused").text, "That is not one of the choices.")
end)

T.test("a pick on a vote of choices is heard as its option", function()
	local alice, bob = Player("Alice"), Player("Bob")
	local s = Load({ alice, bob })
	s.match.over = true
	s.Advance(1)
	T.eq(NextMapVote(alice).cast, Vote.BALLOT_NONE, "nothing picked yet")
	Pick(s, alice, 2)
	T.eq(NextMapVote(alice).cast, 2, "her pick")
	T.eq(NextMapVote(bob).cast, Vote.BALLOT_NONE, "bob's own")
end)

-- Help Other Team and Soldier Difficulty -----------------------------------------------

T.test("a passed support vote helps the caller's other team, and only the caller's team votes", function()
	local alice, bob = Player("Alice", nil, RED), Player("Bob", nil, RED)
	local carol = Player("Carol", nil, BLUE)
	local s = Load({ alice, bob, carol })
	CallVote(s, alice, Vote.KIND_SUPPORT)
	T.eq(Last(alice, "game_vote_state").question, Vote.KIND_SUPPORT .. "?BLU", "about BLU")
	T.eq(Last(carol, "game_vote_state").mine, false, "BLU does not vote")
	Cast(s, bob, true)
	T.eq(table.concat(s.handicaps, ","), tostring(BLUE), "BLU helped")
end)

T.test("a passed difficulty vote sets the soldiers' level", function()
	local alice, bob = Player("Alice"), Player("Bob")
	local s = Load({ alice, bob })
	CallVote(s, alice, Vote.KIND_DIFFICULTY, "expert")
	Cast(s, bob, true)
	T.eq(s.convars.tf_bot_difficulty, Vote.DifficultyLevel("expert"), "expert")
end)

T.test("a difficulty vote for no level is refused to its caller", function()
	local alice = Player("Alice")
	local s = Load({ alice })
	CallVote(s, alice, Vote.KIND_DIFFICULTY, "impossible")
	T.eq(Last(alice, "game_vote_refused") ~= nil, true, "refused")
	T.eq(s.convars.tf_bot_difficulty, 1, "unchanged")
end)

T.finish()
