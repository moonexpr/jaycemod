-- ULX variants of luadev's aowl chat commands (luadev_chatcmds.lua), in the ulx_luadev addon
-- that server_root.py links into the dedicated server, which has ULX and no aowl: "ulx l" in the
-- console, "!l" in chat. ULX includes this module on both sides; the commands
-- run on the server. ULX's access decides who may call them, as aowl's groups
-- did: lm is every player's, the rest are superadmins'. A run on the server tells its caller, in
-- chat, the lines it printed, else the values it returned, else that it ran; clients do
-- not answer, so a run only on them tells nothing. Its caller's client hears how it went: a
-- success cue, an error cue, or, for work it returned still going a frame later (the gamemode's
-- transactions), a blip, then the cue for how the work settled; still going once it is no longer
-- listened for, it is told so, with a neutral cue, and its end goes unheard. Each is a server convar
-- a server.cfg sets, read as it is used: sv_luadev_output_maxlines (lines told, 0 for none),
-- _maxchars (a line's length, 0 for whole), _timeout (seconds listened), and the sounds
-- _success, _error, _progress and _neutral (a path, empty for none).
local CATEGORY = "LuaDev"

-- the library both sides run: what a run says, and what !print shows
if SERVER then
	AddCSLuaFile("includes/modules/luadev_output.lua")
	AddCSLuaFile("includes/modules/luadev_show.lua")
end
local Output = require("luadev_output")
local Show = require("luadev_show")

local function who(ply, name) return luadev.GetPlayerIdentifier(ply, "cmd:" .. name) end

-- ULib splits a chat command's arguments and drops their quotes (print"x"
-- would run as print x). A monitor, before ULib's say commands, keeps the
-- line each player last typed, and a command typed in chat runs its lua as
-- typed; from the console it runs the line it was given.
local said = setmetatable({}, { __mode = "k" })
hook.Add("PlayerSay", "ulx_luadev_said", function(ply, text) said[ply] = text end, HOOK_MONITOR_HIGH)

-- What ply typed after !name, as typed, once; nil when that line was not it.
local function Typed(ply, name)
	local text = said[ply]
	said[ply] = nil
	local word, rest = (text or ""):match("^!(%S+)%s*(.-)%s*$")
	if not word or word:lower() ~= name then return nil end
	return rest
end

-- the keys of a table expression's value, sorted, that contain the search
local function keys_script(expression, search)
	return "local t={} for k in pairs(" .. expression .. ") do t[#t+1]=tostring(k) end table.sort(t) "
		.. "local s=" .. string.format("%q", (search or ""):lower()) .. " "
		.. "for _,v in ipairs(t) do if string.find(v:lower(),s,1,true) then print(v) end end"
end

-- name -> help and the runs it makes: each { where, script }, where is "server",
-- "shared", "clients", "me" (the caller's client) or a player
local COMMANDS = {
	{ "l", "Runs lua on the server (easylua's me, this, there, trace), e.g. !l print(me:Nick())",
		function(line) return { { "server", line } } end },
	{ "ls", "Runs lua shared, on the server and every client, e.g. !ls print(SERVER)",
		function(line) return { { "shared", line } } end },
	{ "lc", "Runs lua on every client, e.g. !lc print(LocalPlayer():Nick())",
		function(line) return { { "clients", line } } end },
	{ "lm", "Runs lua on your own client (me), e.g. !lm print(ScrW(), ScrH())",
		function(line) return { { "me", line } } end },
	{ "lb", "Runs lua on both the server and your own client, e.g. !lb print(SERVER, CLIENT)", function(line)
		return { { "me", line }, { "server", line } }
	end },
	{ "print", "Prints a value on the server, told in chat; one of easylua's (this, we, there, trace...) also shown"
		.. " a moment where it is, e.g. !print this", function(line)
		local name = line:match("^%s*(.-)%s*$")
		if Show.RELATIVES[name] then
			return { { "server", string.format("print(%s) require(%q).Show(me, %q, %s)", name, "luadev_show", name, name) } }
		end
		return { { "server", "print(" .. line .. ")" } }
	end },
	{ "table", "Prints a table on the server, its first lines told in chat, e.g. !table me:GetWeapons()", function(line)
		return { { "server", "PrintTable(" .. line .. ")" } }
	end },
	{ "printc", "Prints a value from every client in the server console, e.g. !printc LocalPlayer():Ping()", function(line)
		return { { "clients", "easylua.PrintOnServer(" .. line .. ")" } }
	end },
	{ "printm", "Prints a value from your own client (me) in the server console, e.g. !printm ScrW()", function(line)
		return { { "me", "easylua.PrintOnServer(" .. line .. ")" } }
	end },
	{ "printb", "Prints a value on both the server and your own client, e.g. !printb CurTime()", function(line)
		return { { "me", "easylua.PrintOnServer(" .. line .. ")" }, { "server", "print(" .. line .. ")" } }
	end },
}

-- The server's settings, sv_luadev_output_*, created where the commands run.
local setting = {}
if SERVER then
	local function Setting(name, default, help, min)
		setting[name] = CreateConVar("sv_luadev_output_" .. name, default, nil, help, min)
	end
	Setting("maxlines", "1", "How many lines of a luadev command's output its caller is told in chat; 0 for none", 0)
	Setting("maxchars", "120", "How long a line of a luadev command's output in chat is: a longer one is cut, saying how many more it had; 0 for uncut", 0)
	Setting("overlay", "2", "How long !print of one of easylua's relative names (this, we, there, trace...) is shown to its caller, in seconds; 0 for not", 0)
	Setting("timeout", "10", "How long a luadev command listens for the work its run returned before saying it still runs", 0)
	Setting("success", "buttons/button14.wav", "The sound a luadev command's caller hears when its run went through; empty for none")
	Setting("error", "buttons/button10.wav", "The sound a luadev command's caller hears when its run did not compile, failed or was refused; empty for none")
	Setting("progress", "buttons/blip1.wav", "The sound a luadev command's caller hears when the work its run returned is still going a frame later; empty for none")
	Setting("neutral", "buttons/button16.wav", "The sound a luadev command's caller hears when it stops listening for work still going; empty for none")
end

-- What the caller's client plays: a run done, failed, or its work still going after a frame.
local STILL_RUNNING = "Still running; no longer listening for its end."
local PENDING, COMMITTED = Output.PENDING, Output.COMMITTED

-- Plays the sound a setting names on ply's own client; the console has none, and an empty
-- setting plays nothing.
local function cue(ply, which)
	local sound = setting[which]:GetString()
	if IsValid(ply) and sound ~= "" then ULib.clientRPC(ply, "surface.PlaySound", sound) end
end

local function failed(ply, why)
	cue(ply, "error")
	return ULib.tsayError(ply, why, true)
end


-- The caller's cue for a run that went through: success now, or, for work still going a frame
-- later, a blip, then the cue for how it settled; still going after sv_luadev_output_timeout
-- seconds, a word and a neutral cue, and no more.
local function cue_done(ply, work)
	if not work then return cue(ply, "success") end
	local listening = true
	work:OnSettle(function(settled)
		if listening then cue(ply, settled:State() == COMMITTED and "success" or "error") end
	end)
	timer.Simple(0, function()
		if work:State() == PENDING then cue(ply, "progress") end
	end)
	timer.Simple(setting.timeout:GetFloat(), function()
		if work:State() ~= PENDING then return end
		listening = false
		ULib.tsay(ply, STILL_RUNNING)
		cue(ply, "neutral")
	end)
end

-- tells ply what a run on the server printed or returned, as sv_luadev_output_* say
local function tell(ply, printed, values)
	local maxlines = setting.maxlines:GetInt()
	if maxlines <= 0 then return end
	for _, line in ipairs(Output.Lines(printed, values, maxlines, setting.maxchars:GetInt())) do ULib.tsay(ply, line) end
end

-- runs each of runs as ply, once every script compiles; tells ply why not, and a run on the
-- server's first line, and cues ply's client how it went
local function run(ply, name, runs)
	for _, r in ipairs(runs) do
		local ok, why = luadev.ValidScript(r[2], name)
		if not ok then return failed(ply, why) end
	end
	local work
	local extra = { ply = ply }
	for _, r in ipairs(runs) do
		local where, script = r[1], r[2]
		local ok, why, printed
		if where == "server" then
			printed, ok, why = Output.Captured(function() return luadev.RunOnServer(script, who(ply, name), extra) end)
		elseif where == "shared" then
			printed, ok, why = Output.Captured(function() return luadev.RunOnShared(script, who(ply, name), extra) end)
		elseif where == "clients" then ok, why = luadev.RunOnClients(script, who(ply, name), extra)
		else ok, why = luadev.RunOnClient(script, where == "me" and ply or where, who(ply, name), extra)
		end
		if not ok then return failed(ply, tostring(why)) end
		if printed then
			tell(ply, printed, why)
			work = work or Output.Work(why)
		end
	end
	cue_done(ply, work)
end

local sv_allowcslua = GetConVar("sv_allowcslua")
local LUA = { type = ULib.cmds.StringArg, hint = "lua", ULib.cmds.takeRestOfLine }

local function add(name, help, fn, params, access)
	local cmd = ulx.command(CATEGORY, "ulx " .. name, fn, "!" .. name)
	for _, param in ipairs(params) do cmd:addParam(param) end
	cmd:defaultAccess(access or ULib.ACCESS_SUPERADMIN)
	cmd:help(help)
end

for _, c in ipairs(COMMANDS) do
	local name, help, runs = c[1], c[2], c[3]
	local fn = function(ply, line) run(ply, name, runs(Typed(ply, name) or line)) end
	if name == "lm" then
		fn = function(ply, line)
			line = Typed(ply, name) or line
			if not ply:IsAdmin() and not sv_allowcslua:GetBool() then
				return failed(ply, "sv_allowcslua is 0")
			end
			run(ply, name, runs(line))
		end
	end
	add(name, help, fn, { LUA }, name == "lm" and ULib.ACCESS_ALL or nil)
end

add("lsc", "Runs lua on one player's client, e.g. !lsc bob print(LocalPlayer():Nick())", function(ply, target, line)
	local typed = Typed(ply, "lsc")
	run(ply, "lsc", { { target, typed and typed:match("^%S+%s+(.+)$") or line } })
end, { { type = ULib.cmds.PlayerArg, hint = "player" }, LUA })

local function add_keys(name, help, where)
	add(name, help, function(ply, expression, search)
		run(ply, name, { { where, keys_script(expression, search) } })
	end, {
		{ type = ULib.cmds.StringArg, hint = "table" },
		{ type = ULib.cmds.StringArg, hint = "search", ULib.cmds.optional },
	})
end
add_keys("keys", "Lists the keys of a table on the server that contain a search, e.g. !keys player Get", "server")
add_keys("keysm", "Lists the keys of a table on your own client (me) that contain a search, e.g. !keysm vgui Create", "me")

-- luadev's console-only features: its own console commands (lua_send_*, lua_watch), run on the
-- server as its console once ULX has let the caller (ULX's access decides, as for the commands
-- above, not luadev's own check, which refuses a player Steam has not authenticated), told and
-- cued as a run on the server is; and easylua's helpers.

local FILE = { type = ULib.cmds.StringArg, hint = "file (lua/ path, or data/, ../)" }
-- where a file runs: luadev's send command for each
local SENDS = { server = "lua_send_sv", shared = "lua_send_sh", clients = "lua_send_clients" }
local WHERE = { type = ULib.cmds.StringArg, hint = "server|shared|clients", completes = { "server", "shared", "clients" },
	ULib.cmds.restrictToCompletes }

-- runs luadev's console command as the console for ply, once luadev finds file, telling ply what
-- it printed
local function console(ply, file, command, args)
	if not luadev.RealFilePath(file) then return failed(ply, "luadev finds no file " .. file) end
	local printed = Output.Captured(function() concommand.Run(NULL, command, args, table.concat(args, " ")) end)
	tell(ply, printed, nil)
	cue_done(ply, nil)
end

add("lfile", "Runs a Lua file on the server, shared or on every client, as lua_send_* does, e.g. !lfile autorun/my_test.lua shared",
	function(ply, file, where) console(ply, file, SENDS[where], { file }) end, { FILE, WHERE })

for name, sent in pairs({
	lent = { "lua_send_ent", "Registers a scripted entity from its file or folder, as lua_send_ent does, e.g. !lent entities/my_ent.lua" },
	lwep = { "lua_send_wep", "Registers a weapon from its file or folder, as lua_send_wep does, e.g. !lwep weapons/my_gun.lua" },
	leffect = { "lua_send_effect", "Registers an effect from its file or folder, as lua_send_effect does, e.g. !leffect effects/my_fx.lua" },
}) do
	add(name, sent[2], function(ply, file) console(ply, file, sent[1], { file }) end, { FILE })
end

add("lwatch", "Sends a Lua file again each time it changes on disk, as lua_watch does, e.g. !lwatch autorun/my_test.lua server",
	function(ply, file, where) console(ply, file, "lua_watch", { file, SENDS[where], "PATH" }) end, { FILE, WHERE })

add("lunwatch", "Stops watching a file !lwatch watches, by its place in the list, or every one, e.g. !lunwatch 1",
	function(ply, index)
		local printed = Output.Captured(function() concommand.Run(NULL, "lua_watch_kill", { index or "" }, index or "") end)
		tell(ply, printed, nil)
		cue_done(ply, nil)
	end, { { type = ULib.cmds.StringArg, hint = "index (none: all)", ULib.cmds.optional } })

add("lcopy", "Copies a value from the server to your clipboard, as easylua does, e.g. !lcopy me:GetPos()", function(ply, line)
	run(ply, "lcopy", { { "server", "local v = " .. (Typed(ply, "lcopy") or line) .. " easylua.CopyToClipboard(v, me)" } })
end, { LUA })

add("lspawn", "Spawns an entity class or a model where you aim, undoable, as easylua does, e.g. !lspawn models/props_c17/oildrum001.mdl",
	function(ply, class) run(ply, "lspawn", { { "server", string.format("easylua.CreateEntity(%q)", class) } }) end,
	{ { type = ULib.cmds.StringArg, hint = "class or model" } })
