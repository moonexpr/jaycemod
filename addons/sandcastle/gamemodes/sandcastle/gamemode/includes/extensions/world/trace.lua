-- Source's traces by shape, their bounds worked out from an origin and a scale, so a caller
-- names what it asks and not the corners: New(engine) -> traces, each traces.Shape(origin,
-- scale, mask, group, filter):
--   Cube(origin, size)     a hull of that size about the origin, traced where it stands
--   Player(origin, scale)  Source's standing player hull, scaled (1 by default), on its feet there
--   Sphere(origin, radius) SPHERE_RAYS rays from the centre out to the radius
--   Frustum(origin, view)  rays from the eye across a view { forward, fov, vfov (fov), range,
--                          cols, rows (FRUSTUM_COLUMNS by FRUSTUM_ROWS) }, its angles in degrees
-- A hull answers the engine's result; rays answer the nearest hit (the first ray's miss when none
-- hits) and every ray's result. mask and group default to the engine's, filter to nothing.
--
-- With no origin, a shape is a preset of the rest: called on an origin it traces there, and
-- preset:Each(origins) is a generator over them, each traced as it is reached
-- (`for tr, origin, i in fits:Each(spots) do`); given a function, it calls fn(tr, origin, i) for
-- each instead.
--
-- The engine port: Hull(spec) and Line(spec) (util.TraceHull, util.TraceLine), Vector(x, y, z),
-- mask and group, the defaults (MASK_NPCSOLID, COLLISION_GROUP_NONE).
local Box = math.box
local Geometry = math.geometry
local ipairs, setmetatable, rad = ipairs, setmetatable, math.rad
module("games.world.trace")

-- Source's player hull: 32 units across, 72 standing.
PLAYER_WIDTH, PLAYER_HEIGHT = 32, 72
-- How many rays a sphere casts, and the grid a view casts by default.
SPHERE_RAYS, FRUSTUM_COLUMNS, FRUSTUM_ROWS = 26, 5, 3

local Preset = {}
Preset.__index = Preset

function Preset:__call(origin) return self.trace(origin, self.scale, self.mask, self.group, self.filter) end

function Preset:Each(origins, fn)
	local i = 0
	local function step()
		i = i + 1
		local origin = origins[i]
		if origin == nil then return nil end
		return self(origin), origin, i
	end
	if not fn then return step end
	for tr, origin, at in step do fn(tr, origin, at) end
end

-- A shape's trace(origin, ...), and its preset when it is given no origin.
local function Shape(trace)
	return function(origin, scale, mask, group, filter)
		if origin == nil then
			return setmetatable({ trace = trace, scale = scale, mask = mask, group = group, filter = filter }, Preset)
		end
		return trace(origin, scale, mask, group, filter)
	end
end

function New(engine)
	local Vector = engine.Vector

	local function Spec(start, endpos, mask, group, filter)
		return { start = start, endpos = endpos, mask = mask or engine.mask, collisiongroup = group or engine.group,
			filter = filter or {} }
	end

	local function Hull(origin, mins, maxs, mask, group, filter)
		local spec = Spec(origin, origin, mask, group, filter)
		spec.mins, spec.maxs = Vector(mins.x, mins.y, mins.z), Vector(maxs.x, maxs.y, maxs.z)
		return engine.Hull(spec)
	end

	-- A ray from origin to each of points: the nearest hit, or the first miss, and all of them.
	local function Rays(origin, points, mask, group, filter)
		local all, nearest = {}, nil
		for i, p in ipairs(points) do
			local tr = engine.Line(Spec(origin, Vector(p.x, p.y, p.z), mask, group, filter))
			all[i] = tr
			if tr.Hit and (not nearest or not nearest.Hit or tr.Fraction < nearest.Fraction) then nearest = tr end
		end
		return nearest or all[1], all
	end

	local traces = {}
	traces.Cube = Shape(function(origin, size, mask, group, filter)
		local mins, maxs = Box.Centered(size)
		return Hull(origin, mins, maxs, mask, group, filter)
	end)
	traces.Player = Shape(function(origin, scale, mask, group, filter)
		scale = scale or 1
		local mins, maxs = Box.Standing(PLAYER_WIDTH * scale, PLAYER_HEIGHT * scale)
		return Hull(origin, mins, maxs, mask, group, filter)
	end)
	traces.Sphere = Shape(function(origin, radius, mask, group, filter)
		return Rays(origin, Geometry.Sphere(origin, radius, SPHERE_RAYS), mask, group, filter)
	end)
	traces.Frustum = Shape(function(origin, view, mask, group, filter)
		local points = Geometry.Frustum(origin, view.forward, rad(view.fov), rad(view.vfov or view.fov), view.range,
			view.cols or FRUSTUM_COLUMNS, view.rows or FRUSTUM_ROWS)
		return Rays(origin, points, mask, group, filter)
	end)
	return traces
end
