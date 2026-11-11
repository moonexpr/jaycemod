-- games.world.trace: Source's traces by shape, their bounds worked out from an origin and a
-- scale: a cube's hull and a standing player's, a sphere's rays and a view's. Over a port: the
-- engine's hull and line traces, its vectors, and the mask and collision group they default to.
local T = dofile ("tests/harness.lua")
local Trace = world.trace
local Geometry = math.geometry

for _, name in ipairs ({ "PLAYER_WIDTH", "PLAYER_HEIGHT", "SPHERE_RAYS", "FRUSTUM_COLUMNS", "FRUSTUM_ROWS" }) do
	T.defined (Trace [name], name)
end

local MASK, GROUP = 33701899, 0

-- The engine as the test's: each trace it is asked for kept, a line hitting when hits(spec) says,
-- at the fraction it gives.
local function Engine (hits)
	local engine = { asked = {}, mask = MASK, group = GROUP }
	function engine.Vector (x, y, z) return { x = x, y = y, z = z } end
	local function Run (kind)
		return function (spec)
			local fraction = hits and hits (spec)
			engine.asked [#engine.asked + 1] = { kind = kind, spec = spec }
			return { Hit = fraction ~= nil, Fraction = fraction or 1, spec = spec }
		end
	end
	engine.Hull, engine.Line = Run ("hull"), Run ("line")
	return engine
end

local function V (x, y, z) return { x = x, y = y, z = z } end

local function Corners (spec)
	return string.format ("%g,%g,%g %g,%g,%g", spec.mins.x, spec.mins.y, spec.mins.z, spec.maxs.x, spec.maxs.y, spec.maxs.z)
end

T.test ("a cube is a hull of its size about its origin, traced where it stands", function ()
	local engine = Engine ()
	local origin = V (10, 20, 30)
	local tr = Trace.New (engine).Cube (origin, 16)
	local spec = engine.asked [1].spec
	T.eq (engine.asked [1].kind, "hull",           "a hull")
	T.eq (spec.start,            origin,           "from its origin")
	T.eq (spec.endpos,           origin,           "to it")
	T.eq (Corners (spec),        "-8,-8,-8 8,8,8", "its size about it")
	T.eq (tr.spec,               spec,             "the engine's answer")
end)

T.test ("a trace takes the engine's mask and collision group and filters nothing, unless told", function ()
	local engine = Engine ()
	local traces = Trace.New (engine)
	traces.Cube (V (0, 0, 0), 4)
	local spec = engine.asked [1].spec
	T.eq (spec.mask,           MASK,  "the engine's mask")
	T.eq (spec.collisiongroup, GROUP, "its group")
	T.eq (#spec.filter,        0,     "no filter")
	local filter = { "me" }
	traces.Cube (V (0, 0, 0), 4, 1, 5, filter)
	spec = engine.asked [2].spec
	T.eq (spec.mask .. "," .. spec.collisiongroup, "1,5",  "as told")
	T.eq (spec.filter,                             filter, "its filter")
end)

T.test ("a player is Source's standing hull, scaled, on its feet at its origin", function ()
	local engine = Engine ()
	local traces = Trace.New (engine)
	traces.Player (V (0, 0, 0))
	T.eq (Corners (engine.asked [1].spec), string.format ("%g,%g,0 %g,%g,%g", -Trace.PLAYER_WIDTH / 2, -Trace.PLAYER_WIDTH / 2,
		Trace.PLAYER_WIDTH / 2, Trace.PLAYER_WIDTH / 2, Trace.PLAYER_HEIGHT), "a whole one")
	traces.Player (V (0, 0, 0), 0.5)
	T.eq (engine.asked [2].spec.maxs.z, Trace.PLAYER_HEIGHT / 2, "half a one")
end)

local function Spots (count)
	local spots = {}
	for i = 1, count do spots [i] = V (i * 100, 0, 0) end
	return spots
end

T.test ("with no origin, a shape is a preset: called on an origin, it traces there", function ()
	local engine = Engine ()
	local fits = Trace.New (engine).Player (nil, 1, 7)
	T.eq (#engine.asked, 0, "nothing traced yet")
	fits (V (5, 0, 0))
	T.eq (engine.asked [1].spec.start.x, 5, "there")
	T.eq (engine.asked [1].spec.mask,    7, "as preset")
end)

T.test ("a preset's Each is a generator over origins: each traced as it is reached", function ()
	local engine = Engine ()
	local fits = Trace.New (engine).Cube (nil, 8)
	local spots = Spots (3)
	local next, seen = fits:Each (spots), {}
	local tr, origin, i = next ()
	T.eq (#engine.asked, 1,         "one traced for the first step")
	T.eq (origin,        spots [1], "the first origin")
	T.eq (i,             1,         "its place")
	T.eq (tr.spec.start, spots [1], "traced there")
	for tr2, at in next do seen [#seen + 1] = tr2.spec.start == at end
	T.eq (#seen,   2,   "the rest, in a for loop")
	T.eq (next (), nil, "then done")
end)

T.test ("a preset's Each with a function calls it for each origin, in order", function ()
	local engine = Engine ()
	local order = {}
	Trace.New (engine).Cube (nil, 8):Each (Spots (3), function (tr, origin, i) order [#order + 1] = i .. ":" .. origin.x end)
	T.eq (table.concat (order, " "), "1:100 2:200 3:300", "each")
end)

T.test ("a sphere is rays from its centre out to its radius, the nearest hit what it meets", function ()
	local engine = Engine (function (spec)
		if spec.endpos.z > 40 then return 0.25 end
		if spec.endpos.z < -40 then return 0.75 end
	end)
	local tr, all = Trace.New (engine).Sphere (V (0, 0, 0), 50)
	T.eq (#all,                  Trace.SPHERE_RAYS, "a ray each")
	T.eq (engine.asked [1].kind, "line",            "lines")
	for _, asked in ipairs (engine.asked) do
		T.near (Geometry.Length (asked.spec.endpos), 50, 1e-9, "out to its radius")
	end
	T.eq (tr.Fraction, 0.25, "the nearest hit")
end)

T.test ("a sphere meeting nothing answers a miss", function ()
	local tr = Trace.New (Engine ()).Sphere (V (0, 0, 0), 50)
	T.eq (tr.Hit, false, "nothing hit")
end)

T.test ("a frustum is rays from its eye across its view, the nearest hit what it sees", function ()
	local engine = Engine (function (spec) if spec.endpos.y > 1 then return 0.5 end end)
	local tr, all = Trace.New (engine).Frustum (V (0, 0, 0), { forward = V (1, 0, 0), fov = 90, range = 100, cols = 3, rows = 3 })
	T.eq (#all, 9, "a ray each")
	local middle = engine.asked [5].spec
	T.near (middle.endpos.x,                100, 1e-9, "the middle straight ahead")
	T.near (middle.endpos.y,                0,   1e-9, "the middle straight ahead")
	T.near (engine.asked [1].spec.endpos.y, 100, 1e-9, "a 90 degree view's left edge")
	T.eq (tr.Fraction, 0.5, "the nearest hit, on its left")
end)

T.test ("a frustum's grid and height default", function ()
	local engine = Engine ()
	local _, all = Trace.New (engine).Frustum (V (0, 0, 0), { forward = V (1, 0, 0), fov = 90, range = 100 })
	T.eq (#all, Trace.FRUSTUM_COLUMNS * Trace.FRUSTUM_ROWS, "the default grid")
	T.near (engine.asked [1].spec.endpos.z, 100, 1e-9, "as high as wide")
end)

T.finish ()
