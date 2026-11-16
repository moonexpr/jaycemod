-- player_expressive_base: the expressive player Sandcastle's classes stand on.
local T = dofile ("tests/harness.lua")

local FILE = "addons/sandcastle/gamemodes/sandcastle/gamemode/player_class/player_expressive_base.lua"

-- The globals the file's bytecode reads: a local used above its declaration reads a global.
local function GlobalsRead (path)
	local listing = assert (io.popen ("luajit -bl " .. path))
	local read    = {}
	for line in listing:lines () do
		local name = line:match ("GGET.-; \"([%w_]+)\"")
		if name then read [name] = true end
	end
	listing:close ()

	return read
end

T.test ("the gestures' classes are locals everywhere the class reads them", function ()
	local read = GlobalsRead (FILE)
	for _, name in ipairs ({ "Use", "Carry", "Pain", "Dying" }) do
		T.eq (read [name], nil, name .. " read as a global")
	end
end)

T.finish ()
