-- The dev workbench's probes (addons/sandcastle_dev/lua/sandcastle_dev/probes/): Lua that asks the
-- running game one question and answers it as data, run by name (dev.probe) and listed with the first
-- line of each one's comment (dev.probes), so a probe is found from inside the game.
local T = dofile ("tests/harness.lua")

local DIR = "addons/sandcastle_dev/lua/sandcastle_dev/probes/"
local PROBES = "sandcastle_dev/probes/"

local function ReadFile (path)
	local file = io.open (path)
	if not file then return nil end
	local text = file:read ("*a")
	file:close ()
	return text
end

local function ProbeFiles ()
	local names = {}
	local list = assert (io.popen ("ls -1 " .. DIR))
	for name in list:lines () do
		if name:match ("%.lua$") then names [#names + 1] = name end
	end
	list:close ()
	return names
end

-- sv_probes.lua in a stub of the workbench: dev.load reads the repo's files, file.Find lists them
local function Load ()
	local loaded = {}
	local dev =
	{
		Fail = function (message) error (message, 2) end,
		Command = function () end,
		load = function (path, ...)
			loaded [#loaded + 1] = path
			return "ran " .. path, ...
		end
	}
	local env = setmetatable (
		{
			dev = dev,
			file =
			{
				Find = function (pattern, where)
					T.eq (where, "LUA", "the probes are read from the mounted addon")
					-- as GMod's: the files of the pattern's folder whose names match its last part, * any run
					local wanted = "^" .. pattern:match ("[^/]*$"):gsub ("[%.%-]", "%%%0"):gsub ("%*", ".*") .. "$"
					local found = {}
					for _, name in ipairs (ProbeFiles ()) do
						if name:match (wanted) then found [#found + 1] = name end
					end
					return found, {}
				end,
				Read = function (path) return ReadFile ("addons/sandcastle_dev/lua/" .. path) end
			}
		},
		{ __index = _G }
	)
	setfenv (assert (loadfile ("addons/sandcastle_dev/lua/sandcastle_dev/sv_probes.lua")), env) ()
	return dev, loaded
end

T.test ("there are probes, and each begins with the comment line dev.probes shows", function ()
	local names = ProbeFiles ()
	T.eq (#names > 10, true, "the probes moved from .workbench/bin")
	for _, name in ipairs (names) do
		local first = ReadFile (DIR .. name):match ("^[^\n]*")
		T.eq (first:match ("^%-%- %S") ~= nil, true, name .. "'s first line is a comment saying what it asks")
	end
end)

T.test ("dev.probe runs a probe's file by its name and answers what it returns", function ()
	local dev, loaded = Load ()
	local answer, extra = dev.probe ("bot_status", 7)
	T.eq (loaded [1], PROBES .. "bot_status.lua")
	T.eq (answer,     "ran " .. PROBES .. "bot_status.lua")
	T.eq (extra, 7, "its arguments go to the probe")
end)

T.test ("dev.probe refuses a name that is not one probe's", function ()
	local dev, loaded = Load ()
	for _, bad in ipairs ({ "../sv_util", "bot status", "", "nope_not_a_probe" }) do
		local ok, err = pcall (dev.probe, bad)
		T.eq (ok,                                            false, bad)
		T.eq (tostring (err):find ("probe", 1, true) ~= nil, true,  "the refusal says why: " .. tostring (err))
	end
	T.eq (#loaded, 0, "nothing run")
end)

T.test ("dev.probes lists every probe by name with its first comment line", function ()
	local dev = Load ()
	local listed = dev.probes ()
	T.eq (#listed, #ProbeFiles ())
	local status
	for _, probe in ipairs (listed) do
		if probe.name == "bot_status" then status = probe end
	end
	T.eq (status ~= nil,                                            true, "bot_status is listed")
	T.eq (status.about:match ("^The AI war's bot soldiers") ~= nil, true, status.about)
end)

T.finish ()
