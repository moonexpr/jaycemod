-- NextSoldier's binary opened as GMod opens it (gmod13_open), built for a
-- server its engine binding cannot read: every build but win64's, whose
-- binding reads server.dll's MSVC classes (addons/nextsoldier/native). It
-- still loads, as the Linux server in a container loads it (srcds.py
-- --runtime docker): nextsoldier.engine says why it is not bound, as a
-- binding a GMod update broke says, and the native scenarios are published.
local T = dofile ("tests/harness.lua")

local CRATE = "addons/nextsoldier/native/target/release/libnextsoldier"

local function Built ()
	for _, extension in ipairs ({ ".so", ".dylib" }) do
		local file = io.open (CRATE .. extension)
		if file then
			file:close ()
			return CRATE .. extension
		end
	end
	error ("addons/nextsoldier/native is not built: cargo build --release in it")
end

-- gmod13_open writes globals: run it on fresh ones, and put the harness's back
local function Opened ()
	local saved = { nextsoldier = nextsoldier, wartactics = wartactics }
	nextsoldier, wartactics = {}, nil
	local open = assert (package.loadlib (Built (), "gmod13_open"))
	local ok, err = pcall (open)
	local opened = { nextsoldier = nextsoldier, wartactics = wartactics }
	nextsoldier, wartactics = saved.nextsoldier, saved.wartactics
	assert (ok, err)
	return opened
end

T.test ("the engine is published refused, saying it binds only win64's server", function ()
	local engine = Opened ().nextsoldier.engine
	T.eq (type (engine),         "table",  "nextsoldier.engine")
	T.eq (type (engine.refused), "string", "refused")
	assert (engine.refused:find ("win64", 1, true), engine.refused)
	T.eq (engine.Insert, nil, "Insert, which needs the binding")
end)

T.test ("the binary publishes nothing of the war's: its scenarios are wartactics' own Lua", function ()
	T.eq (Opened ().wartactics, nil, "no wartactics")
end)

T.finish ()
