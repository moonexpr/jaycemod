-- luadev's socket on the dedicated server (server_root.py), for
-- server_lua.py. luadev's own socketdev.lua is client-only: it listens in
-- the operator's game on 27099 and forwards to a server over net messages,
-- with no reply. This listens on the server itself, on 127.0.0.1:27098, runs
-- each chunk through luadev, and answers on the same connection.
--
-- A request is three lines, realm (sv, cl or sh), label and the code's
-- length in bytes, then the code. The answer is JSON: output (print and MsgN
-- while the chunk ran, still echoed to the console), returns, error, and for
-- cl/sh the number of clients it was sent to.
--
-- LuaSocket is luadev's win64 build, lua/bin/gmsv_luasocket_win64.dll in the
-- server's own lua/bin (server_root.py's SERVER_BINARIES); it defines the
-- global socket, the same API as danielga's gmod_luasocket.
require("luasocket")

local HOST, PORT = "127.0.0.1", 27098
local READ_TIMEOUT = 2 -- seconds a connected client has to send its request
local LISTEN_BACKLOG = 4

-- a refresh of this file runs it again: let go of the old port first
if SANDCASTLE_LUADEV_SOCKET then SANDCASTLE_LUADEV_SOCKET:close() end
-- no reuseaddr: setsockopt fails under CrossOver's wine
local listener = assert(socket.tcp())
assert(listener:bind(HOST, PORT))
assert(listener:listen(LISTEN_BACKLOG))
listener:settimeout(0)
SANDCASTLE_LUADEV_SOCKET = listener

local function joined(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
	return table.concat(parts, "\t")
end

local function run_on_server(result, code, label)
	local saved_print, saved_msgn = print, MsgN
	local function capture(saved)
		return function(...)
			result.output[#result.output + 1] = joined(...)
			saved(...)
		end
	end
	print, MsgN = capture(saved_print), capture(saved_msgn)
	local called, ok, values = pcall(luadev.RunOnServer, code, label)
	print, MsgN = saved_print, saved_msgn
	if not called then
		result.error = "luadev failed: " .. tostring(ok)
	elseif ok == true then
		for i = 1, table.maxn(values) do result.returns[#result.returns + 1] = tostring(values[i]) end
	elseif ok == false then
		result.error = tostring(values)
	else
		result.error = "a luadev hook stopped the chunk"
	end
end

local function run_on_clients(result, code, label)
	local sent, why = luadev.RunOnClients(code, label)
	if not sent then result.error = "not sent to the clients: " .. tostring(why) end
	result.clients = player.GetCount()
end

local REALMS = {
	sv = run_on_server,
	cl = run_on_clients,
	sh = function(result, code, label)
		run_on_clients(result, code, label)
		if not result.error then run_on_server(result, code, label) end
	end,
}

local function answer(client)
	local realm = client:receive("*l")
	local label = client:receive("*l")
	local length = tonumber(client:receive("*l") or "")
	local result = { output = {}, returns = {} }
	if not (REALMS[realm] and label and length) then
		result.error = "bad request: expected realm (sv, cl, sh), label and length lines"
	else
		local code = length == 0 and "" or client:receive(length)
		if not code then
			result.error = "the code ended before its " .. length .. " bytes"
		else
			REALMS[realm](result, code, label)
		end
	end
	client:send(util.TableToJSON(result))
end

hook.Add("Think", "SandcastleLuadevSocket", function()
	local client = listener:accept()
	if not client then return end
	client:settimeout(READ_TIMEOUT)
	local ok, err = pcall(answer, client)
	if not ok then ErrorNoHalt("[luadev_socket] " .. tostring(err) .. "\n") end
	client:close()
end)
