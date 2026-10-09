-- ULX variants of luadev's aowl chat commands (luadev_chatcmds.lua), for the
-- dedicated server (server_root.py), which has ULX and no aowl: "ulx l" in the
-- console, "!l" in chat. ULX includes this module on both sides; the commands
-- run on the server. ULX's access decides who may call them, as aowl's groups
-- did: lm is every player's, the rest are superadmins'.
local CATEGORY = "LuaDev"

local function who(ply, name) return luadev.GetPlayerIdentifier(ply, "cmd:" .. name) end

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

-- runs each of runs as ply, once every script compiles; tells ply why not
local function run(ply, name, runs)
	for _, r in ipairs(runs) do
		local ok, why = luadev.ValidScript(r[2], name)
		if not ok then return ULib.tsayError(ply, why, true) end
	end
	local extra = { ply = ply }
	for _, r in ipairs(runs) do
		local where, script = r[1], r[2]
		local ok, why
		if where == "server" then ok, why = luadev.RunOnServer(script, who(ply, name), extra)
		elseif where == "shared" then ok, why = luadev.RunOnShared(script, who(ply, name), extra)
		elseif where == "clients" then ok, why = luadev.RunOnClients(script, who(ply, name), extra)
		else ok, why = luadev.RunOnClient(script, where == "me" and ply or where, who(ply, name), extra)
		end
		if not ok then return ULib.tsayError(ply, tostring(why), true) end
	end
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
	local fn = function(ply, line) run(ply, name, runs(line)) end
	if name == "lm" then
		fn = function(ply, line)
			if not ply:IsAdmin() and not sv_allowcslua:GetBool() then
				return ULib.tsayError(ply, "sv_allowcslua is 0", true)
			end
			run(ply, name, runs(line))
		end
	end
	add(name, help, fn, { LUA }, name == "lm" and ULib.ACCESS_ALL or nil)
end

add("lsc", "Runs lua on a specific player", function(ply, target, line)
	run(ply, "lsc", { { target, line } })
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
