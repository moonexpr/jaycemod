-- The dedicated server's luadev access (.devtools/bin/server_root/): on a
-- LAN server, where Steam authenticates nobody, luadev's policy without its
-- authentication gate; and the ULX variants of luadev's aowl commands. Both
-- run here against fakes of luadev, ULX and the GMod globals they call.
local T = dofile ("tests/harness.lua")

-- GMod's AddCSLuaFile, which each of ulx_luadev's modules calls for itself as it loads (no path:
-- the file calling it): what it was asked to send, by path, or "itself".
local sentByModules = {}
AddCSLuaFile = function (path) sentByModules [#sentByModules + 1] = path or "itself" end

local DIR = ".devtools/bin/server_root/"
local ULX_LUADEV = "addons/ulx_luadev/lua/ulx/modules/sh/luadev.lua"

-- what a client's copy of ulx_luadev made its preferences, set once ulx_module is defined
local clientPreferences = {}

-- A player as the server sees one: GetInfo answers its client's preferences (t.prefs, else as its
-- copy of the module made them), as GMod's does: text, a number's default when it is not one.
local function player (t)
	t = t or {}
	local function info (name)
		local set = (t.prefs or {}) [name]
		if set ~= nil then return tostring (set) end
		return clientPreferences [name] and clientPreferences [name].default or ""
	end
	return
	{
		IsFullyAuthenticated = function () return t.authenticated or false end,
		IsSuperAdmin = function () return t.superadmin or false end,
		IsAdmin = function () return t.admin or t.superadmin or false end,
		GetInfo = function (_, name) return info (name) end,
		GetInfoNum = function (_, name, default) return tonumber (info (name)) or default end
	}
end

local function convar (on) return { GetBool = function () return on end } end

-- loads luadev_lan.lua over a fake luadev whose own check refuses with "luadev's own"
local function lan (t)
	local luadev = { TO_CLIENT = 2, CanLuaDev = function () return false, "luadev's own" end }
	local hooks = t.hooks or {}
	local env = setmetatable (
		{
			luadev = luadev,
			GetConVar = function (name) return convar (({ sv_lan = t.lan, sv_allowcslua = t.cslua }) [name]) end,
			hook = { Run = function (name, ...) if hooks [name] then return hooks [name] (...) end end },
			istable = function (v) return type (v) == "table" end,
			table = { Count = function (tb) local n = 0 for _ in pairs (tb) do n = n + 1 end return n end }
		}, { __index = _G })
	setfenv (assert (loadfile (DIR .. "luadev_lan.lua")), env) ()
	return luadev
end

T.test ("off a LAN server luadev's own check decides", function ()
	local luadev = lan ({ lan = false })
	T.eq (select (2, luadev.CanLuaDev (player ({ superadmin = true }), "x")), "luadev's own")
end)

T.test ("on a LAN server an unauthenticated superadmin may run lua", function ()
	local luadev = lan ({ lan = true })
	T.eq (luadev.CanLuaDev (player ({ superadmin = true }), "x"), true)
end)

T.test ("on a LAN server anyone else is refused", function ()
	local luadev = lan ({ lan = true })
	T.eq (luadev.CanLuaDev (player (), "x", nil, nil, nil, nil) and true or false, false)
end)

T.test ("on a LAN server the CanLuaDev hooks still decide first", function ()
	local luadev = lan ({ lan = true, hooks = { CanLuaDev = function () return false, "hooked" end } })
	local ok, why = luadev.CanLuaDev (player ({ superadmin = true }), "x")
	T.eq (ok,  false)
	T.eq (why, "hooked")
	local allowed = lan ({ lan = true, hooks = { LuaDevIsPlayerAllowed = function () return true end } })
	T.eq (allowed.CanLuaDev (player (), "x"), true)
end)

T.test ("on a LAN server with sv_allowcslua anyone may run lua on their own client", function ()
	local luadev = lan ({ lan = true, cslua = true })
	local me = player ()
	T.eq (luadev.CanLuaDev (me, "x", nil, 2, me),     true)
	T.eq (luadev.CanLuaDev (me, "x", nil, 2, { me }), true)
	T.eq (luadev.CanLuaDev (me, "x", nil, 2, player ()) and true or false, false, "someone else's client")
end)

-- loads ulx_luadev's luadev.lua over fakes of ULX, ULib and luadev that record what they are asked
local function ulx_module (t)
	t = t or {}
	local commands, ran, errors, said, cues, frames, created = {}, {}, {}, {}, {}, {}, {}
	local consoled, sent = {}, {}
	local function command (_, name, fn, say)
		local c = { name = name, fn = fn, say = say, params = {} }
		function c.addParam (self, p) self.params [#self.params + 1] = p end
		function c.defaultAccess (self, access) self.access = access end
		function c.help (self, text) self.text = text end
		commands [name] = c
		return c
	end
	local function runner (where)
		return function (script, a, b, c)
			ran [#ran + 1] = { where = where, script = script, args = { a, b, c } }
			if t.prints and MsgN then MsgN (t.prints) end
			if t.fail then return false, t.fail end
			return true, t.values or {}
		end
	end
	local hooks = {}
	local env = setmetatable (
		{
			hook = { Add = function (name, _, fn, priority) hooks [name] = { fn = fn, priority = priority } end },
			HOOK_MONITOR_HIGH = -2,
			ulx = { command = command },
			ULib =
			{
				ACCESS_ALL = "user", ACCESS_SUPERADMIN = "superadmin",
				cmds = { StringArg = "string", PlayerArg = "player", takeRestOfLine = "rest", optional = "optional" },
				tsayError = function (ply, msg) errors [#errors + 1] = msg end,
				tsay = function (ply, msg) said [#said + 1] = msg end,
				clientRPC = function (ply, fn, sound) cues [#cues + 1] = { ply = ply, fn = fn, sound = sound } end
			},
			luadev =
			{
				RunOnServer = runner ("server"), RunOnShared = runner ("shared"),
				RunOnClients = runner ("clients"), RunOnClient = runner ("client"),
				ValidScript = function (script)
					if script:find ("%(%(") then return nil, "bad script" end
					return true
				end,
				GetPlayerIdentifier = function (_, info) return info end,
				RealFilePath = function (path) if (t.files or {}) [path] then return path, "LUA" end end
			},
			GetConVar = function () return convar (t.cslua) end,
			-- the module's preferences, made on a client (t.client)
			CreateClientConVar = function (name, default, save, userinfo)
				created [name] = { default = default, save = save, userinfo = userinfo }
			end,
			SERVER = not t.client,
			CLIENT = t.client or false,
			require = T.require,
			AddCSLuaFile = function (path) sent [#sent + 1] = path end,
			concommand = { Run = function (ply, command, args, line)
				consoled [#consoled + 1] = { ply = ply, command = command, args = args, line = line }
			end },
			IsValid = function (v) return v ~= nil and v.valid ~= false end,
			timer = { Simple = function (delay, fn) frames [#frames + 1] = { delay = delay, fn = fn } end }
		}, { __index = _G })
	setfenv (assert (loadfile (ULX_LUADEV)), env) ()
	return commands, ran, errors, hooks, said, cues, frames, created, consoled, sent
end

clientPreferences = select (8, ulx_module ({ client = true }))

-- the cues' sounds in order
local function sounds (cues)
	local list = {}
	for i, cue in ipairs (cues) do list [i] = cue.sound end
	return list
end

-- runs the timers queued so far that are due within seconds (a frame: 0), keeping the rest
local function after (frames, seconds)
	local due, kept = {}, {}
	for _, t in ipairs (frames) do
		if t.delay <= seconds then due [#due + 1] = t.fn else kept [#kept + 1] = t end
	end
	for i = #frames, 1, -1 do frames [i] = nil end
	for i, t in ipairs (kept) do frames [i] = t end
	for _, fn in ipairs (due) do fn () end
end

local function frame (frames) after (frames, 0) end

-- a transaction as the gamemode's: pending until settled, telling who waits on it
local function transaction (state)
	local tx = { state = state or "pending", waiting = {} }
	function tx:State () return self.state end
	function tx:OnSettle (fn) if self.state == "pending" then self.waiting [#self.waiting + 1] = fn else fn (self) end end
	function tx:Settle (to) self.state = to for _, fn in ipairs (self.waiting) do fn (self) end end
	return tx
end

local AOWL = { "l", "ls", "lc", "lsc", "lm", "lb", "print", "table", "keys", "keysm", "printc", "printm", "printb" }

T.test ("every aowl command has a ULX variant and a say command", function ()
	local commands = ulx_module ()
	for _, name in ipairs (AOWL) do
		local c = commands ["ulx " .. name]
		T.eq (c ~= nil,      true,        name)
		T.eq (c.say,         "!" .. name, name)
		T.eq (c.text ~= nil, true,        name .. "'s help")
	end
end)

T.test ("only lm is for every player; the rest are for superadmins", function ()
	local commands = ulx_module ()
	for _, name in ipairs (AOWL) do
		T.eq (commands ["ulx " .. name].access, name == "lm" and "user" or "superadmin", name)
	end
end)

T.test ("l runs the line on the server as the caller", function ()
	local commands, ran = ulx_module ()
	local me = player ()
	commands ["ulx l"].fn (me, "print(1)")
	T.eq (#ran,                 1)
	T.eq (ran [1].where,        "server")
	T.eq (ran [1].script,       "print(1)")
	T.eq (ran [1].args [1],     "cmd:l")
	T.eq (ran [1].args [2].ply, me)
end)

T.test ("lb runs on the caller's client and the server", function ()
	local commands, ran = ulx_module ()
	local me = player ()
	commands ["ulx lb"].fn (me, "x()")
	T.eq (ran [1].where,    "client")
	T.eq (ran [1].args [1], me)
	T.eq (ran [2].where,    "server")
end)

T.test ("lsc runs on the target player's client", function ()
	local commands, ran = ulx_module ()
	local them = player ()
	commands ["ulx lsc"].fn (player (), them, "x()")
	T.eq (ran [1].where,    "client")
	T.eq (ran [1].script,   "x()")
	T.eq (ran [1].args [1], them)
end)

T.test ("print, table and printc wrap the expression", function ()
	local commands, ran = ulx_module ()
	commands ["ulx print"].fn (player (), "1 + 1")
	commands ["ulx table"].fn (player (), "_G")
	commands ["ulx printc"].fn (player (), "LocalPlayer()")
	T.eq (ran [1].script, "print(1 + 1)")
	T.eq (ran [2].script, "PrintTable(_G)")
	T.eq (ran [3].where,  "clients")
	T.eq (ran [3].script, "easylua.PrintOnServer(LocalPlayer())")
end)

T.test ("keys quotes its search, so a quote in it cannot break the script", function ()
	local commands, ran = ulx_module ()
	commands ["ulx keys"].fn (player (), "_G", 'a"b')
	T.eq (ran [1].script:find ('"a\\"b"', 1, true) ~= nil, true, ran [1].script)
	commands ["ulx keys"].fn (player (), "_G")
	T.eq (ran [2].script:find ('""', 1, true) ~= nil, true, "no search lists every key")
end)

T.test ("a script that does not compile is refused and runs nowhere", function ()
	local commands, ran, errors = ulx_module ()
	commands ["ulx l"].fn (player (), "((")
	T.eq (#ran,       0)
	T.eq (errors [1], "bad script")
end)

T.test ("luadev's failure is told to the caller", function ()
	local commands, _, errors = ulx_module ({ fail = "no targets" })
	commands ["ulx lc"].fn (player (), "x()")
	T.eq (errors [1], "no targets")
end)

T.test ("lm needs sv_allowcslua unless the caller is an admin", function ()
	local commands, ran, errors = ulx_module ({ cslua = false })
	commands ["ulx lm"].fn (player (), "x()")
	T.eq (#ran,       0)
	T.eq (errors [1], "sv_allowcslua is 0")
	commands ["ulx lm"].fn (player ({ admin = true }), "x()")
	T.eq (#ran, 1)
	local open, ran_open = ulx_module ({ cslua = true })
	open ["ulx lm"].fn (player (), "x()")
	T.eq (#ran_open, 1)
end)

-- ULib splits a chat command's arguments and drops their quotes, so the
-- line typed is taken as typed: print"test" stays print"test".
T.test ("a command typed in chat runs the lua as it was typed, quotes and all", function ()
	local commands, ran, _, hooks = ulx_module ()
	local me = player ()
	T.eq (hooks.PlayerSay.priority, -2, "a monitor, before ULib's own say commands")
	hooks.PlayerSay.fn (me, '!l print"test"')
	commands ["ulx l"].fn (me, "print test")
	T.eq (ran [1].script, 'print"test"')
end)

T.test ("typed in chat, lsc's lua is what follows its target, as typed", function ()
	local commands, ran, _, hooks = ulx_module ()
	local me, them = player (), player ()
	hooks.PlayerSay.fn (me, '!lsc moon print("a b")')
	commands ["ulx lsc"].fn (me, them, "print(a b)")
	T.eq (ran [1].script, 'print("a b")')
end)

T.test ("from the console, or after another chat line, the parsed line runs", function ()
	local commands, ran, _, hooks = ulx_module ()
	local me = player ()
	commands ["ulx l"].fn (me, "print(1)")
	T.eq (ran [1].script, "print(1)", "console")
	hooks.PlayerSay.fn (me, "hello there")
	commands ["ulx l"].fn (me, "print(2)")
	T.eq (ran [2].script, "print(2)", "another line said")
	hooks.PlayerSay.fn (me, '!lc print"x"')
	commands ["ulx l"].fn (me, "print(3)")
	T.eq (ran [3].script, "print(3)", "another command's line")
end)

T.test ("a chat line is used once", function ()
	local commands, ran, _, hooks = ulx_module ()
	local me = player ()
	hooks.PlayerSay.fn (me, '!l print"once"')
	commands ["ulx l"].fn (me, "print once")
	commands ["ulx l"].fn (me, "print(again)")
	T.eq (ran [2].script, "print(again)")
end)

T.test ("a run on the server tells the caller the first line it printed, in chat", function ()
	local commands, _, _, _, said = ulx_module ({ prints = "first\nsecond" })
	commands ["ulx l"].fn (player (), "x()")
	T.eq (said [1], "first", "just the first line")
end)

T.test ("printing nothing, a run tells the values it returned, else that it ran", function ()
	local commands, _, _, _, said = ulx_module ({ values = { 1, "two" } })
	commands ["ulx l"].fn (player (), "return 1, 'two'")
	T.eq (said [1], "1, two", "its values")
	commands, _, _, _, said = ulx_module ()
	commands ["ulx l"].fn (player (), "x()")
	T.eq (said [1], "ok", "that it ran")
end)

T.test ("a run only on clients tells nothing: they do not answer", function ()
	local commands, _, _, _, said = ulx_module ({ prints = "on a client" })
	commands ["ulx lc"].fn (player (), "x()")
	T.eq (#said, 0, "nothing")
end)

T.test ("a failed run tells its error, not a line", function ()
	local commands, _, errors, _, said = ulx_module ({ fail = "boom" })
	commands ["ulx l"].fn (player (), "x()")
	T.eq (errors [1], "boom", "the error")
	T.eq (#said,      0,      "no line")
end)

T.test ("a run that ran cues its caller's client with success; one that failed, with an error", function ()
	local commands, _, _, _, _, cues = ulx_module ()
	local me = player ()
	commands ["ulx l"].fn (me, "x()")
	local failing, _, _, _, _, failed = ulx_module ({ fail = "boom" })
	failing ["ulx l"].fn (me, "x()")
	T.eq (cues [1].ply,                       me,                  "to the caller")
	T.eq (cues [1].fn,                        "surface.PlaySound", "a sound on its client")
	T.eq (failed [1].sound ~= cues [1].sound, true,                "two cues")
	T.eq (#cues .. #failed,                   "11",                "one each")
end)

T.test ("a script that does not compile cues an error", function ()
	local commands, _, _, _, _, cues = ulx_module ()
	commands ["ulx l"].fn (player (), "((")
	local failing, _, _, _, _, failed = ulx_module ({ fail = "boom" })
	failing ["ulx l"].fn (player (), "x()")
	T.eq (#cues,          1,                "cued")
	T.eq (cues [1].sound, failed [1].sound, "as an error")
end)

T.test ("the console is cued nothing: it has no client", function ()
	local commands, _, _, _, _, cues = ulx_module ()
	commands ["ulx l"].fn ({ valid = false }, "x()") -- the console: NULL
	T.eq (#cues, 0, "nothing")
end)

T.test ("a run sent only to clients cues success once sent", function ()
	local commands, _, _, _, _, cues = ulx_module ()
	commands ["ulx lc"].fn (player (), "x()")
	T.eq (#cues, 1, "sent")
end)

T.test ("a run returning work still pending after a frame blips, then cues how it settled", function ()
	local tx = transaction ()
	local commands, _, _, _, _, cues, frames = ulx_module ({ values = { tx } })
	commands ["ulx l"].fn (player (), "return work()")
	T.eq (#cues, 0, "nothing yet")
	frame (frames)
	T.eq (#cues, 1, "a blip after a frame")
	local blip = cues [1].sound
	tx:Settle ("committed")
	T.eq (#cues,                  2,    "then its end")
	T.eq (cues [2].sound ~= blip, true, "not the blip")
	local done, _, _, _, _, doneCues = ulx_module ()
	done ["ulx l"].fn (player (), "x()")
	T.eq (cues [2].sound, doneCues [1].sound, "success")
end)

T.test ("pending work that is declined or fails cues an error as it settles", function ()
	local failing, _, _, _, _, errorCues = ulx_module ({ fail = "boom" })
	failing ["ulx l"].fn (player (), "x()")
	for _, ending in ipairs ({ "declined", "failed" }) do
		local tx = transaction ()
		local commands, _, _, _, _, cues, frames = ulx_module ({ values = { tx } })
		commands ["ulx l"].fn (player (), "return work()")
		frame (frames)
		tx:Settle (ending)
		T.eq (cues [2].sound, errorCues [1].sound, ending)
	end
end)

T.test ("work settled within the frame cues only how it settled, no blip", function ()
	local tx = transaction ()
	local commands, _, _, _, _, cues, frames = ulx_module ({ values = { tx } })
	commands ["ulx l"].fn (player (), "return work()")
	tx:Settle ("committed")
	frame (frames)
	T.eq (#cues, 1, "one cue")
end)

T.test ("a long line is cut to 120 characters, saying how many more there were", function ()
	local commands, _, _, _, said = ulx_module ({ prints = string.rep ("a", 120) .. string.rep ("b", 85) })
	commands ["ulx l"].fn (player (), "x()")
	T.eq (said [1], string.rep ("a", 120) .. "... (85+ chars)", "cut")
	local exact, _, _, _, saidExact = ulx_module ({ prints = string.rep ("a", 120) })
	exact ["ulx l"].fn (player (), "x()")
	T.eq (saidExact [1], string.rep ("a", 120), "120 is whole")
end)

T.test ("work still going after 10 seconds is told so, with a neutral cue, and listened for no more", function ()
	local tx = transaction ()
	local commands, _, _, _, said, cues, frames = ulx_module ({ values = { tx } })
	commands ["ulx l"].fn (player (), "return work()")
	frame (frames)
	local blip = cues [1].sound
	after (frames, 9)
	T.eq (#cues, 1, "nothing before 10 seconds")
	after (frames, 10)
	T.eq (#cues,                  2,    "a cue at 10")
	T.eq (cues [2].sound ~= blip, true, "not the blip")
	local done, _, _, _, _, doneCues = ulx_module ()
	done ["ulx l"].fn (player (), "x()")
	local failing, _, _, _, _, errorCues = ulx_module ({ fail = "boom" })
	failing ["ulx l"].fn (player (), "x()")
	T.eq (cues [2].sound ~= doneCues [1].sound and cues [2].sound ~= errorCues [1].sound, true, "neither success nor error")
	T.eq (said [#said]:lower ():find ("still running", 1, true) ~= nil, true, "told: " .. tostring (said [#said]))
	tx:Settle ("committed")
	T.eq (#cues, 2, "its end unheard")
end)

T.test ("work settled before 10 seconds is not told it is still going", function ()
	local tx = transaction ()
	local commands, _, _, _, said, cues, frames = ulx_module ({ values = { tx } })
	commands ["ulx l"].fn (player (), "return work()")
	frame (frames)
	tx:Settle ("committed")
	local lines = #said
	after (frames, 10)
	T.eq (#cues, 2,     "the blip and its end, no more")
	T.eq (#said, lines, "nothing said")
end)

local PREFERENCES = { "cl_luadev_output_maxchars", "cl_luadev_output_maxlines", "cl_luadev_output_timeout", "cl_luadev_output_overlay",
	"cl_luadev_output_success", "cl_luadev_output_error", "cl_luadev_output_progress", "cl_luadev_output_neutral" }

T.test ("its settings are preferences each client saves and tells the server, under cl_luadev_output", function ()
	local _, _, _, _, _, _, _, created = ulx_module ({ client = true })
	for _, name in ipairs (PREFERENCES) do
		T.eq (created [name] ~= nil,   true, name)
		T.eq (created [name].save,     true, name .. " is saved")
		T.eq (created [name].userinfo, true, name .. " reaches the server")
	end
end)

T.test ("the server makes none of them", function ()
	local _, _, _, _, _, _, _, created = ulx_module ()
	T.eq (next (created), nil, "none")
end)

T.test ("each caller goes by its own preferences", function ()
	local commands, _, _, _, said = ulx_module ({ prints = "one\ntwo" })
	commands ["ulx l"].fn (player ({ prefs = { cl_luadev_output_maxlines = 2 } }), "x()")
	T.eq (table.concat (said, "|"), "one|two", "the one who asked for two")
	for i = #said, 1, -1 do said [i] = nil end
	commands ["ulx l"].fn (player (), "x()")
	T.eq (table.concat (said, "|"), "one|... (1+ lines)", "the one who did not")
end)

T.test ("the console, which has no client, goes by the defaults", function ()
	local commands, _, _, _, said, cues = ulx_module ({ prints = "first\nsecond" })
	commands ["ulx l"].fn ({ valid = false }, "x()")
	T.eq (table.concat (said, "|"), "first|... (1+ lines)", "one line")
	T.eq (#cues,                    0,                      "nothing to hear it")
end)

T.test ("a number preference that is not one goes by its default", function ()
	local commands, _, _, _, said = ulx_module ({ prints = "first\nsecond" })
	commands ["ulx l"].fn (player ({ prefs = { cl_luadev_output_maxlines = "lots" } }), "x()")
	T.eq (table.concat (said, "|"), "first|... (1+ lines)", "one line")
end)

T.test ("a line in chat is as long as cl_luadev_output_maxchars, or whole at 0", function ()
	local commands, _, _, _, said = ulx_module ({ prints = string.rep ("a", 30) })
	commands ["ulx l"].fn (player ({ prefs = { cl_luadev_output_maxchars = 10 } }), "x()")
	T.eq (said [1], string.rep ("a", 10) .. "... (20+ chars)", "cut at 10")
	local whole, _, _, _, wholeSaid = ulx_module ({ prints = string.rep ("a", 300) })
	whole ["ulx l"].fn (player ({ prefs = { cl_luadev_output_maxchars = 0 } }), "x()")
	T.eq (wholeSaid [1], string.rep ("a", 300), "uncut")
end)

T.test ("chat is told as many lines as cl_luadev_output_maxlines, saying how many more there were", function ()
	local two = player ({ prefs = { cl_luadev_output_maxlines = 2 } })
	local commands, _, _, _, said = ulx_module ({ prints = "one\ntwo\n\nthree\nfour" })
	commands ["ulx l"].fn (two, "x()")
	T.eq (table.concat (said, "|"), "one|two|... (2+ lines)", "two, then how many more")
	local all, _, _, _, allSaid = ulx_module ({ prints = "one\ntwo" })
	all ["ulx l"].fn (two, "x()")
	T.eq (table.concat (allSaid, "|"), "one|two", "all there were")
	local off, _, _, _, offSaid = ulx_module ({ prints = "a line" })
	off ["ulx l"].fn (player ({ prefs = { cl_luadev_output_maxlines = 0 } }), "x()")
	T.eq (#offSaid, 0, "none at 0")
end)

T.test ("one line by default", function ()
	local commands, _, _, _, said = ulx_module ({ prints = "first\nsecond\nthird" })
	commands ["ulx l"].fn (player (), "x()")
	T.eq (table.concat (said, "|"), "first|... (2+ lines)", "the first, then how many more")
end)

T.test ("work is listened for cl_luadev_output_timeout seconds", function ()
	local tx = transaction ()
	local commands, _, _, _, said, _, frames = ulx_module ({ values = { tx } })
	commands ["ulx l"].fn (player ({ prefs = { cl_luadev_output_timeout = 3 } }), "return work()")
	local lines = #said
	after (frames, 3)
	T.eq (#said, lines + 1, "told at 3")
end)

T.test ("each cue is its convar's sound, and none when it is empty", function ()
	local commands, _, _, _, _, cues = ulx_module ()
	commands ["ulx l"].fn (player ({ prefs = { cl_luadev_output_success = "my/ok.wav" } }), "x()")
	T.eq (cues [1].sound, "my/ok.wav", "its sound")
	local quiet, _, _, _, _, quietCues = ulx_module ({ fail = "boom" })
	quiet ["ulx l"].fn (player ({ prefs = { cl_luadev_output_error = "" } }), "x()")
	T.eq (#quietCues, 0, "none")
end)

-- luadev's console-only features, as ULX commands
local NEW = { "lfile", "lent", "lwep", "leffect", "lwatch", "lunwatch", "lcopy", "lspawn" }

T.test ("every command, luadev's console-only features among them, says what it does with an example", function ()
	local commands = ulx_module ()
	for _, name in ipairs (AOWL) do
		T.eq (commands ["ulx " .. name].text:find ("e.g. !" .. name, 1, true) ~= nil, true, name .. ": " .. commands ["ulx " .. name].text)
	end
	for _, name in ipairs (NEW) do
		local c = commands ["ulx " .. name]
		T.eq (c ~= nil,                                       true,         name)
		T.eq (c.say,                                          "!" .. name,  name .. "'s say command")
		T.eq (c.access,                                       "superadmin", name .. " is a superadmin's")
		T.eq (c.text:find ("e.g. !" .. name, 1, true) ~= nil, true,         name .. ": " .. tostring (c.text))
	end
end)

T.test ("every parameter is named for the menu", function ()
	local commands = ulx_module ()
	for name, c in pairs (commands) do
		for i, param in ipairs (c.params) do T.eq (type (param.hint), "string", name .. "'s parameter " .. i) end
	end
end)

local SENDS = { server = "lua_send_sv", shared = "lua_send_sh", clients = "lua_send_clients" }

T.test ("lfile runs a Lua file where it is told, as luadev's lua_send_* does", function ()
	for where, command in pairs (SENDS) do
		local commands, _, _, _, _, cues, _, _, consoled = ulx_module ({ files = { ["my/file.lua"] = true } })
		local me = player ()
		commands ["ulx lfile"].fn (me, "my/file.lua", where)
		T.eq (consoled [1].command,  command,       where)
		T.eq (consoled [1].args [1], "my/file.lua", where .. ": the file")
		T.eq (consoled [1].ply,      nil,           where .. ": as the console (NULL), ULX having let the caller")
		T.eq (#cues,                 1,             where .. ": cued")
	end
end)

T.test ("a file luadev cannot find is refused with an error cue, and nothing runs", function ()
	local commands, _, errors, _, _, cues, _, _, consoled = ulx_module ()
	commands ["ulx lfile"].fn (player (), "nowhere.lua", "server")
	T.eq (#consoled,                                       0,    "nothing")
	T.eq (errors [1]:find ("nowhere.lua", 1, true) ~= nil, true, "told why")
	T.eq (#cues,                                           1,    "cued")
end)

T.test ("lent, lwep and leffect register a scripted class from a file, as luadev's sends do", function ()
	for name, command in pairs ({ lent = "lua_send_ent", lwep = "lua_send_wep", leffect = "lua_send_effect" }) do
		local commands, _, _, _, _, _, _, _, consoled = ulx_module ({ files = { ["entities/x.lua"] = true } })
		commands ["ulx " .. name].fn (player (), "entities/x.lua")
		T.eq (consoled [1].command,  command,          name)
		T.eq (consoled [1].args [1], "entities/x.lua", name .. ": the file")
	end
end)

T.test ("lwatch sends a file again where it is told each time it changes; lunwatch stops", function ()
	local commands, _, _, _, _, _, _, _, consoled = ulx_module ({ files = { ["my/file.lua"] = true } })
	commands ["ulx lwatch"].fn (player (), "my/file.lua", "shared")
	T.eq (consoled [1].command,                  "lua_watch",                    "watched")
	T.eq (table.concat (consoled [1].args, " "), "my/file.lua lua_send_sh PATH", "sent shared on each change")
	commands ["ulx lunwatch"].fn (player (), "2")
	T.eq (consoled [2].command .. " " .. consoled [2].args [1], "lua_watch_kill 2", "one stopped")
	commands ["ulx lunwatch"].fn (player ())
	T.eq (consoled [3].args [1], "", "all stopped")
end)

T.test ("lcopy copies a value to the caller's clipboard; lspawn spawns a class or model at the aim", function ()
	local commands, ran = ulx_module ()
	commands ["ulx lcopy"].fn (player (), "me:GetPos()")
	T.eq (ran [1].where,  "server",                                               "copied from the server")
	T.eq (ran [1].script, "local v = me:GetPos() easylua.CopyToClipboard(v, me)", "the value, to me")
	commands ["ulx lspawn"].fn (player (), "models/props_c17/oildrum001.mdl")
	T.eq (ran [2].script, 'easylua.CreateEntity("models/props_c17/oildrum001.mdl")', "spawned")
end)

T.test ("!print of one of easylua's relative names also shows it to its caller; of anything else, prints only", function ()
	local commands, ran = ulx_module ()
	commands ["ulx print"].fn (player (), "this")
	-- GMod's require returns nothing: the module is its global table
	T.eq (ran [1].script, 'print(this) require("luadev_overlay") luadev_overlay.Show(me, "this", this)', "shown")
	commands ["ulx print"].fn (player (), " there ")
	T.eq (ran [2].script:find ('Show(me, "there", there)', 1, true) ~= nil, true, "trimmed")
	commands ["ulx print"].fn (player (), "me:GetPos()")
	T.eq (ran [3].script, "print(me:GetPos())", "printed only")
end)

T.test ("each module clients run sends itself to them as it loads", function ()
	local _, _, _, _, _, _, _, _, _, sent = ulx_module ()
	T.eq (table.concat (sentByModules, " "), "itself itself", "luadev_output and luadev_overlay, each itself")
	T.eq (#sent,                             0,               "the ULX module sends none of them")
end)

T.finish ()
