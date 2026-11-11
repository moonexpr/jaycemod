-- Wetsands, the game built on Sandcastle: a gamemode of its own, derived from
-- Sandcastle as Sandcastle is from Sandbox.
local T = dofile ("tests/harness.lua")

local ROOT = "addons/sandcastle/gamemodes/wetsands/"

local function Source (path)
	local f = assert (io.open (ROOT .. path))
	local text = f:read ("*a")
	f:close ()
	return text
end

local function Has (text, part, what)
	T.eq (text:find (part, 1, true) ~= nil, true, what)
end

T.test ("its manifest names Sandcastle as its base", function ()
	local manifest = Source ("wetsands.txt")
	Has (manifest, '"wetsands"', "its name")
	T.eq (manifest:match ('"base"%s+"([%w_]+)"'), "sandcastle", "its base")
end)

T.test ("it derives from Sandcastle", function ()
	Has (Source ("gamemode/shared.lua"), 'DeriveGamemode ("sandcastle")', "the derivation")
end)

T.test ("the server sends clients its files and runs the shared one", function ()
	local init = Source ("gamemode/init.lua")
	Has (init, 'AddCSLuaFile ("shared.lua")',  "shared.lua sent")
	Has (init, 'AddCSLuaFile ("cl_init.lua")', "cl_init.lua sent")
	Has (init, 'include ("shared.lua")',       "shared.lua run")
end)

T.test ("clients run the shared file", function ()
	Has (Source ("gamemode/cl_init.lua"), 'include ("shared.lua")', "shared.lua run")
end)

T.finish ()
