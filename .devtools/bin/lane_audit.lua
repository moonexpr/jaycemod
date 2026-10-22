-- Audits the AI war's lanes on the running server (dt lua -f .devtools/bin/lane_audit.lua):
-- every waypoint and every leg between two, as a soldier would walk it.
--   solid:   the waypoint is inside a brush (a soldier's hull cannot stand there)
--   offmesh: no nav area under the waypoint
--   blocked: a soldier's hull, above a step, hits a brush walking the leg
--   nofloor: a level leg (within a step) has no floor under it somewhere
-- Prints the counts per team and lane, then up to EXAMPLES legs with their points.
local EXAMPLES = 12
local STEP = 18
local LIFT = Vector(0, 0, STEP + 2)
local MINS, MAXS = Vector(-10, -10, 0), Vector(10, 10, 72 - STEP - 2)
local FLOOR_SAMPLE, FLOOR_BELOW = 16, STEP + 4
local mask = WS.ClipMasks().brushes
-- the world alone: a door shut now opens for the soldier
local function WorldOnly(ent) return ent:IsWorld() end

local function V(p) return Vector(p.x, p.y, p.z) end

local function Solid(p)
	return util.TraceHull({ start = p + LIFT, endpos = p + LIFT, mins = MINS, maxs = MAXS, mask = mask, filter = WorldOnly }).StartSolid
end

local function OffMesh(p)
	return not IsValid(navmesh.GetNavArea(p + Vector(0, 0, 16), 64))
end

local function Sweep(a, b)
	return util.TraceHull({ start = a + LIFT, endpos = b + LIFT, mins = MINS, maxs = MAXS, mask = mask, filter = WorldOnly }).Hit
end

-- Walked straight (a ramp, a stair), or for a drop walked out at the upper
-- height, then fallen; for a climb risen (a hop), then walked out.
local function Blocked(a, b)
	if not Sweep(a, b) then return false end -- a ramp or stair is walked straight
	if b.z < a.z - STEP then
		local over = Vector(b.x, b.y, a.z)
		return Sweep(a, over) or Sweep(over, b)
	elseif b.z > a.z + STEP then
		local up = Vector(a.x, a.y, b.z)
		return Sweep(a, up) or Sweep(up, b)
	end
	return Sweep(a, b)
end

local function NoFloor(a, b)
	if math.abs(a.z - b.z) > STEP then return false end
	-- Core-rule exception: LerpVector, not structs.polyline, as sv_map.lua's
	-- WorldWalkClear: a two-point polyline per leg costs more than the lerp.
	local n = math.floor(a:Distance(b) / FLOOR_SAMPLE)
	for i = 1, n do
		local p = LerpVector(i / (n + 1), a, b)
		if not util.TraceLine({ start = p + LIFT, endpos = p - Vector(0, 0, FLOOR_BELOW), mask = mask, filter = WorldOnly }).Hit then return true end
	end
	return false
end

local function Fmt(p) return string.format("(%.0f %.0f %.0f)", p.x, p.y, p.z) end

local out, examples, totals = {}, {}, { solid = 0, offmesh = 0, blocked = 0, nofloor = 0, legs = 0 }
for team, set in pairs(WS.Feature("aiwar").laneSets or {}) do
	for li, lane in ipairs(set) do
		local c = { solid = 0, offmesh = 0, blocked = 0, nofloor = 0 }
		local pts = lane.points
		for i, raw in ipairs(pts) do
			local p = V(raw)
			if Solid(p) then c.solid = c.solid + 1 examples[#examples + 1] = string.format("t%d l%d #%d solid %s", team, li, i, Fmt(p)) end
			if OffMesh(p) then c.offmesh = c.offmesh + 1 examples[#examples + 1] = string.format("t%d l%d #%d offmesh %s", team, li, i, Fmt(p)) end
			if i > 1 then
				local a = V(pts[i - 1])
				totals.legs = totals.legs + 1
				if Blocked(a, p) then c.blocked = c.blocked + 1 examples[#examples + 1] = string.format("t%d l%d #%d blocked %s -> %s", team, li, i, Fmt(a), Fmt(p)) end
				if NoFloor(a, p) then c.nofloor = c.nofloor + 1 examples[#examples + 1] = string.format("t%d l%d #%d nofloor %s -> %s", team, li, i, Fmt(a), Fmt(p)) end
			end
		end
		for k, v in pairs(c) do totals[k] = totals[k] + v end
		out[#out + 1] = string.format("team %d lane %d (%s, %d points): solid %d offmesh %d blocked %d nofloor %d",
			team, li, lane.kind, #pts, c.solid, c.offmesh, c.blocked, c.nofloor)
	end
end
out[#out + 1] = string.format("TOTAL legs %d: solid %d offmesh %d blocked %d nofloor %d",
	totals.legs, totals.solid, totals.offmesh, totals.blocked, totals.nofloor)
for i = 1, math.min(EXAMPLES, #examples) do out[#out + 1] = examples[i] end
return table.concat(out, "\n")
