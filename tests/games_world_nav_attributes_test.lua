-- games.world.nav_attributes: TF2's per-area nav attributes, read from the
-- sidecar .devtools/bin/nav_convert.py writes beside a converted mesh.
local T = dofile("tests/harness.lua")
local Attributes = world.nav_attributes

local SENTRY, SNIPER, NO_SPAWNING = 0x400000, 0x200000, 0x2000000 -- tf_nav_area.h

local function Fails(fn, says)
	local ok, err = pcall(fn)
	T.eq(ok, false, "refused: " .. says)
	T.eq(tostring(err):find(says, 1, true) ~= nil, true, "says " .. says .. ": " .. tostring(err))
end

local function Joined(list) return table.concat(list, " ") end

local function Sidecar(lines)
	return "tfnav 1\n" .. table.concat(lines, "\n") .. (#lines > 0 and "\n" or "")
end

T.test("TF2's flags, by their names in tf_nav_area.h", function()
	T.eq(Attributes.FLAGS.SENTRY_SPOT, SENTRY)
	T.eq(Attributes.FLAGS.SNIPER_SPOT, SNIPER)
	T.eq(Attributes.FLAGS.NO_SPAWNING, NO_SPAWNING)
end)

T.test("an area has the attributes its line gives, and no others", function()
	local mesh = Attributes.Parse(Sidecar({ "12 " .. (SENTRY + SNIPER), "40 " .. NO_SPAWNING }))
	T.eq(mesh:Has(12, "SENTRY_SPOT"), true)
	T.eq(mesh:Has(12, "SNIPER_SPOT"), true)
	T.eq(mesh:Has(12, "NO_SPAWNING"), false)
	T.eq(mesh:Has(40, "NO_SPAWNING"), true)
	T.eq(mesh:Has(7, "SENTRY_SPOT"), false, "an area without a line has none")
end)

T.test("an area's names come in the order of their bits", function()
	local mesh = Attributes.Parse(Sidecar({ "3 " .. (NO_SPAWNING + SENTRY + SNIPER) }))
	T.eq(Joined(mesh:Names(3)), "SNIPER_SPOT SENTRY_SPOT NO_SPAWNING")
	T.eq(Joined(mesh:Names(4)), "")
end)

T.test("the areas with an attribute, in id order", function()
	local mesh = Attributes.Parse(Sidecar({ "9 " .. SENTRY, "2 " .. SENTRY, "5 " .. SNIPER }))
	T.eq(Joined(mesh:Areas("SENTRY_SPOT")), "2 9")
	T.eq(Joined(mesh:Areas("RESCUE_CLOSET")), "")
end)

T.test("a map without a sidecar has an empty set", function()
	local mesh = Attributes.None()
	T.eq(mesh:Has(1, "SENTRY_SPOT"), false)
	T.eq(Joined(mesh:Areas("SENTRY_SPOT")), "")
end)

T.test("an unknown attribute name is our bug", function()
	local mesh = Attributes.None()
	Fails(function() mesh:Has(1, "SENTRY") end, "unknown")
	Fails(function() mesh:Areas("sentry_spot") end, "unknown")
end)

T.test("a file that is not a sidecar is refused", function()
	Fails(function() Attributes.Parse("tfnav 2\n") end, "tfnav 1")
	Fails(function() Attributes.Parse("") end, "tfnav 1")
	Fails(function() Attributes.Parse("tfnav 1\n12 x\n") end, "line 2")
	Fails(function() Attributes.Parse("tfnav 1\n12\n") end, "line 2")
end)

T.test("an area's flags that are not TF2's persistent ones are refused", function()
	Fails(function() Attributes.Parse(Sidecar({ "12 64" })) end, "line 2")
end)

T.finish()
