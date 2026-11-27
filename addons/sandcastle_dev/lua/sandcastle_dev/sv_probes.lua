-- The probes: Lua that asks the running game one question and answers it as data (a census, an
-- audit, a check of a live system), kept in sandcastle_dev/probes/<name>.lua and run by name, read
-- from disk each time, so an edited probe runs as it is now. A probe's first line says what it asks.
local PROBES = "sandcastle_dev/probes/"
local NAME = "^[%w_]+$"

local function Exists (name)
	local found = file.Find (PROBES .. name .. ".lua", "LUA")
	return #found > 0
end

-- Runs the probe `name` with the arguments given; answers what it returns (a table, or nothing for a
-- probe that defines a global to call, as profile_server's WSProfile).
function dev.probe (name, ...)
	if type (name) ~= "string" or not name:match (NAME) or not Exists (name) then
		dev.Fail ("no probe " .. tostring (name) .. ": dev.probes() lists them")
	end
	return dev.load (PROBES .. name .. ".lua", ...)
end

-- Every probe: { name, about }, about the first line of its comment.
function dev.probes ()
	local listed = {}
	local found = file.Find (PROBES .. "*.lua", "LUA")
	table.sort (found)
	for _, file_name in ipairs (found) do
		local text = file.Read (PROBES .. file_name, "LUA") or ""
		listed [#listed + 1] = { name = file_name:gsub ("%.lua$", ""), about = text:match ("^%-%- ([^\n]*)") or "" }
	end
	return listed
end

dev.Command ("dev_probe", function (args) return dev.probe (args [1]) end,
	"dev_probe <name>: run a probe of sandcastle_dev/probes/ and print what it returns")
dev.Command ("dev_probes", function () return dev.probes () end, "dev_probes: every probe and what it asks")
