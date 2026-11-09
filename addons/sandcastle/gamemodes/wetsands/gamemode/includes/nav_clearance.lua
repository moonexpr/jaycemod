local NavGaps = nextsoldier.world.nav_gaps
local HL2 = require("foundation.wetsands.path.hl2")
local STATIC_BRUSHES = { func_brush = true, func_wall = true }
local ipairs, setmetatable = ipairs, setmetatable
local ceil, max, sqrt = math.ceil, math.max, math.sqrt
module(...)

local function StaticMap(ent)
	return ent:IsWorld() or STATIC_BRUSHES[ent:GetClass()] == true
end

-- How thick the sole of a body is measured when finding where it rests.
local SOLE = 1

local function StepMins(mins, maxs, vector)
	local step = NavGaps.STEP_HEIGHT
	local halfHeight = (maxs.z - mins.z) / 2
	if step > halfHeight then step = halfHeight end
	return vector(mins.x, mins.y, mins.z + step)
end

-- A body as the traces measure it. It stands where its box comes to rest, not
-- on the nav mesh's floor: a body wider than a stair's tread, or across a
-- slope, rides on what stands highest under its footprint, feet and head
-- together, as far above the floor as that lifts it (a tank in a gorge: a
-- hundred and more). What it clears is measured above a step, which it steps
-- over.
local Body = {}
Body.__index = Body

local function NewBody(mins, maxs, mask, traceHull, vector)
	return setmetatable({
		mins = StepMins(mins, maxs, vector),
		maxs = maxs,
		soleMins = mins,
		soleMaxs = vector(maxs.x, maxs.y, mins.z + SOLE),
		height = maxs.z - mins.z - SOLE,
		mask = mask,
		traceHull = traceHull,
		vector = vector,
	}, Body)
end

function Body:Clear(from, to)
	local trace = self.traceHull({
		start = from,
		endpos = to,
		mins = self.mins,
		maxs = self.maxs,
		mask = self.mask,
		filter = StaticMap,
	})
	return not trace.Hit and not trace.StartSolid
end

-- The height the body's sole comes down to at (x, y), dropped from `above` no
-- further than `floor`; nil when solid stands in the way at `above`.
function Body:Rest(x, y, above, floor)
	local trace = self.traceHull({
		start = self.vector(x, y, above),
		endpos = self.vector(x, y, floor),
		mins = self.soleMins,
		maxs = self.soleMaxs,
		mask = self.mask,
		filter = StaticMap,
	})
	if trace.StartSolid then return nil end
	return trace.Hit and trace.HitPos.z or floor
end

-- Whether the body stands over this floor, on it or on what lifts it. It starts
-- from a body's height over the floor: a ceiling lower than the body refuses it
-- however it rests.
function Body:Stands(x, y, floor)
	local onFloor = self.vector(x, y, floor + 1)
	if self:Clear(onFloor, onFloor) then return true end
	local rest = self:Rest(x, y, floor + self.height, floor)
	if not rest then return false end
	local standing = self.vector(x, y, rest + 1)
	return self:Clear(standing, standing)
end

-- Whether the body crosses from `start` over a floor at fromZ to `finish` over
-- one at toZ: level at the higher floor, else walked stride by stride, rising
-- no more than a step in each, so a slope carries it up and a crate stops it.
function Body:Crosses(start, finish, fromZ, toZ)
	local vector = self.vector
	local level = max(fromZ, toZ) + 1
	if self:Clear(vector(start.x, start.y, level), vector(finish.x, finish.y, level)) then return true end
	local floor = (fromZ < toZ and fromZ or toZ) - 1
	local z = self:Rest(start.x, start.y, fromZ + self.height, floor)
	if not z then return false end
	local step = NavGaps.STEP_HEIGHT
	local dx, dy = finish.x - start.x, finish.y - start.y
	local strides = max(1, ceil(sqrt(dx * dx + dy * dy) / step))
	local x, y = start.x, start.y
	for i = 1, strides do
		local nextX, nextY = start.x + dx * i / strides, start.y + dy * i / strides
		local nextZ = self:Rest(nextX, nextY, z + step, floor)
		if not nextZ then return false end
		level = max(z, nextZ) + 1
		if not self:Clear(vector(x, y, level), vector(nextX, nextY, level)) then return false end
		x, y, z = nextX, nextY, nextZ
	end
	return true
end

function FitsLines(lines, mins, maxs, mask, traceHull, vector)
	local body = NewBody(mins, maxs, mask, traceHull, vector)
	for i = 1, #lines do
		local line = lines[i]
		if body:Crosses(line.start, line.finish, line.start.z, line.finish.z) then return true end
	end
	return false
end

local Clearance = {}
Clearance.__index = Clearance
local clearances = {}

-- A body that crouches (its NSCrouchHeight) passes a crouch area crouched, as
-- it walks there (OnNavAreaChanged); elsewhere it is measured by its hull.
function New(entity, mask, traceHull, vector)
	local mins, maxs = entity:GetCollisionBounds()
	local crouchHeight = entity.NSCrouchHeight
	for _, clearance in ipairs(clearances) do
		local cachedMins, cachedMaxs = clearance.hullMins, clearance.hullMaxs
		if clearance.mask == mask and clearance.crouchHeight == crouchHeight
			and clearance.traceHull == traceHull and clearance.vector == vector
			and cachedMins.x == mins.x and cachedMins.y == mins.y and cachedMins.z == mins.z
			and cachedMaxs.x == maxs.x and cachedMaxs.y == maxs.y and cachedMaxs.z == maxs.z then
			return clearance
		end
	end
	local crouchMaxs = maxs
	if crouchHeight and crouchHeight < maxs.z then crouchMaxs = vector(maxs.x, maxs.y, crouchHeight) end
	local clearance = {
		hullMins = mins,
		hullMaxs = maxs,
		standing = NewBody(mins, maxs, mask, traceHull, vector),
		crouched = NewBody(mins, crouchMaxs, mask, traceHull, vector),
		crouchHeight = crouchHeight,
		mask = mask,
		traceHull = traceHull,
		vector = vector,
		areas = {},
		links = {},
	}
	clearance.Area, clearance.Link = Clearance.Area, Clearance.Link
	clearances[#clearances + 1] = clearance
	return clearance
end

function Clear()
	clearances = {}
end

function Clearance:Area(area)
	local id = area:GetID()
	local known = self.areas[id]
	if known ~= nil then return known end
	local center = area:GetCenter()
	local body = HL2.MustCrouch(area:GetAttributes()) and self.crouched or self.standing
	local fits = body:Stands(center.x, center.y, area:GetZ(center))
	self.areas[id] = fits
	return fits
end

function Clearance:Link(from, to)
	local fromId, toId = from:GetID(), to:GetID()
	local links = self.links[fromId]
	if not links then
		links = {}
		self.links[fromId] = links
	end
	local known = links[toId]
	if known ~= nil then return known end

	local side
	for dir = 0, 3 do
		if from:IsConnectedAtSide(to, dir) then
			side = dir
			break
		end
	end

	local crouched = HL2.MustCrouch(from:GetAttributes()) or HL2.MustCrouch(to:GetAttributes())
	local body = crouched and self.crouched or self.standing
	local vector = self.vector
	local function LineFits(line)
		local start, finish = vector(line.start.x, line.start.y, 0), vector(line.finish.x, line.finish.y, 0)
		return body:Crosses(start, finish, from:GetZ(start), to:GetZ(finish))
	end

	local fits = false
	if side == nil then
		fits = LineFits({
			start = from:GetClosestPointOnArea(to:GetCenter()),
			finish = to:GetClosestPointOnArea(from:GetCenter()),
		})
	else
		local extent, other = from:GetExtentInfo(), to:GetExtentInfo()
		local lines = NavGaps.FitLines(
			{ x = extent.lo.x, y = extent.lo.y },
			{ x = extent.hi.x, y = extent.hi.y },
			side,
			{ x = other.lo.x, y = other.lo.y },
			{ x = other.hi.x, y = other.hi.y },
			0
		)
		for i = 1, #lines do
			if LineFits(lines[i]) then
				fits = true
				break
			end
		end
	end
	links[toId] = fits
	return fits
end
