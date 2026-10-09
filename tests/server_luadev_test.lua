-- The dedicated server's luadev access (.devtools/bin/server_root/): on a
-- LAN server, where Steam authenticates nobody, luadev's policy without its
-- authentication gate; and the ULX variants of luadev's aowl commands. Both
-- run here against fakes of luadev, ULX and the GMod globals they call.
local T = dofile("tests/harness.lua")

local DIR = ".devtools/bin/server_root/"

local function player(t)
	t = t or {}
	return {
		IsFullyAuthenticated = function() return t.authenticated or false end,
		IsSuperAdmin = function() return t.superadmin or false end,
		IsAdmin = function() return t.admin or t.superadmin or false end,
	}
end

local function convar(on) return { GetBool = function() return on end } end

-- loads luadev_lan.lua over a fake luadev whose own check refuses with "luadev's own"
local function lan(t)
	local luadev = { TO_CLIENT = 2, CanLuaDev = function() return false, "luadev's own" end }
	local hooks = t.hooks or {}
	local env = setmetatable({
		luadev = luadev,
		GetConVar = function(name) return convar(({ sv_lan = t.lan, sv_allowcslua = t.cslua })[name]) end,
		hook = { Run = function(name, ...) if hooks[name] then return hooks[name](...) end end },
		istable = function(v) return type(v) == "table" end,
		table = { Count = function(tb) local n = 0 for _ in pairs(tb) do n = n + 1 end return n end },
	}, { __index = _G })
	setfenv(assert(loadfile(DIR .. "luadev_lan.lua")), env)()
	return luadev
end

T.test("off a LAN server luadev's own check decides", function()
	local luadev = lan({ lan = false })
	T.eq(select(2, luadev.CanLuaDev(player({ superadmin = true }), "x")), "luadev's own")
end)

T.test("on a LAN server an unauthenticated superadmin may run lua", function()
	local luadev = lan({ lan = true })
	T.eq(luadev.CanLuaDev(player({ superadmin = true }), "x"), true)
end)

T.test("on a LAN server anyone else is refused", function()
	local luadev = lan({ lan = true })
	T.eq(luadev.CanLuaDev(player(), "x", nil, nil, nil, nil) and true or false, false)
end)

T.test("on a LAN server the CanLuaDev hooks still decide first", function()
	local luadev = lan({ lan = true, hooks = { CanLuaDev = function() return false, "hooked" end } })
	local ok, why = luadev.CanLuaDev(player({ superadmin = true }), "x")
	T.eq(ok, false)
	T.eq(why, "hooked")
	local allowed = lan({ lan = true, hooks = { LuaDevIsPlayerAllowed = function() return true end } })
	T.eq(allowed.CanLuaDev(player(), "x"), true)
end)

T.test("on a LAN server with sv_allowcslua anyone may run lua on their own client", function()
	local luadev = lan({ lan = true, cslua = true })
	local me = player()
	T.eq(luadev.CanLuaDev(me, "x", nil, 2, me), true)
	T.eq(luadev.CanLuaDev(me, "x", nil, 2, { me }), true)
	T.eq(luadev.CanLuaDev(me, "x", nil, 2, player()) and true or false, false, "someone else's client")
end)

-- loads ulx_luadev.lua over fakes of ULX, ULib and luadev that record what they are asked
local function ulx_module(t)
	t = t or {}
	local commands, ran, errors = {}, {}, {}
	local function command(_, name, fn, say)
		local c = { name = name, fn = fn, say = say, params = {} }
		function c.addParam(self, p) self.params[#self.params + 1] = p end
		function c.defaultAccess(self, access) self.access = access end
		function c.help(self, text) self.text = text end
		commands[name] = c
		return c
	end
	local function runner(where)
		return function(script, a, b, c)
			ran[#ran + 1] = { where = where, script = script, args = { a, b, c } }
			return t.fail == nil, t.fail
		end
	end
	local hooks = {}
	local env = setmetatable({
		hook = { Add = function(name, _, fn, priority) hooks[name] = { fn = fn, priority = priority } end },
		HOOK_MONITOR_HIGH = -2,
		ulx = { command = command },
		ULib = {
			ACCESS_ALL = "user", ACCESS_SUPERADMIN = "superadmin",
			cmds = { StringArg = "string", PlayerArg = "player", takeRestOfLine = "rest", optional = "optional" },
			tsayError = function(ply, msg) errors[#errors + 1] = msg end,
		},
		luadev = {
			RunOnServer = runner("server"), RunOnShared = runner("shared"),
			RunOnClients = runner("clients"), RunOnClient = runner("client"),
			ValidScript = function(script)
				if script:find("%(%(") then return nil, "bad script" end
				return true
			end,
			GetPlayerIdentifier = function(_, info) return info end,
		},
		GetConVar = function() return convar(t.cslua) end,
	}, { __index = _G })
	setfenv(assert(loadfile(DIR .. "ulx_luadev.lua")), env)()
	return commands, ran, errors, hooks
end

local AOWL = { "l", "ls", "lc", "lsc", "lm", "lb", "print", "table", "keys", "keysm", "printc", "printm", "printb" }

T.test("every aowl command has a ULX variant and a say command", function()
	local commands = ulx_module()
	for _, name in ipairs(AOWL) do
		local c = commands["ulx " .. name]
		T.eq(c ~= nil, true, name)
		T.eq(c.say, "!" .. name, name)
		T.eq(c.text ~= nil, true, name .. "'s help")
	end
end)

T.test("only lm is for every player; the rest are for superadmins", function()
	local commands = ulx_module()
	for _, name in ipairs(AOWL) do
		T.eq(commands["ulx " .. name].access, name == "lm" and "user" or "superadmin", name)
	end
end)

T.test("l runs the line on the server as the caller", function()
	local commands, ran = ulx_module()
	local me = player()
	commands["ulx l"].fn(me, "print(1)")
	T.eq(#ran, 1)
	T.eq(ran[1].where, "server")
	T.eq(ran[1].script, "print(1)")
	T.eq(ran[1].args[1], "cmd:l")
	T.eq(ran[1].args[2].ply, me)
end)

T.test("lb runs on the caller's client and the server", function()
	local commands, ran = ulx_module()
	local me = player()
	commands["ulx lb"].fn(me, "x()")
	T.eq(ran[1].where, "client")
	T.eq(ran[1].args[1], me)
	T.eq(ran[2].where, "server")
end)

T.test("lsc runs on the target player's client", function()
	local commands, ran = ulx_module()
	local them = player()
	commands["ulx lsc"].fn(player(), them, "x()")
	T.eq(ran[1].where, "client")
	T.eq(ran[1].script, "x()")
	T.eq(ran[1].args[1], them)
end)

T.test("print, table and printc wrap the expression", function()
	local commands, ran = ulx_module()
	commands["ulx print"].fn(player(), "1 + 1")
	commands["ulx table"].fn(player(), "_G")
	commands["ulx printc"].fn(player(), "LocalPlayer()")
	T.eq(ran[1].script, "print(1 + 1)")
	T.eq(ran[2].script, "PrintTable(_G)")
	T.eq(ran[3].where, "clients")
	T.eq(ran[3].script, "easylua.PrintOnServer(LocalPlayer())")
end)

T.test("keys quotes its search, so a quote in it cannot break the script", function()
	local commands, ran = ulx_module()
	commands["ulx keys"].fn(player(), "_G", 'a"b')
	T.eq(ran[1].script:find('"a\\"b"', 1, true) ~= nil, true, ran[1].script)
	commands["ulx keys"].fn(player(), "_G")
	T.eq(ran[2].script:find('""', 1, true) ~= nil, true, "no search lists every key")
end)

T.test("a script that does not compile is refused and runs nowhere", function()
	local commands, ran, errors = ulx_module()
	commands["ulx l"].fn(player(), "((")
	T.eq(#ran, 0)
	T.eq(errors[1], "bad script")
end)

T.test("luadev's failure is told to the caller", function()
	local commands, _, errors = ulx_module({ fail = "no targets" })
	commands["ulx lc"].fn(player(), "x()")
	T.eq(errors[1], "no targets")
end)

T.test("lm needs sv_allowcslua unless the caller is an admin", function()
	local commands, ran, errors = ulx_module({ cslua = false })
	commands["ulx lm"].fn(player(), "x()")
	T.eq(#ran, 0)
	T.eq(errors[1], "sv_allowcslua is 0")
	commands["ulx lm"].fn(player({ admin = true }), "x()")
	T.eq(#ran, 1)
	local open, ran_open = ulx_module({ cslua = true })
	open["ulx lm"].fn(player(), "x()")
	T.eq(#ran_open, 1)
end)

-- ULib splits a chat command's arguments and drops their quotes, so the
-- line typed is taken as typed: print"test" stays print"test".
T.test("a command typed in chat runs the lua as it was typed, quotes and all", function()
	local commands, ran, _, hooks = ulx_module()
	local me = player()
	T.eq(hooks.PlayerSay.priority, -2, "a monitor, before ULib's own say commands")
	hooks.PlayerSay.fn(me, '!l print"test"')
	commands["ulx l"].fn(me, "print test")
	T.eq(ran[1].script, 'print"test"')
end)

T.test("typed in chat, lsc's lua is what follows its target, as typed", function()
	local commands, ran, _, hooks = ulx_module()
	local me, them = player(), player()
	hooks.PlayerSay.fn(me, '!lsc moon print("a b")')
	commands["ulx lsc"].fn(me, them, "print(a b)")
	T.eq(ran[1].script, 'print("a b")')
end)

T.test("from the console, or after another chat line, the parsed line runs", function()
	local commands, ran, _, hooks = ulx_module()
	local me = player()
	commands["ulx l"].fn(me, "print(1)")
	T.eq(ran[1].script, "print(1)", "console")
	hooks.PlayerSay.fn(me, "hello there")
	commands["ulx l"].fn(me, "print(2)")
	T.eq(ran[2].script, "print(2)", "another line said")
	hooks.PlayerSay.fn(me, '!lc print"x"')
	commands["ulx l"].fn(me, "print(3)")
	T.eq(ran[3].script, "print(3)", "another command's line")
end)

T.test("a chat line is used once", function()
	local commands, ran, _, hooks = ulx_module()
	local me = player()
	hooks.PlayerSay.fn(me, '!l print"once"')
	commands["ulx l"].fn(me, "print once")
	commands["ulx l"].fn(me, "print(again)")
	T.eq(ran[2].script, "print(again)")
end)

T.finish()
