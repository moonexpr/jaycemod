-- ws/sv_players_menu.lua: the scoreboard player menu's requests. Reports go
-- to foundation.reports and, at the count, start a kick vote
-- (WSReportsReached); money moves through WS.TransferMoney; kicks, bans and
-- grants need the players privilege. Run against fake events, players and
-- economy.
local T = dofile("tests/harness.lua")
local Reports = T.require("foundation.reports")
local Economy = T.require("foundation.economy")
local Permissions = T.require("foundation.permissions")
local Refusal = T.require("foundation.core.refusal")

local function Player(name, held)
	local p = {
		name = name,
		held = held or {},
		said = {},
	}
	function p:Nick() return self.name end
	function p:IsPlayer() return true end
	return p
end

local function Load(players, configured)
	local s = {
		listeners = {},
		hooks = {},
		reached = {},
		kicked = {},
		banned = {},
		moved = {},
		granted = {},
	}
	local W = {
		require = T.require,
		Events = {
			Listen = function(name, _, fn) s.listeners[name] = fn end,
			Fire = function(name, fields, ply)
				assert(name == "players_menu_said", name)
				ply.said[#ply.said + 1] = fields
			end,
		},
		Can = function(ply, name) return ply.held[name] == true end,
		TransferMoney = function(from, to, amount)
			if amount > 100 then Refusal.Raise(Economy.INSUFFICIENT_FUNDS, "too much") end
			s.moved[#s.moved + 1] = { from = from, to = to, amount = amount }
		end,
		GrantMoney = function(ent, amount) s.granted[#s.granted + 1] = { ent = ent, amount = amount } end,
		PLAYERS_MENU_BANS = {
			{
				label = "1 Hour",
				minutes = 60,
			},
		},
		REPORT_LABELS = {
			[Reports.CHEATING] = "Player is Cheating",
			[Reports.IDLE] = "Player is Idle",
			[Reports.SCAMMING] = "Player is Scamming",
			[Reports.NONE] = "No Reason Given",
		},
		ADMIN_KICK = 0,
		ADMIN_BAN = 1,
		ADMIN_GRANT = 2,
	}
	for _, p in ipairs(players) do
		function p:Kick(reason) s.kicked[#s.kicked + 1] = { ply = self, reason = reason } end
		function p:Ban(minutes, kick) s.banned[#s.banned + 1] = { ply = self, minutes = minutes, kick = kick } end
	end
	local env = setmetatable({
		WS = W,
		IsValid = function(v) return v ~= nil end,
		hook = {
			Add = function(name, _, fn) s.hooks[name] = fn end,
			Run = function(name, ...)
				assert(name == "WSReportsReached", name)
				s.reached[#s.reached + 1] = { ... }
			end,
		},
		player = { GetCount = function() return #players end },
		GetConVar = function(name)
			assert(name == "mp_reports_kick_count", name)
			return { GetInt = function() return configured end }
		end,
		print = function() end,
	}, { __index = _G })
	setfenv(assert(loadfile("addons/sandcastle/gamemodes/sandcastle/gamemode/ws/sv_players_menu.lua")), env)()
	return s
end

local function IndexOf(reason)
	for i, r in ipairs(Reports.REASONS) do
		if r == reason then return i - 1 end
	end
end

local function Report(s, by, target, reason)
	s.listeners.player_report({ target = target, reason = IndexOf(reason) }, by)
end

local function Last(ply) return ply.said[#ply.said] end

T.test("reports below the count tell the reporter how many start a vote", function()
	local alice, bob, carol, dave, erin, frank = Player("Alice"), Player("Bob"), Player("Carol"), Player("Dave"), Player("Erin"), Player("Frank")
	local s = Load({ alice, bob, carol, dave, erin, frank }, 3)
	Report(s, alice, bob, Reports.CHEATING)
	T.eq(#s.reached, 0)
	T.eq(Last(alice).refused, false)
	T.eq(Last(alice).text:find("3 players", 1, true) ~= nil, true, Last(alice).text)
end)

T.test("the report that reaches the count starts the kick vote", function()
	local alice, bob, carol, dave, erin, frank = Player("Alice"), Player("Bob"), Player("Carol"), Player("Dave"), Player("Erin"), Player("Frank")
	local s = Load({ alice, bob, carol, dave, erin, frank }, 3)
	Report(s, alice, bob, Reports.CHEATING)
	Report(s, carol, bob, Reports.CHEATING)
	Report(s, dave, bob, Reports.IDLE)
	T.eq(#s.reached, 1)
	T.eq(s.reached[1][1], bob)
	T.eq(s.reached[1][2], Reports.CHEATING)
end)

T.test("on a server of three, the second report starts it", function()
	local alice, bob, carol = Player("Alice"), Player("Bob"), Player("Carol")
	local s = Load({ alice, bob, carol }, 3)
	Report(s, alice, bob, Reports.IDLE)
	Report(s, carol, bob, Reports.IDLE)
	T.eq(#s.reached, 1)
end)

T.test("a refused report is told to the reporter as refused", function()
	local alice, bob = Player("Alice"), Player("Bob")
	local s = Load({ alice, bob }, 3)
	Report(s, alice, bob, Reports.IDLE)
	Report(s, alice, bob, Reports.IDLE)
	T.eq(Last(alice).refused, true)
	Report(s, alice, alice, Reports.IDLE)
	T.eq(Last(alice).refused, true)
end)

T.test("a report of someone who left is refused, not an error", function()
	local alice = Player("Alice")
	local s = Load({ alice }, 3)
	s.listeners.player_report({ target = nil, reason = 0 }, alice)
	T.eq(Last(alice).refused, true)
end)

T.test("a player who leaves takes their reports with them", function()
	local alice, bob, carol, dave, erin = Player("Alice"), Player("Bob"), Player("Carol"), Player("Dave"), Player("Erin")
	local s = Load({ alice, bob, carol, dave, erin }, 2)
	Report(s, alice, bob, Reports.IDLE)
	s.hooks.PlayerDisconnected(alice)
	Report(s, carol, bob, Reports.IDLE)
	T.eq(#s.reached, 0, "alice's report left with her")
end)

T.test("giving money moves it and tells both players", function()
	local alice, bob = Player("Alice"), Player("Bob")
	local s = Load({ alice, bob }, 3)
	s.listeners.money_transfer({ target = bob, amount = 50 }, alice)
	T.eq(#s.moved, 1)
	T.eq(s.moved[1].amount, 50)
	T.eq(Last(alice).refused, false)
	T.eq(Last(bob).text, "Alice gave you $50.")
end)

T.test("giving more than you hold is refused and told", function()
	local alice, bob = Player("Alice"), Player("Bob")
	local s = Load({ alice, bob }, 3)
	s.listeners.money_transfer({ target = bob, amount = 500 }, alice)
	T.eq(#s.moved, 0)
	T.eq(Last(alice).refused, true)
	T.eq(#bob.said, 0)
end)

T.test("kicks, bans and grants need the players privilege", function()
	local alice, bob = Player("Alice"), Player("Bob")
	local s = Load({ alice, bob }, 3)
	s.listeners.admin_player({ target = bob, action = 0, value = 0 }, alice)
	s.listeners.admin_player({ target = bob, action = 1, value = 0 }, alice)
	s.listeners.admin_player({ target = bob, action = 2, value = 100 }, alice)
	T.eq(#s.kicked + #s.banned + #s.granted, 0)
	T.eq(Last(alice).refused, true)
end)

T.test("an admin kicks, bans for the length chosen, and grants money", function()
	local admin, bob = Player("Admin", { [Permissions.PLAYERS] = true }), Player("Bob")
	local s = Load({ admin, bob }, 3)
	s.listeners.admin_player({ target = bob, action = 0, value = 0 }, admin)
	T.eq(s.kicked[1].ply, bob)
	s.listeners.admin_player({ target = bob, action = 1, value = 0 }, admin)
	T.eq(s.banned[1].minutes, 60)
	T.eq(s.banned[1].kick, true)
	s.listeners.admin_player({ target = bob, action = 2, value = 100 }, admin)
	T.eq(s.granted[1].amount, 100)
end)

T.test("a ban length the menu does not offer is refused", function()
	local admin, bob = Player("Admin", { [Permissions.PLAYERS] = true }), Player("Bob")
	local s = Load({ admin, bob }, 3)
	s.listeners.admin_player({ target = bob, action = 1, value = 9 }, admin)
	T.eq(#s.banned, 0)
	T.eq(Last(admin).refused, true)
end)

T.test("an admin cannot kick or ban themself", function()
	local admin = Player("Admin", { [Permissions.PLAYERS] = true })
	local s = Load({ admin }, 3)
	s.listeners.admin_player({ target = admin, action = 0, value = 0 }, admin)
	T.eq(#s.kicked, 0)
	T.eq(Last(admin).refused, true)
end)

T.finish()
