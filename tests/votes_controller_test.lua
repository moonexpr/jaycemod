-- ws/sv_votes.lua: runs foundation.vote on the server. A player's call
-- starts a vote and its timer; casts and the timer end it; a passed vote
-- runs its effect; reports reaching the count (WSReportsReached) start a
-- kick vote, or queue it behind the running one. Run against fake events,
-- players, timers, convars and the rounds feature.
local T = dofile("tests/harness.lua")
local Vote = T.require("foundation.vote")
local Permissions = T.require("foundation.permissions")
local PlayMode = T.require("foundation.play_mode")

local KINDS = {
	Vote.KIND_KICK,
	Vote.KIND_MAP,
	Vote.KIND_RESET,
	Vote.KIND_SCRAMBLE,
	Vote.KIND_SUPPORT,
	Vote.KIND_DIFFICULTY,
}

local function Index(kind)
	for i, k in ipairs(KINDS) do
		if k == kind then return i - 1 end
	end
end

local function Player(name, held)
	local p = {
		name = name,
		held = held or {},
		got = {},
	}
	function p:Nick() return self.name end
	function p:IsPlayer() return true end
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
	}
	local convars = {
		mp_vote_duration = 20,
		mp_vote_cooldown = 120,
		mapcyclefile = "mapcycle.txt",
	}
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
		VoteEnabled = function(kind) return kind == Vote.KIND_MAP or kind == Vote.KIND_RESET or kind == Vote.KIND_SCRAMBLE end,
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
			}
		end,
	}
	for _, p in ipairs(players) do
		function p:Kick(reason) s.kicked[#s.kicked + 1] = { ply = self, reason = reason } end
	end
	local env = setmetatable({
		WS = W,
		CurTime = function() return s.now end,
		IsValid = function(v) return v ~= nil end,
		player = { GetHumans = function() return players end },
		hook = { Add = function(name, _, fn) s.hooks[name] = fn end },
		timer = {
			Create = function(name, delay, _, fn) s.timers[name] = { at = s.now + delay, fn = fn } end,
			Remove = function(name) s.timers[name] = nil end,
		},
		GetConVar = function(name)
			return {
				GetInt = function() return convars[name] end,
				GetFloat = function() return convars[name] end,
				GetString = function() return convars[name] end,
			}
		end,
		file = { Read = function(path, where)
			assert(path == "cfg/mapcycle.txt" and where == "GAME", path)
			return s.cycle
		end },
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
				s.timers[name] = nil
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
	s.listeners.vote_call({ kind = Index(kind), subject = subject or "" }, ply)
end

local function Cast(s, ply, yes)
	s.listeners.vote_cast({ yes = yes }, ply)
end

local function Five()
	return Player("Alice"), Player("Bob"), Player("Carol"), Player("Dave"), Player("Erin")
end

T.test("a new player hears the map cycle's maps, comments and blanks left out", function()
	local alice = Player("Alice")
	local s = Load({ alice })
	s.listeners.client_ready({}, alice)
	local maps = Last(alice, "vote_maps").maps
	T.eq(table.concat(maps, ","), "cp_dustbowl,pl_badwater")
end)

T.test("a call starts the vote for everyone, the caller's yes counted", function()
	local alice, bob, carol, dave, erin = Five()
	local s = Load({ alice, bob, carol, dave, erin })
	CallVote(s, alice, Vote.KIND_MAP, "cp_dustbowl")
	local state = Last(bob, "vote_state")
	T.eq(state.running, true)
	T.eq(state.kind, Index(Vote.KIND_MAP))
	T.eq(state.caller, "Alice")
	T.eq(state.yes, 1)
	T.eq(state.mine, true, "bob may vote")
	T.eq(Last(alice, "vote_state").mine, false, "alice voted when she called it")
end)

T.test("a map not in the cycle is refused", function()
	local alice = Player("Alice")
	local s = Load({ alice })
	CallVote(s, alice, Vote.KIND_MAP, "gm_flatgrass")
	T.eq(Last(alice, "vote_state"), nil)
	T.eq(Last(alice, "vote_refused") ~= nil, true)
end)

T.test("a kind not offered is refused with the server's reason", function()
	local alice = Player("Alice")
	local s = Load({ alice })
	CallVote(s, alice, Vote.KIND_SUPPORT)
	T.eq(Last(alice, "vote_refused").text, "Server has disabled that issue.")
end)

T.test("a vote that passes when its time is up runs its effect: the next map", function()
	local alice, bob, carol, dave, erin = Five()
	local s = Load({ alice, bob, carol, dave, erin })
	CallVote(s, alice, Vote.KIND_MAP, "pl_badwater")
	Cast(s, bob, true)
	Cast(s, carol, true)
	s.Advance(20)
	T.eq(Last(dave, "vote_ended").passed, true)
	T.eq(s.commands[1], "nextlevel pl_badwater")
	T.eq(Last(dave, "vote_state").running, false, "the card goes away")
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
	local ended = Last(bob, "vote_ended")
	T.eq(ended.passed, false)
	T.eq(ended.text, Vote.FAILED_QUORUM)
	T.eq(#s.commands, 0)
end)

T.test("reports start a kick vote that kicks when it passes", function()
	local alice, bob, carol, dave, erin = Five()
	local s = Load({ alice, bob, carol, dave, erin })
	s.hooks.WSReportsReached(bob, "cheating")
	T.eq(Last(alice, "vote_state").kind, Index(Vote.KIND_KICK))
	T.eq(Last(bob, "vote_state").mine, false, "the target does not vote")
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
	T.eq(Last(carol, "vote_state").kind, Index(Vote.KIND_MAP))
	s.Advance(20)
	T.eq(Last(carol, "vote_state").kind, Index(Vote.KIND_KICK), "the kick follows")
end)

T.test("an admin reported enough is not put to a vote", function()
	local alice, admin = Player("Alice"), Player("Admin", { [Permissions.PLAYERS] = true })
	local s = Load({ alice, admin })
	s.hooks.WSReportsReached(admin, "idle")
	T.eq(Last(alice, "vote_state"), nil)
end)

T.test("a kick's target leaving ends the vote", function()
	local alice, bob, carol = Player("Alice"), Player("Bob"), Player("Carol")
	local s = Load({ alice, bob, carol })
	s.hooks.WSReportsReached(bob, "idle")
	s.hooks.PlayerDisconnected(bob)
	T.eq(Last(alice, "vote_state").running, false)
	T.eq(#s.kicked, 0, "nobody left to kick")
end)

T.test("a cast with no vote running is refused, not an error", function()
	local alice = Player("Alice")
	local s = Load({ alice })
	Cast(s, alice, true)
	T.eq(Last(alice, "vote_refused").text, "No vote is running.")
end)

T.finish()
