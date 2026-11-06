-- ULX variants of luadev's aowl chat commands (luadev_chatcmds.lua), in the ulx_luadev addon
-- that server_root.py links into the dedicated server, which has ULX and no aowl: "ulx l" in the
-- console, "!l" in chat. ULX includes this module on both sides; the commands
-- run on the server. ULX's access decides who may call them, as aowl's groups
-- did: lm is every player's, the rest are superadmins'. A run on the server tells its caller, in
-- chat, the first line it printed, else the values it returned, else that it ran; clients do
-- not answer, so a run only on them tells nothing. Its caller's client hears how it went: a
-- success cue, an error cue, or, for work it returned still going a frame later (the gamemode's
-- transactions), a blip, then the cue for how the work settled; still going after LISTEN_FOR
-- seconds, it is told so, with a neutral cue, and its end goes unheard.
local CATEGORY = "LuaDev"

local function who(ply, name) return luadev.GetPlayerIdentifier(ply, "cmd:" .. name) end

-- ULib splits a chat command's arguments and drops their quotes (print"x"
-- would run as print x). A monitor, before ULib's say commands, keeps the
-- line each player last typed, and a command typed in chat runs its lua as
-- typed; from the console it runs the line it was given.
local said = setmetatable({}, { __mode = "k" })
hook.Add("PlayerSay", "ws_ulx_luadev_said", function(ply, text) said[ply] = text end, HOOK_MONITOR_HIGH)

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
	{ "l", "Runs lua on the server", function(line) return { { "server", line } } end },
	{ "ls", "Runs lua shared (server and all clients)", function(line) return { { "shared", line } } end },
	{ "lc", "Runs lua on all clients", function(line) return { { "clients", line } } end },
	{ "lm", "Runs lua on your own client (me)", function(line) return { { "me", line } } end },
	{ "lb", "Runs lua on both the server and your own client", function(line)
		return { { "me", line }, { "server", line } }
	end },
	{ "print", "Prints a value in the server console", function(line)
		return { { "server", "print(" .. line .. ")" } }
	end },
	{ "table", "Prints a table in the server console", function(line)
		return { { "server", "PrintTable(" .. line .. ")" } }
	end },
	{ "printc", "Prints a value from every client in the server console", function(line)
		return { { "clients", "easylua.PrintOnServer(" .. line .. ")" } }
	end },
	{ "printm", "Prints a value from your own client (me) in the server console", function(line)
		return { { "me", "easylua.PrintOnServer(" .. line .. ")" } }
	end },
	{ "printb", "Prints a value on both the server and your own client", function(line)
		return { { "me", "easylua.PrintOnServer(" .. line .. ")" }, { "server", "print(" .. line .. ")" } }
	end },
}

-- How long a line chat is given; a longer one is cut there, saying how many more it had.
local FEEDBACK_MAX = 120
local PRINTERS = { print = "\t", Msg = "", MsgN = "", MsgC = "" }
local NEWLINE = { print = true, MsgN = true }

-- What fn printed while it ran, as text (still printed as ever), then what it returned.
local function captured(fn)
	local text, saved = {}, {}
	for printer, sep in pairs(PRINTERS) do
		saved[printer] = _G[printer]
		_G[printer] = function(...)
			local parts = {}
			for i = 1, select("#", ...) do
				local v = select(i, ...)
				if type(v) ~= "table" then parts[#parts + 1] = tostring(v) end -- MsgC's colours
			end
			text[#text + 1] = table.concat(parts, sep) .. (NEWLINE[printer] and "\n" or "")
			if saved[printer] then return saved[printer](...) end
		end
	end
	local results = { pcall(fn) }
	for printer in pairs(PRINTERS) do _G[printer] = saved[printer] end
	if not results[1] then error(results[2], 0) end
	return table.concat(text), unpack(results, 2)
end

-- The line a run on the server tells its caller.
local function first_line(printed, values)
	local line = printed:match("([^\n]*%S[^\n]*)")
	if not line and values and #values > 0 then
		local parts = {}
		for i, v in ipairs(values) do parts[i] = tostring(v) end
		line = table.concat(parts, ", "):match("([^\n]*)")
	end
	line = line and line:match("^%s*(.-)%s*$") or "ok"
	if #line > FEEDBACK_MAX then line = string.format("%s... (%d+ chars)", line:sub(1, FEEDBACK_MAX), #line - FEEDBACK_MAX) end
	return line
end

-- What the caller's client plays: a run done, failed, or its work still going after a frame.
local SUCCESS_SOUND, ERROR_SOUND, PROGRESS_SOUND = "buttons/button14.wav", "buttons/button10.wav", "buttons/blip1.wav"
local NEUTRAL_SOUND = "buttons/button16.wav"
-- How long a run's work is listened for.
local LISTEN_FOR = 10
local STILL_RUNNING = "Still running; no longer listening for its end."
-- A transaction's states, as the gamemode's foundation names them.
local PENDING, COMMITTED = "pending", "committed"

-- Plays sound on ply's own client; the console has none.
local function cue(ply, sound)
	if IsValid(ply) then ULib.clientRPC(ply, "surface.PlaySound", sound) end
end

local function failed(ply, why)
	cue(ply, ERROR_SOUND)
	return ULib.tsayError(ply, why, true)
end

-- Work a run returned that goes on after it: a value answering State() and OnSettle(fn), pending.
local function pending_work(values)
	if type(values) ~= "table" then return nil end
	for _, v in ipairs(values) do
		if type(v) == "table" and type(v.State) == "function" and type(v.OnSettle) == "function" and v:State() == PENDING then
			return v
		end
	end
end

-- The caller's cue for a run that went through: success now, or, for work still going a frame
-- later, a blip, then the cue for how it settled; still going after LISTEN_FOR seconds, a word
-- and a neutral cue, and no more.
local function cue_done(ply, work)
	if not work then return cue(ply, SUCCESS_SOUND) end
	local listening = true
	work:OnSettle(function(settled)
		if listening then cue(ply, settled:State() == COMMITTED and SUCCESS_SOUND or ERROR_SOUND) end
	end)
	timer.Simple(0, function()
		if work:State() == PENDING then cue(ply, PROGRESS_SOUND) end
	end)
	timer.Simple(LISTEN_FOR, function()
		if work:State() ~= PENDING then return end
		listening = false
		ULib.tsay(ply, STILL_RUNNING)
		cue(ply, NEUTRAL_SOUND)
	end)
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
			printed, ok, why = captured(function() return luadev.RunOnServer(script, who(ply, name), extra) end)
		elseif where == "shared" then
			printed, ok, why = captured(function() return luadev.RunOnShared(script, who(ply, name), extra) end)
		elseif where == "clients" then ok, why = luadev.RunOnClients(script, who(ply, name), extra)
		else ok, why = luadev.RunOnClient(script, where == "me" and ply or where, who(ply, name), extra)
		end
		if not ok then return failed(ply, tostring(why)) end
		if printed then
			ULib.tsay(ply, first_line(printed, why))
			work = work or pending_work(why)
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

add("lsc", "Runs lua on a specific player", function(ply, target, line)
	local typed = Typed(ply, "lsc")
	run(ply, "lsc", { { target, typed and typed:match("^%S+%s+(.+)$") or line } })
end, { { type = ULib.cmds.PlayerArg }, LUA })

local function add_keys(name, help, where)
	add(name, help, function(ply, expression, search)
		run(ply, name, { { where, keys_script(expression, search) } })
	end, {
		{ type = ULib.cmds.StringArg, hint = "table" },
		{ type = ULib.cmds.StringArg, hint = "search", ULib.cmds.optional },
	})
end
add_keys("keys", "Lists the keys of a table on the server", "server")
add_keys("keysm", "Lists the keys of a table on your own client (me)", "me")
