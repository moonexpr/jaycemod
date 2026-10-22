-- ws/sv_match_control.lua: the commands behind Utilities > Admin > Match
-- Control, each refused to a player without its privilege, and the round
-- reward paid to the round's winners. Run against fake commands, rounds,
-- editors and players.
local T = dofile("tests/harness.lua")
local Permissions = T.require("games.system.permissions")

local RED, BLUE, UNASSIGNED, SPECTATOR = 2, 3, 0, 1

local function Player(name, held, t)
	local p = {
		name = name,
		held = held or {},
		team = t or RED,
		said = {},
	}
	function p:Nick() return self.name end
	function p:ChatPrint(text) self.said[#self.said + 1] = text end
	return p
end

local function Load(players, opts)
	opts = opts or {}
	local s = {
		commands = {},
		hooks = {},
		granted = {},
		ran = {},
		serverRewards = {},
	}
	local rounds = {
		SuddenDeathNow = function(_, forMatch) s.ran[#s.ran + 1] = "sudden " .. tostring(forMatch) return true end,
		RestartRound = function() s.ran[#s.ran + 1] = "restart" end,
		ForceMatchWin = function(_, t) s.ran[#s.ran + 1] = "match " .. t return true end,
	}
	local env = setmetatable({
		WS = {
			require = T.require,
			Can = function(ply, name) return ply == nil or ply.held[name] == true end,
			Active = function() return opts.active ~= false end,
			Feature = function(name)
				if name == "rounds" then return rounds end
				error("feature " .. name)
			end,
			GrantMoney = function(ply, amount) s.granted[#s.granted + 1] = { ply = ply, amount = amount } end,
			TeamOf = function(ply) return ply.team end,
			TEAM_RED = RED,
			TEAM_BLUE = BLUE,
			TEAM_UNASSIGNED = UNASSIGNED,
			TEAM_SPECTATOR = SPECTATOR,
		},
		CreateConVar = function() return { GetInt = function() return opts.reward or 0 end } end,
		concommand = { Add = function(name, fn) s.commands[name] = fn end },
		hook = {
			Add = function(name, _, fn) s.hooks[name] = fn end,
			Run = function(name, ...) if name == "WSRoundRewards" then s.serverRewards[#s.serverRewards + 1] = { ... } end end,
		},
		team = { GetPlayers = function(t)
			local found = {}
			for _, p in ipairs(players) do
				if p.team == t then found[#found + 1] = p end
			end
			return found
		end },
		IsValid = function(v) return v ~= nil end,
		print = function() end,
	}, { __index = _G })
	setfenv(assert(loadfile("addons/sandcastle/gamemodes/sandcastle/gamemode/ws/sv_match_control.lua")), env)()
	function s.Run(name, ply, ...) s.commands[name](ply, name, { ... }) end
	return s
end

T.test("a player without the round privilege is refused, and told", function()
	local bob = Player("Bob")
	local s = Load({ bob })
	s.Run("mp_round_suddendeath", bob)
	T.eq(#s.ran, 0)
	T.eq(bob.said[1], "mp_round_suddendeath: you may not do that")
end)

T.test("a holder sends the round to sudden death, or restarts it", function()
	local admin = Player("Admin", { [Permissions.ROUND] = true })
	local s = Load({ admin })
	s.Run("mp_round_suddendeath", admin)
	s.Run("mp_round_restart", admin)
	T.eq(table.concat(s.ran, ","), "sudden false,restart")
end)

T.test("forcing the match's winner needs the match privilege, not the round's", function()
	local roundOnly = Player("Round", { [Permissions.ROUND] = true })
	local matchAdmin = Player("Match", { [Permissions.MATCH] = true })
	local s = Load({ roundOnly, matchAdmin })
	s.Run("mp_match_forcewin", roundOnly, "red")
	T.eq(#s.ran, 0)
	s.Run("mp_match_forcewin", matchAdmin, "blue")
	s.Run("mp_match_forcewin", matchAdmin, "sudden")
	T.eq(table.concat(s.ran, ","), "match " .. BLUE .. ",sudden true")
end)

T.test("a map without rounds says so", function()
	local admin = Player("Admin", { [Permissions.ROUND] = true })
	local s = Load({ admin }, { active = false })
	s.Run("mp_round_suddendeath", admin)
	T.eq(admin.said[1], "mp_round_suddendeath: this map has no rounds")
end)

T.test("a round's winners are each paid the reward, then the server's own rewards run", function()
	local alice, bob, carol = Player("Alice", nil, RED), Player("Bob", nil, RED), Player("Carol", nil, BLUE)
	local s = Load({ alice, bob, carol }, { reward = 200 })
	s.hooks.WSRoundWin(RED)
	T.eq(#s.granted, 2)
	T.eq(s.granted[1].amount, 200)
	T.eq(s.serverRewards[1][1], RED)
end)

T.test("no reward is paid with the setting at 0, or for a round nobody won", function()
	local alice = Player("Alice", nil, RED)
	local s = Load({ alice }, { reward = 0 })
	s.hooks.WSRoundWin(RED)
	T.eq(#s.granted, 0)
	local paid = Load({ alice }, { reward = 200 })
	paid.hooks.WSRoundWin(UNASSIGNED)
	T.eq(#paid.granted, 0)
	T.eq(#paid.serverRewards, 0)
end)

T.finish()
