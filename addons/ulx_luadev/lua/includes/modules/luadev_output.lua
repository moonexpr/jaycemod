-- luadev_output (ulx_luadev's): what a run says: the output it printed, the lines its caller is
-- told, and work it returned that goes on after it.
--   Captured(fn) -> what fn printed while it ran (print, Msg, MsgN, MsgC), as text, still printed
--     as ever, then what fn returned; fn's error is raised again
--   Lines(printed, values, maxlines, maxchars) -> the lines a run tells its caller: at most
--     maxlines of those it printed (blank ones left out), else its values, else "ok", each at most
--     maxchars long (0: whole), then how many more there were
--   Work(values) -> work a run returned that goes on after it: a value answering State() and
--     OnSettle(fn) (the gamemode's transactions), still PENDING; nil for none
local _G, ipairs, pairs, pcall, select, tostring, type, unpack, error = _G, ipairs, pairs, pcall, select, tostring, type, unpack, error
local concat, format, min = table.concat, string.format, math.min
module(...)

-- A transaction's states, as the gamemode's foundation names them.
PENDING, COMMITTED = "pending", "committed"

local PRINTERS = { print = "\t", Msg = "", MsgN = "", MsgC = "" }
local NEWLINE = { print = true, MsgN = true }

function Captured(fn)
	local text, saved = {}, {}
	for printer, sep in pairs(PRINTERS) do
		saved[printer] = _G[printer]
		_G[printer] = function(...)
			local parts = {}
			for i = 1, select("#", ...) do
				local v = select(i, ...)
				if type(v) ~= "table" then parts[#parts + 1] = tostring(v) end -- MsgC's colours
			end
			text[#text + 1] = concat(parts, sep) .. (NEWLINE[printer] and "\n" or "")
			if saved[printer] then return saved[printer](...) end
		end
	end
	local results = { pcall(fn) }
	for printer in pairs(PRINTERS) do _G[printer] = saved[printer] end
	if not results[1] then error(results[2], 0) end
	return concat(text), unpack(results, 2)
end

function Lines(printed, values, maxlines, maxchars)
	local lines = {}
	for line in printed:gmatch("[^\n]+") do
		if line:find("%S") then lines[#lines + 1] = line:match("^%s*(.-)%s*$") end
	end
	if not lines[1] and values and #values > 0 then
		local parts = {}
		for i, v in ipairs(values) do parts[i] = tostring(v) end
		lines[1] = concat(parts, ", "):match("^%s*([^\n]-)%s*$")
	end
	if not lines[1] then lines[1] = "ok" end
	local told = {}
	for i = 1, min(#lines, maxlines) do
		local line = lines[i]
		if maxchars > 0 and #line > maxchars then
			line = format("%s... (%d+ chars)", line:sub(1, maxchars), #line - maxchars)
		end
		told[i] = line
	end
	if #lines > maxlines then told[#told + 1] = format("... (%d+ lines)", #lines - maxlines) end
	return told
end

function Work(values)
	if type(values) ~= "table" then return nil end
	for _, v in ipairs(values) do
		if type(v) == "table" and type(v.State) == "function" and type(v.OnSettle) == "function" and v:State() == PENDING then
			return v
		end
	end
end
