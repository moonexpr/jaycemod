local NavGaps = nextsoldier.world.nav_gaps
local HL2 = require("foundation.wetsands.path.hl2")
local STATIC_BRUSHES = { func_brush = true, func_wall = true }
local ipairs = ipairs
module(...)

local function StaticMap(ent)
	return ent:IsWorld() or STATIC_BRUSHES[ent:GetClass()] == true
end

-- How high a body stands over the floor measured: on it, or a step up. A hull
-- is wider than a stair's tread, so on a stair or at its foot the next steps
-- stand within its reach; the body rides up on them, feet and head a step
-- higher, where a hull on the floor would be stopped by them.
RIDES = { 0, NavGaps.STEP_HEIGHT }

local function HullLineFits(from, to, start, finish, mins, maxs, mask, traceHull, vector)
	start = vector(start.x, start.y, 0)
	finish = vector(finish.x, finish.y, 0)
	local fromZ, toZ = from:GetZ(start), to:GetZ(finish)
	local height = (fromZ > toZ and fromZ or toZ) + 1
	-- on the floor, else riding a step (Clearance:Area)
	for _, lift in ipairs(RIDES) do
		start.z, finish.z = height + lift, height + lift
		local trace = traceHull({
			start = start,
			endpos = finish,
			mins = mins,
			maxs = maxs,
			mask = mask,
			filter = StaticMap,
		})
		if not trace.Hit and not trace.StartSolid then return true end
	end
	return false
end

local Clearance = {}
Clearance.__index = Clearance
local clearances = {}

local function StepMins(mins, maxs, vector)
	local step = NavGaps.STEP_HEIGHT
	local halfHeight = (maxs.z - mins.z) / 2
	if step > halfHeight then step = halfHeight end
	return vector(mins.x, mins.y, mins.z + step)
end

function FitsLines(lines, mins, maxs, mask, traceHull, vector)
	local traceMins = StepMins(mins, maxs, vector)
	for i = 1, #lines do
		local line = lines[i]
		for _, lift in ipairs(RIDES) do
			local start = vector(line.start.x, line.start.y, line.start.z + 1 + lift)
			local finish = vector(line.finish.x, line.finish.y, line.finish.z + 1 + lift)
			local trace = traceHull({
				start = start,
				endpos = finish,
				mins = traceMins,
				maxs = maxs,
				mask = mask,
				filter = StaticMap,
			})
			if not trace.Hit and not trace.StartSolid then return true end
		end
	end
	return false
end

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
	local traceMins = StepMins(mins, maxs, vector)
	local crouchMaxs = maxs
	if crouchHeight and crouchHeight < maxs.z then crouchMaxs = vector(maxs.x, maxs.y, crouchHeight) end
	local clearance = {
		hullMins = mins,
		hullMaxs = maxs,
		mins = traceMins,
		maxs = maxs,
		crouchHeight = crouchHeight,
		crouchMins = StepMins(mins, crouchMaxs, vector),
		crouchMaxs = crouchMaxs,
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
	center.z = area:GetZ(center)
	local crouched = HL2.MustCrouch(area:GetAttributes())
	local fits = false
	for _, lift in ipairs(RIDES) do
		local start = center + self.vector(0, 0, 1 + lift)
		local trace = self.traceHull({
			start = start,
			endpos = start,
			mins = crouched and self.crouchMins or self.mins,
			maxs = crouched and self.crouchMaxs or self.maxs,
			mask = self.mask,
			filter = StaticMap,
		})
		if not trace.Hit and not trace.StartSolid then
			fits = true
			break
		end
	end
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
	local mins, maxs = self.mins, self.maxs
	if crouched then mins, maxs = self.crouchMins, self.crouchMaxs end

	local fits = false
	if side == nil then
		local start = from:GetClosestPointOnArea(to:GetCenter())
		local finish = to:GetClosestPointOnArea(from:GetCenter())
		fits = HullLineFits(from, to, start, finish, mins, maxs,
			self.mask, self.traceHull, self.vector)
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
			local line = lines[i]
			if HullLineFits(from, to, line.start, line.finish, mins, maxs,
				self.mask, self.traceHull, self.vector) then
				fits = true
				break
			end
		end
	end
	links[toId] = fits
	return fits
end
