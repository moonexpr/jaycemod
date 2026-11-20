-- nextsoldier.world.teleports: a map's teleporters as a walker meets them. A trigger_teleport
-- is a box that sends whoever walks into it to the point its target names: its entry is the
-- middle of the box's floor, its exit that point. One disabled, or naming no point, sends no one.
local T = dofile ("tests/harness.lua")
local Teleports = nextsoldier.world.teleports

local function Box (mins, maxs, target, disabled)
	return { mins = mins, maxs = maxs, target = target, disabled = disabled or false }
end

local NAMED = { exit = { x = 900, y = 0, z = 64 } }
local function At (name) return NAMED [name] end

T.test ("a teleporter's entry is the middle of its floor, its exit the point it names", function ()
	local links = Teleports.Links ({ Box ({ x = 0, y = 0, z = 10 }, { x = 100, y = 50, z = 90 }, "exit") }, At)
	T.eq (#links, 1, "one")
	local link = links [1]
	T.eq (link.entry.x,        50,         "the middle across")
	T.eq (link.entry.y,        25,         "the middle along")
	T.eq (link.entry.z,        10,         "on its floor")
	T.eq (link.entry.teleport, true,       "a teleporter's entry")
	T.eq (link.exit,           NAMED.exit, "where it sends")
	T.eq (link.mins.x,         0,          "its box kept")
	T.eq (link.maxs.z,         90,         "to its top")
end)

T.test ("one disabled, or naming nothing there, sends no one", function ()
	local links = Teleports.Links (
		{
			Box ({ x = 0, y = 0, z = 0 }, { x = 1, y = 1, z = 1 }, "exit", true),
			Box ({ x = 0, y = 0, z = 0 }, { x = 1, y = 1, z = 1 }, "nowhere"),
			Box ({ x = 0, y = 0, z = 0 }, { x = 1, y = 1, z = 1 }, nil)
		}, At)
	T.eq (#links, 0, "none")
end)

T.finish ()
