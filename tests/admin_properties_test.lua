-- ws/sh_admin_properties.lua: admins' C-click options on players. Each
-- shows only on what its filter accepts, to holders of its privilege, and
-- the server checks both again before running it. Run against fake
-- properties, events and players.
local T = dofile("tests/harness.lua")
local Permissions = T.require("foundation.permissions")

local function Player(name, held)
	local p = {
		name = name,
		held = held or {},
		alive = true,
		said = {},
	}
	function p:Nick() return self.name end
	function p:IsPlayer() return true end
	function p:Alive() return self.alive end
	function p:ChatPrint(text) self.said[#self.said + 1] = text end
	function p:Kill() self.alive = false end
	return p
end

local function Load()
	local s = {
		added = {},
		listeners = {},
		actions = {},
	}
	local env = setmetatable({
		SERVER = true,
		WS = {
			require = T.require,
			Can = function(ply, name) return ply.held[name] == true end,
			Events = {
				Define = function() end,
				String = function() end,
				Entity = function() end,
				Int = function() end,
				Listen = function(name, _, fn) s.listeners[name] = fn end,
				Request = function() end,
			},
			AdminPlayerAction = function(ply, target, action, value)
				s.actions[#s.actions + 1] = { ply = ply, target = target, action = action, value = value }
			end,
			ADMIN_KICK = 0,
			ADMIN_BAN = 1,
			ADMIN_GRANT = 2,
		},
		properties = { Add = function(name, def) s.added[name] = def end },
		IsValid = function(v) return v ~= nil end,
		isfunction = function(v) return type(v) == "function" end,
		print = function() end,
	}, { __index = _G })
	setfenv(assert(loadfile("addons/sandcastle/gamemodes/sandcastle/gamemode/ws/sh_admin_properties.lua")), env)()
	function s.Use(name, ply, target, value)
		s.listeners.admin_property({ name = name, target = target, value = value or 0 }, ply)
	end
	return s
end

T.test("an admin's options show on another player, never on themself", function()
	local s = Load()
	local admin, bob = Player("Admin", { [Permissions.PLAYERS] = true }), Player("Bob")
	for _, name in ipairs({ "ws_admin_slay", "ws_admin_kick", "ws_admin_ban", "ws_admin_bring" }) do
		T.eq(s.added[name]:Filter(bob, admin), true, name)
		T.eq(s.added[name]:Filter(admin, admin), false, name .. " on themself")
	end
end)

T.test("a player without the players privilege sees none of them", function()
	local s = Load()
	local alice, bob = Player("Alice"), Player("Bob")
	for name, def in pairs(s.added) do T.eq(def:Filter(bob, alice), false, name) end
end)

T.test("the server runs an option only for a holder, on what its filter accepts", function()
	local s = Load()
	local alice, admin, bob = Player("Alice"), Player("Admin", { [Permissions.PLAYERS] = true }), Player("Bob")
	s.Use("ws_admin_slay", alice, bob)
	T.eq(bob.alive, true, "refused to a player")
	s.Use("ws_admin_slay", admin, bob)
	T.eq(bob.alive, false, "an admin slays")
	s.Use("ws_admin_slay", admin, bob)
	T.eq(#admin.said, 1, "the dead are not slain again")
end)

T.test("kick, ban and give go through the scoreboard menu's checked action", function()
	local s = Load()
	local admin, bob = Player("Admin", { [Permissions.PLAYERS] = true }), Player("Bob")
	s.Use("ws_admin_kick", admin, bob)
	s.Use("ws_admin_ban", admin, bob, 2)
	s.Use("ws_admin_give", admin, bob, 100)
	T.eq(#s.actions, 3)
	T.eq(s.actions[1].action, 0)
	T.eq(s.actions[2].action, 1)
	T.eq(s.actions[2].value, 2)
	T.eq(s.actions[3].action, 2)
	T.eq(s.actions[3].value, 100)
end)

T.test("an unknown option is ignored", function()
	local s = Load()
	local admin = Player("Admin", { [Permissions.PLAYERS] = true })
	s.Use("ws_admin_nonsense", admin, Player("Bob"))
	T.eq(#admin.said, 0)
end)

T.finish()
